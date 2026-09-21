"""
Aula 16 - Locking, Deadlocks e MVCC
Disciplina de Banco de Dados - IDP
Marcello Azevedo Pinheiro Siqueira - 24101166

Harness dos experimentos de concorrencia.

POR QUE UM HARNESS, E NAO DOIS TERMINAIS

O enunciado pede para abrir duas sessoes e intercalar comandos a mao. Feito
assim, o resultado depende da velocidade de quem digita: nao da para afirmar
que a sessao 2 esperou por causa do bloqueio e nao porque o comando foi colado
tarde. Este arquivo abre DUAS CONEXOES TCP REAIS e independentes com o MySQL,
cada uma na sua thread, e usa barreiras (threading.Event) para garantir a ordem
exata dos passos. Cada conexao tem o seu proprio CONNECTION_ID, a sua propria
transacao e o seu proprio read view - sao duas sessoes de verdade, nao duas
consultas na mesma.

O que a thread ganha: quando a sessao 2 trava num FOR UPDATE, e a thread dela
que fica parada. A sessao 1 continua andando e da COMMIT. Esse e o ponto
inteiro do exercicio, e nao seria observavel num script de uma unica conexao.

Todos os tempos sao medidos com time.monotonic() em volta da chamada que
bloqueia. Os numeros que o concorrencia.md reporta saem da saida deste arquivo.

    python harness.py            # roda os cinco experimentos
    python harness.py --json     # a mesma coisa, com um dump JSON no fim

Dependencia: mysql-connector-python (as outras aulas nao usam nada externo).
"""

import argparse
import json
import sys
import threading
import time

import mysql.connector

CONEXAO = {
    "host": "127.0.0.1",
    "port": 3308,
    "user": "root",
    "password": "root",
    "database": "aeroporto_concorrencia",
    "autocommit": True,  # transacao controlada na mao, com START TRANSACTION
}

T0 = time.monotonic()
_impressao = threading.Lock()
_eventos = []


def log(sessao, texto):
    """Imprime uma linha da timeline com o instante relativo ao inicio."""
    t = time.monotonic() - T0
    with _impressao:
        _eventos.append({"t": round(t, 3), "sessao": sessao, "evento": texto})
        print(f"  [{t:7.3f}s] {sessao:>3} | {texto}", flush=True)


class Sessao:
    """Uma conexao TCP real com o MySQL, identificada pelo seu CONNECTION_ID."""

    def __init__(self, nome):
        self.nome = nome
        self.cnx = mysql.connector.connect(**CONEXAO)
        self.cur = self.cnx.cursor()
        self.cur.execute("SELECT CONNECTION_ID()")
        self.id_conexao = self.cur.fetchone()[0]

    def exec(self, sql, esperado_ok=True):
        """Executa e devolve (linhas, erro). Nunca levanta: o erro e o dado."""
        try:
            self.cur.execute(sql)
            linhas = self.cur.fetchall() if self.cur.with_rows else None
            return linhas, None
        except mysql.connector.Error as e:
            return None, e

    def fecha(self):
        try:
            self.cur.close()
            self.cnx.close()
        except mysql.connector.Error:
            pass


def resetar():
    """Volta os tres assentos para DISPONIVEL e zera as reservas."""
    s = Sessao("adm")
    s.exec("CALL sp_resetar_cenario()")
    linhas, _ = s.exec("SELECT numero, status FROM assentos ORDER BY numero")
    s.fecha()
    return linhas


def estado():
    s = Sessao("adm")
    assentos, _ = s.exec("SELECT numero, status FROM assentos ORDER BY numero")
    reservas, _ = s.exec(
        "SELECT r.id, p.nome, a.numero, r.status "
        "FROM reservas r "
        "JOIN passageiros p ON p.id = r.passageiro_id "
        "JOIN assentos a ON a.id = r.assento_id ORDER BY r.id"
    )
    s.fecha()
    return assentos, reservas


def cabecalho(titulo, pergunta):
    print()
    print("=" * 78)
    print(titulo)
    print("=" * 78)
    print(f"Pergunta: {pergunta}")
    print("-" * 78)


def mostra_estado(rotulo="Estado final"):
    assentos, reservas = estado()
    print("-" * 78)
    print(f"{rotulo}:")
    print("  assentos:", ", ".join(f"{n}={s}" for n, s in assentos))
    if reservas:
        for rid, nome, numero, st in reservas:
            print(f"  reserva {rid}: {nome} -> {numero} ({st})")
    else:
        print("  reservas: nenhuma")


# =============================================================================
# Experimento A1 - duas sessoes disputam o mesmo assento pelo procedimento
# =============================================================================
# S1 chama o procedimento e ganha. S2 chama o mesmo procedimento para o MESMO
# assento enquanto S1 ainda esta no meio da transacao. O FOR UPDATE de S2 fica
# esperando; quando S1 confirma, S2 acorda, rele o status ja como RESERVADO e e
# recusada pela revalidacao pos-lock.
#
# O "meio da transacao" de S1 e obtido rodando os passos do procedimento na mao
# na sessao 1, porque o procedimento inteiro commita sozinho e nao daria janela
# para intercalar nada. S2 chama o procedimento de verdade - e o lado de S2 que
# esta sob teste.

def experimento_a1(segurar=2.0):
    cabecalho(
        "EXPERIMENTO A1 - duas sessoes, o mesmo assento, pelo procedimento",
        "quem ganha o assento 10A, e o que a perdedora recebe?",
    )
    resetar()

    s1, s2 = Sessao("S1"), Sessao("S2")
    log("S1", f"conectada, CONNECTION_ID = {s1.id_conexao}")
    log("S2", f"conectada, CONNECTION_ID = {s2.id_conexao}")

    lock_tomado = threading.Event()
    resultado = {}

    def tarefa_s1():
        s1.exec("START TRANSACTION")
        log("S1", "START TRANSACTION")
        linhas, _ = s1.exec(
            "SELECT id, status FROM assentos WHERE voo_id = 1 AND numero = '10A' FOR UPDATE"
        )
        log("S1", f"SELECT ... FOR UPDATE -> id={linhas[0][0]}, status={linhas[0][1]} (linha bloqueada)")
        lock_tomado.set()

        s1.exec("UPDATE assentos SET status = 'RESERVADO' WHERE id = 1 AND status = 'DISPONIVEL'")
        log("S1", "UPDATE assentos SET status = 'RESERVADO'")
        s1.exec("INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA')")
        log("S1", "INSERT na reservas")

        log("S1", f"segurando o bloqueio por {segurar}s (sem COMMIT) de proposito")
        time.sleep(segurar)

        s1.exec("COMMIT")
        log("S1", "COMMIT - bloqueio liberado")

    def tarefa_s2():
        lock_tomado.wait()
        log("S2", "chama sp_reservar_assento(2, 1, '10A') - vai travar no FOR UPDATE")
        inicio = time.monotonic()
        _, erro = s2.exec("CALL sp_reservar_assento(2, 1, '10A')")
        espera = time.monotonic() - inicio
        resultado["espera_s2"] = espera
        if erro:
            resultado["erro_s2"] = (erro.errno, erro.msg)
            log("S2", f"destravou depois de {espera:.3f}s e foi RECUSADA")
            log("S2", f"ERRO {erro.errno}: {erro.msg}")
        else:
            resultado["erro_s2"] = None
            log("S2", f"destravou depois de {espera:.3f}s e foi ACEITA (inesperado)")

    t1 = threading.Thread(target=tarefa_s1)
    t2 = threading.Thread(target=tarefa_s2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    s1.fecha()
    s2.fecha()

    mostra_estado()
    resultado["segurar"] = segurar
    return resultado


# =============================================================================
# Experimento A2 - a UNIQUE da coluna gerada agindo sozinha
# =============================================================================
# Nenhum procedimento, nenhum FOR UPDATE, nenhuma revalidacao: duas sessoes
# inserem a reserva do mesmo assento direto na tabela. E o cenario do cliente
# que ignora a camada de aplicacao. A ultima barreira e a UNIQUE
# (assento_ativo), e o erro esperado e 1062.

def experimento_a2():
    cabecalho(
        "EXPERIMENTO A2 - sem procedimento e sem FOR UPDATE, so a UNIQUE",
        "a restricao segura a duplicidade quando o cliente nao colabora?",
    )
    resetar()

    s1, s2 = Sessao("S1"), Sessao("S2")
    resultado = {}

    log("S1", "INSERT direto na reservas (assento 1), sem transacao explicita")
    _, e1 = s1.exec("INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA')")
    log("S1", "aceito" if not e1 else f"ERRO {e1.errno}: {e1.msg}")

    log("S2", "INSERT direto na reservas para o MESMO assento 1")
    _, e2 = s2.exec("INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (2, 1, 'CONFIRMADA')")
    if e2:
        resultado["erro_s2"] = (e2.errno, e2.msg)
        log("S2", f"ERRO {e2.errno}: {e2.msg}")
    else:
        resultado["erro_s2"] = None
        log("S2", "aceito (inesperado - a duplicidade passou)")

    # Contraprova: cancelar a reserva de S1 libera o assento, porque a coluna
    # gerada vira NULL e sai da UNIQUE.
    log("S1", "UPDATE reservas SET status = 'CANCELADA' (libera o assento_ativo)")
    s1.exec("UPDATE reservas SET status = 'CANCELADA' WHERE assento_id = 1")
    log("S2", "tenta de novo o mesmo INSERT depois do cancelamento")
    _, e3 = s2.exec("INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (2, 1, 'CONFIRMADA')")
    resultado["apos_cancelamento"] = None if not e3 else (e3.errno, e3.msg)
    log("S2", "aceito - o cancelamento devolveu o assento" if not e3 else f"ERRO {e3.errno}: {e3.msg}")

    s1.fecha()
    s2.fecha()
    mostra_estado()
    return resultado


# =============================================================================
# Experimento B - quanto tempo a sessao 2 espera
# =============================================================================
# Mesma disputa do A1, mas o interesse aqui e o tempo. S1 segura o bloqueio por
# um intervalo conhecido e S2 mede quanto tempo o seu FOR UPDATE ficou parado.
# Se a espera medida acompanha o tempo de retencao, esta provado que quem
# determina a duracao do bloqueio e o COMMIT da concorrente, e nao o acaso.

def experimento_b(tempos=(1.0, 3.0)):
    cabecalho(
        "EXPERIMENTO B - a duracao da espera e o COMMIT da outra sessao",
        "a espera de S2 acompanha o tempo que S1 segura o bloqueio?",
    )
    medicoes = []

    for segurar in tempos:
        resetar()
        s1, s2 = Sessao("S1"), Sessao("S2")
        lock_tomado = threading.Event()
        caixa = {}

        def tarefa_s1():
            s1.exec("START TRANSACTION")
            s1.exec("SELECT id FROM assentos WHERE id = 1 FOR UPDATE")
            lock_tomado.set()
            time.sleep(segurar)
            s1.exec("COMMIT")

        def tarefa_s2():
            lock_tomado.wait()
            s2.exec("START TRANSACTION")
            inicio = time.monotonic()
            s2.exec("SELECT id FROM assentos WHERE id = 1 FOR UPDATE")
            caixa["espera"] = time.monotonic() - inicio
            s2.exec("COMMIT")

        t1 = threading.Thread(target=tarefa_s1)
        t2 = threading.Thread(target=tarefa_s2)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
        s1.fecha()
        s2.fecha()

        espera = caixa["espera"]
        atraso = espera - segurar
        log("S2", f"S1 segurou {segurar:.1f}s -> S2 esperou {espera:.3f}s (diferenca {atraso:+.3f}s)")
        medicoes.append({"segurou": segurar, "esperou": round(espera, 3), "diferenca": round(atraso, 3)})

    return {"medicoes": medicoes}


# =============================================================================
# Experimento C - estouro do tempo de espera (erro 1205)
# =============================================================================
# innodb_lock_wait_timeout e por sessao. S2 baixa o seu para 2 segundos e S1
# segura o bloqueio por mais do que isso. A espera nao e infinita: o servidor
# derruba o comando de S2 com 1205 e a transacao dela fica intacta para decidir
# o que fazer.

def experimento_c(timeout_s2=2, segurar=6.0):
    cabecalho(
        "EXPERIMENTO C - innodb_lock_wait_timeout e o erro 1205",
        "o que acontece quando a espera passa do limite da sessao?",
    )
    resetar()

    s1, s2 = Sessao("S1"), Sessao("S2")
    lock_tomado = threading.Event()
    resultado = {"timeout_s2": timeout_s2, "segurar": segurar}

    def tarefa_s1():
        s1.exec("START TRANSACTION")
        s1.exec("SELECT id FROM assentos WHERE id = 1 FOR UPDATE")
        log("S1", f"bloqueio tomado, vai segurar por {segurar}s")
        lock_tomado.set()
        time.sleep(segurar)
        s1.exec("COMMIT")
        log("S1", "COMMIT")

    def tarefa_s2():
        s2.exec(f"SET SESSION innodb_lock_wait_timeout = {timeout_s2}")
        linhas, _ = s2.exec("SELECT @@innodb_lock_wait_timeout")
        log("S2", f"innodb_lock_wait_timeout da sessao = {linhas[0][0]}s")
        lock_tomado.wait()
        s2.exec("START TRANSACTION")
        log("S2", "SELECT ... FOR UPDATE no assento ja bloqueado")
        inicio = time.monotonic()
        _, erro = s2.exec("SELECT id FROM assentos WHERE id = 1 FOR UPDATE")
        espera = time.monotonic() - inicio
        resultado["espera_s2"] = round(espera, 3)
        if erro:
            resultado["erro_s2"] = (erro.errno, erro.msg)
            log("S2", f"ERRO {erro.errno} depois de {espera:.3f}s: {erro.msg}")
        else:
            resultado["erro_s2"] = None
            log("S2", f"passou depois de {espera:.3f}s (inesperado)")
        # A transacao de S2 sobrevive ao 1205: so o comando foi desfeito.
        linhas, _ = s2.exec("SELECT COUNT(*) FROM assentos")
        if linhas:
            log("S2", f"a transacao continua viva apos o 1205 (SELECT simples: {linhas[0][0]} assentos)")
            resultado["transacao_viva"] = True
        s2.exec("ROLLBACK")

    t1 = threading.Thread(target=tarefa_s1)
    t2 = threading.Thread(target=tarefa_s2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    s1.fecha()
    s2.fecha()
    mostra_estado()
    return resultado


# =============================================================================
# Experimento D - deadlock (erro 1213)
# =============================================================================
# S1 bloqueia o assento 10A e depois quer o 10B. S2 bloqueia o 10B e depois
# quer o 10A. Cada uma espera um recurso que a outra detem: ciclo fechado. O
# InnoDB detecta o ciclo e mata uma das duas imediatamente, sem esperar
# timeout. A vitima recebe 1213 e a sua transacao inteira e desfeita - e a
# diferenca em relacao ao 1205 do Experimento C.
#
# O WHERE PRECISA SER (voo_id, numero), NAO SO numero
#
# A primeira versao deste experimento filtrava por "numero = 10A" e nunca
# produziu deadlock: as duas sessoes ficavam 50s paradas e saiam por 1205. O
# motivo esta no Experimento F - sem voo_id o indice uq_assento_voo nao pode
# ser usado para acesso direto, o FOR UPDATE varre o indice inteiro e bloqueia
# TODAS as linhas. S1 ja detinha 10A, 10B e 10C, entao S2 travava no seu
# PRIMEIRO bloqueio e o ciclo nunca se formava. Com o par (voo_id, numero) o
# acesso e type=const e cada sessao bloqueia exatamente uma linha.
#
# O timeout das duas sessoes e reduzido para 5s: se o ciclo nao se formar, o
# experimento falha rapido em vez de ficar 50s parado escondendo o problema.

def experimento_d():
    cabecalho(
        "EXPERIMENTO D - deadlock por ordem invertida de bloqueio (1213)",
        "o servidor detecta o ciclo, e o que sobra da transacao da vitima?",
    )
    resetar()

    s1, s2 = Sessao("S1"), Sessao("S2")
    primeiro_par = threading.Barrier(2)
    resultado = {}

    def tarefa(sessao, primeiro, segundo, caixa):
        sessao.exec("SET SESSION innodb_lock_wait_timeout = 5")
        sessao.exec("START TRANSACTION")
        # Par completo da UNIQUE: bloqueia UMA linha (type=const). Ver Exp. F.
        _, erro = sessao.exec(
            "SELECT id FROM assentos WHERE voo_id = 1 AND numero = '%s' FOR UPDATE" % primeiro
        )
        if erro:
            # Nunca deve acontecer: e o primeiro bloqueio, ninguem o disputa.
            caixa["erro_primeiro_lock"] = (erro.errno, erro.msg)
            log(sessao.nome, "ERRO INESPERADO ao bloquear %s: %s %s" % (primeiro, erro.errno, erro.msg))
            sessao.exec("ROLLBACK")
            primeiro_par.wait()
            return
        log(sessao.nome, "bloqueou %s (uma linha)" % primeiro)
        primeiro_par.wait()  # garante que as duas ja tem o seu primeiro lock
        log(sessao.nome, "agora pede %s - que a outra sessao detem" % segundo)
        inicio = time.monotonic()
        _, erro = sessao.exec(
            "SELECT id FROM assentos WHERE voo_id = 1 AND numero = '%s' FOR UPDATE" % segundo
        )
        decorrido = time.monotonic() - inicio
        caixa["tempo"] = round(decorrido, 3)
        if erro:
            caixa["erro"] = (erro.errno, erro.msg)
            log(sessao.nome, "ERRO %s depois de %.3fs: %s" % (erro.errno, decorrido, erro.msg))
            sessao.exec("ROLLBACK")
        else:
            caixa["erro"] = None
            log(sessao.nome, "conseguiu %s depois de %.3fs - sobreviveu" % (segundo, decorrido))
            sessao.exec("COMMIT")
            log(sessao.nome, "COMMIT")

    c1, c2 = {}, {}
    t1 = threading.Thread(target=tarefa, args=(s1, "10A", "10B", c1))
    t2 = threading.Thread(target=tarefa, args=(s2, "10B", "10A", c2))
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    resultado["s1"] = c1
    resultado["s2"] = c2
    vitimas = [n for n, c in (("S1", c1), ("S2", c2)) if c.get("erro")]
    sobreviventes = [n for n, c in (("S1", c1), ("S2", c2))
                     if c.get("erro") is None and "tempo" in c]
    resultado["vitima"] = vitimas
    resultado["sobrevivente"] = sobreviventes
    print("-" * 78)
    print("Vitima do InnoDB: %s | sobrevivente: %s" % (
        ", ".join(vitimas) if vitimas else "nenhuma",
        ", ".join(sobreviventes) if sobreviventes else "nenhuma"))

    # O servidor registra o ultimo deadlock; e a prova de que foi ciclo (1213) e
    # nao espera esgotada (1205).
    adm = Sessao("adm")
    linhas, _ = adm.exec("SHOW ENGINE INNODB STATUS")
    if linhas:
        texto = linhas[0][2]
        bloco = texto.split("LATEST DETECTED DEADLOCK")
        if len(bloco) > 1:
            trecho = [l for l in bloco[1].splitlines() if l.strip()][:6]
            resultado["innodb_status"] = trecho
            print("SHOW ENGINE INNODB STATUS, secao LATEST DETECTED DEADLOCK:")
            for linha in trecho:
                print("  %s" % linha)
    adm.fecha()
    s1.fecha()
    s2.fecha()
    mostra_estado()
    return resultado


# =============================================================================
# Experimento F - o WHERE decide quantas linhas ficam bloqueadas
# =============================================================================
# Este experimento nao estava previsto: ele nasceu de um defeito real no
# Experimento D, que filtrava por "numero = 10A" e por isso nunca deadlockou.
#
# O InnoDB nao bloqueia "a linha que o WHERE descreve": bloqueia toda linha que
# precisou EXAMINAR para avaliar o WHERE. A tabela assentos tem UNIQUE
# (voo_id, numero); numero nao e prefixo a esquerda desse indice, entao
# "WHERE numero = 10A" nao tem acesso direto e vira varredura do indice:
#
#   EXPLAIN ... WHERE numero = 10A                  -> type=index, rows=3
#   EXPLAIN ... WHERE voo_id = 1 AND numero = 10A   -> type=const, rows=1
#
# Consequencia pratica: com o WHERE ruim, uma reserva do assento 10A impede a
# reserva SIMULTANEA do 10B e do 10C, que nada tem a ver com ela. O sistema
# perde a concorrencia inteira sem que nenhuma regra de negocio peca isso, e o
# sintoma no cliente e um 1205 depois de 50s - nao um erro de logica.
#
# S1 bloqueia por um predicado e S2 tenta bloquear OUTRO assento. Se S2 travar,
# esta provado que o bloqueio de S1 passou do assento que ela pediu.

def experimento_f():
    cabecalho(
        "EXPERIMENTO F - predicado sem indice bloqueia linhas que nao foram pedidas",
        "o bloqueio de S1 no 10A alcanca o 10B?",
    )
    medicoes = []

    cenarios = (
        ("sem indice (numero = 10A)", "numero = '10A'"),
        ("com indice (voo_id = 1 AND numero = 10A)", "voo_id = 1 AND numero = '10A'"),
    )

    for rotulo, where_s1 in cenarios:
        resetar()
        s1, s2 = Sessao("S1"), Sessao("S2")
        lock_tomado = threading.Event()
        caixa = {}

        def tarefa_s1(where_s1=where_s1):
            s1.exec("START TRANSACTION")
            s1.exec("SELECT id FROM assentos WHERE %s FOR UPDATE" % where_s1)
            lock_tomado.set()
            time.sleep(3.0)
            s1.exec("COMMIT")

        def tarefa_s2():
            # Timeout curto: o interesse e se trava, nao quanto tempo trava.
            s2.exec("SET SESSION innodb_lock_wait_timeout = 1")
            lock_tomado.wait()
            s2.exec("START TRANSACTION")
            # S2 quer o 10B, um assento DIFERENTE, e sempre pelo par completo.
            _, erro = s2.exec(
                "SELECT id FROM assentos WHERE voo_id = 1 AND numero = '10B' FOR UPDATE"
            )
            caixa["erro"] = (erro.errno, erro.msg) if erro else None
            s2.exec("ROLLBACK")

        t1 = threading.Thread(target=tarefa_s1)
        t2 = threading.Thread(target=tarefa_s2)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
        s1.fecha()
        s2.fecha()

        erro = caixa["erro"]
        if erro:
            log("S2", "S1 com WHERE %s: S2 NAO conseguiu o 10B -> %s %s" % (rotulo, erro[0], erro[1]))
        else:
            log("S2", "S1 com WHERE %s: S2 conseguiu o 10B normalmente" % rotulo)
        medicoes.append({"where_s1": where_s1, "rotulo": rotulo,
                         "s2_bloqueada": erro is not None,
                         "erro_s2": erro})

    # O EXPLAIN que explica a diferenca.
    adm = Sessao("adm")
    planos = {}
    print("-" * 78)
    for chave_rot, w in (("sem_indice", "numero = '10A'"),
                         ("com_indice", "voo_id = 1 AND numero = '10A'")):
        linhas, _ = adm.exec("EXPLAIN SELECT id FROM assentos WHERE %s FOR UPDATE" % w)
        # Colunas do EXPLAIN: 0 id, 1 select_type, 2 table, 3 partitions,
        # 4 type, 5 possible_keys, 6 key, 7 key_len, 8 ref, 9 rows.
        tipo, chave, nlinhas = linhas[0][4], linhas[0][6], linhas[0][9]
        planos[chave_rot] = {"type": tipo, "key": chave, "rows": nlinhas}
        print("  EXPLAIN %-38s -> type=%s, key=%s, rows=%s" % (w, tipo, chave, nlinhas))
    adm.fecha()
    mostra_estado()
    return {"medicoes": medicoes, "explain": planos}


# =============================================================================
# Experimento E - MVCC: o retrato da transacao contra a versao confirmada
# =============================================================================
# S2 abre a transacao e le o assento SEM bloqueio, fixando o seu read view. S1
# entao altera o assento e da COMMIT. S2 rele:
#
#   - com SELECT simples, continua vendo DISPONIVEL. Em REPEATABLE READ o
#     retrato e do instante da primeira leitura, e o MVCC entrega a versao
#     antiga guardada no undo log. Nao e cache do cliente: e versionamento.
#   - com SELECT ... FOR UPDATE, ve RESERVADO. A leitura bloqueante ignora o
#     retrato e vai na versao confirmada mais recente.
#
# As duas respostas saem da MESMA transacao, a segundos de distancia. E por
# isso que a revalidacao do procedimento e feita com FOR UPDATE e nao com um
# SELECT comum - com SELECT comum ela leria o valor velho e autorizaria a
# reserva dobrada.
#
# No PostgreSQL, cujo padrao e READ COMMITTED, o SELECT simples de S2 ja veria
# RESERVADO. A diferenca de padrao entre os dois bancos muda esta saida.

def experimento_e():
    cabecalho(
        "EXPERIMENTO E - MVCC em REPEATABLE READ",
        "a mesma transacao pode ver dois valores diferentes da mesma linha?",
    )
    resetar()

    s1, s2 = Sessao("S1"), Sessao("S2")
    snapshot_feito = threading.Event()
    s1_commitou = threading.Event()
    resultado = {}

    def tarefa_s2():
        s2.exec("START TRANSACTION")
        linhas, _ = s2.exec("SELECT status FROM assentos WHERE id = 1")
        resultado["leitura_1"] = linhas[0][0]
        log("S2", f"START TRANSACTION + SELECT simples -> {linhas[0][0]} (read view fixado)")
        snapshot_feito.set()

        s1_commitou.wait()

        linhas, _ = s2.exec("SELECT status FROM assentos WHERE id = 1")
        resultado["leitura_2"] = linhas[0][0]
        log("S2", f"SELECT simples DEPOIS do COMMIT de S1 -> {linhas[0][0]} (retrato do MVCC)")

        linhas, _ = s2.exec("SELECT status FROM assentos WHERE id = 1 FOR UPDATE")
        resultado["leitura_3"] = linhas[0][0]
        log("S2", f"SELECT ... FOR UPDATE na MESMA transacao -> {linhas[0][0]} (versao confirmada)")

        s2.exec("COMMIT")
        linhas, _ = s2.exec("SELECT status FROM assentos WHERE id = 1")
        resultado["leitura_4"] = linhas[0][0]
        log("S2", f"depois do COMMIT, transacao nova -> {linhas[0][0]}")

    def tarefa_s1():
        snapshot_feito.wait()
        s1.exec("START TRANSACTION")
        s1.exec("UPDATE assentos SET status = 'RESERVADO' WHERE id = 1")
        log("S1", "UPDATE assentos SET status = 'RESERVADO' WHERE id = 1")
        s1.exec("COMMIT")
        log("S1", "COMMIT")
        s1_commitou.set()

    t2 = threading.Thread(target=tarefa_s2)
    t1 = threading.Thread(target=tarefa_s1)
    t2.start()
    t1.start()
    t2.join()
    t1.join()
    s1.fecha()
    s2.fecha()

    print("-" * 78)
    print(f"  leitura 1 (antes do UPDATE de S1)          : {resultado['leitura_1']}")
    print(f"  leitura 2 (SELECT simples, apos o COMMIT)  : {resultado['leitura_2']}")
    print(f"  leitura 3 (FOR UPDATE, mesma transacao)    : {resultado['leitura_3']}")
    print(f"  leitura 4 (transacao nova)                 : {resultado['leitura_4']}")
    mostra_estado()
    return resultado


def main():
    ap = argparse.ArgumentParser(description="Experimentos de concorrencia da Aula 16")
    ap.add_argument("--json", action="store_true", help="imprime um dump JSON no fim")
    args = ap.parse_args()

    try:
        s = Sessao("adm")
    except mysql.connector.Error as e:
        print(f"Nao foi possivel conectar em {CONEXAO['host']}:{CONEXAO['port']}: {e}")
        print("O contêiner mysql esta rodando e o concorrencia.sql ja foi carregado?")
        return 1

    linhas, _ = s.exec(
        "SELECT VERSION(), @@transaction_isolation, @@innodb_lock_wait_timeout, "
        "@@innodb_deadlock_detect"
    )
    versao, isolamento, timeout, deteccao = linhas[0]
    s.fecha()

    print("=" * 78)
    print("Aula 16 - experimentos de concorrencia com duas conexoes reais")
    print("=" * 78)
    print(f"  MySQL                     : {versao}")
    print(f"  isolamento padrao         : {isolamento}")
    print(f"  innodb_lock_wait_timeout  : {timeout}s")
    print(f"  innodb_deadlock_detect    : {deteccao}")

    saida = {
        "ambiente": {
            "versao": versao,
            "isolamento": isolamento,
            "lock_wait_timeout": timeout,
            "deadlock_detect": deteccao,
        },
        "a1": experimento_a1(),
        "a2": experimento_a2(),
        "b": experimento_b(),
        "c": experimento_c(),
        "d": experimento_d(),
        "e": experimento_e(),
        "f": experimento_f(),
    }

    resetar()
    print()
    print("=" * 78)
    print("Fim. Cenario resetado.")
    print("=" * 78)

    if args.json:
        saida["timeline"] = _eventos
        print()
        print(json.dumps(saida, indent=2, ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
