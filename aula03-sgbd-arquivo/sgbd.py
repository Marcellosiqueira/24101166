"""
Simulacao de um SGBD sobre arquivo de texto.

Aula de Banco de Dados - IDP
Marcello Azevedo Pinheiro Siqueira - 24101166

Base: painel de voos (dados.txt), 30 registros, delimitador ';'.
Colunas: ID;NUMERO_VOO;DESTINO;PORTAO;HORARIO;STATUS

Desafio 1: Full Table Scan          -> SELECT * FROM voos
Desafio 2: Busca por chave primaria -> SELECT * FROM voos WHERE ID = X
Desafio 3: Filtro e projecao        -> SELECT col1, col2 FROM voos WHERE cond

O arquivo nunca e carregado inteiro na memoria. A leitura e sempre linha a linha,
como um SGBD faz ao trazer paginas do disco.
"""

import os
import time

ARQUIVO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dados.txt")
DELIMITADORES_CANDIDATOS = [";", "\t", ",", "|"]

# Colunas que devem ser comparadas como texto mesmo parecendo numero.
# PORTAO tem zero a esquerda ("08", "01"). Converter para numero funcionaria nas
# comparacoes, mas descaracteriza o dado: portao e identificador, nao quantidade.
COLUNAS_TEXTUAIS = {"PORTAO"}


# ---------------------------------------------------------------------------
# Camada de acesso ao "disco"
# ---------------------------------------------------------------------------

def detectar_delimitador(caminho):
    """Le a primeira linha e escolhe o caractere que mais aparece nela.

    Deixa o codigo funcionar sem alteracao se o arquivo vier com ; , tab ou |.
    """
    with open(caminho, "r", encoding="utf-8") as f:
        cabecalho = f.readline()
    contagem = {d: cabecalho.count(d) for d in DELIMITADORES_CANDIDATOS}
    delimitador = max(contagem, key=contagem.get)
    if contagem[delimitador] == 0:
        raise ValueError("Nao foi possivel identificar o delimitador do arquivo.")
    return delimitador


def ler_registros(caminho, delimitador):
    """Generator que devolve (numero_da_linha, lista_de_campos) por vez.

    Generator e nao lista: o consumo de memoria e constante, independente do
    tamanho do arquivo. readlines() traria o arquivo inteiro para a RAM.
    """
    with open(caminho, "r", encoding="utf-8") as f:
        next(f)  # descarta o cabecalho
        for numero, linha in enumerate(f, start=2):
            linha = linha.strip()
            if not linha:
                continue
            yield numero, linha.split(delimitador)


def ler_colunas(caminho, delimitador):
    with open(caminho, "r", encoding="utf-8") as f:
        return f.readline().strip().split(delimitador)


def imprimir_tabela(colunas, linhas):
    """Formata a saida com largura de coluna calculada, apenas para leitura."""
    if not linhas:
        print("(0 registros)")
        return
    larguras = [len(c) for c in colunas]
    for linha in linhas:
        for i, campo in enumerate(linha):
            larguras[i] = max(larguras[i], len(str(campo)))

    separador = "-+-".join("-" * w for w in larguras)
    print(" | ".join(c.ljust(larguras[i]) for i, c in enumerate(colunas)))
    print(separador)
    for linha in linhas:
        print(" | ".join(str(campo).ljust(larguras[i]) for i, campo in enumerate(linha)))
    print(f"\n({len(linhas)} registro(s))")


# ---------------------------------------------------------------------------
# Desafio 1: Full Table Scan
# ---------------------------------------------------------------------------

def full_table_scan(caminho=ARQUIVO):
    delimitador = detectar_delimitador(caminho)
    colunas = ler_colunas(caminho, delimitador)

    inicio = time.perf_counter()
    linhas = []
    for _, campos in ler_registros(caminho, delimitador):
        linhas.append(campos)
    duracao = time.perf_counter() - inicio

    print("\nSELECT * FROM voos;\n")
    imprimir_tabela(colunas, linhas)
    print(f"Linhas lidas: {len(linhas)} | Tempo: {duracao * 1000:.3f} ms")
    return linhas


# ---------------------------------------------------------------------------
# Desafio 2: Busca por chave primaria com early exit
# ---------------------------------------------------------------------------

def buscar_por_id(id_procurado, caminho=ARQUIVO, verbose=True):
    """Varre o arquivo ate achar o ID e para na hora. Retorna dict ou None.

    O contador linhas_lidas existe para tornar visivel o custo da busca: e ele
    que mostra por que um indice faz diferenca.
    """
    delimitador = detectar_delimitador(caminho)
    colunas = ler_colunas(caminho, delimitador)
    id_procurado = str(id_procurado).strip()

    linhas_lidas = 0
    inicio = time.perf_counter()

    for _, campos in ler_registros(caminho, delimitador):
        linhas_lidas += 1
        if campos[0].strip() == id_procurado:
            duracao = time.perf_counter() - inicio
            registro = dict(zip(colunas, campos))
            if verbose:
                print(f"\nSELECT * FROM voos WHERE ID = {id_procurado};\n")
                for coluna, valor in registro.items():
                    print(f"  {coluna:<12} : {valor}")
                print(f"\nEncontrado apos ler {linhas_lidas} de {contar_registros(caminho)} "
                      f"linha(s). Tempo: {duracao * 1000:.3f} ms")
                print("Leitura interrompida (early exit).")
            return registro

    duracao = time.perf_counter() - inicio
    if verbose:
        print(f"\nSELECT * FROM voos WHERE ID = {id_procurado};\n")
        print(f"Nenhum voo encontrado com ID = {id_procurado}.")
        print(f"Arquivo percorrido inteiro: {linhas_lidas} linha(s) lidas. "
              f"Tempo: {duracao * 1000:.3f} ms")
        print("Sem indice, provar que a chave nao existe custa o arquivo todo.")
    return None


def contar_registros(caminho=ARQUIVO):
    delimitador = detectar_delimitador(caminho)
    return sum(1 for _ in ler_registros(caminho, delimitador))


# ---------------------------------------------------------------------------
# Desafio 3: Filtro + projecao
# ---------------------------------------------------------------------------

OPERADORES = {
    ">":  lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "<":  lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    "=":  lambda a, b: a == b,
    "!=": lambda a, b: a != b,
}


def _converter(valor, coluna=None):
    """Tenta numero, cai para texto normalizado.

    Sem essa conversao a comparacao seria entre strings e NUMERO_VOO '9' > '10'
    retornaria True. HORARIO fica como texto de proposito: o formato HH:MM com
    zero a esquerda ja ordena corretamente na comparacao lexicografica.
    """
    if coluna in COLUNAS_TEXTUAIS:
        return str(valor).strip().lower()
    try:
        return float(str(valor).replace(",", "."))
    except (ValueError, AttributeError):
        return str(valor).strip().lower()


def consultar(projecao, coluna_filtro, operador, valor, caminho=ARQUIVO):
    """SELECT <projecao> FROM voos WHERE <coluna_filtro> <operador> <valor>."""
    if operador not in OPERADORES:
        raise ValueError(f"Operador invalido: {operador}")

    delimitador = detectar_delimitador(caminho)
    colunas = ler_colunas(caminho, delimitador)

    for nome in list(projecao) + [coluna_filtro]:
        if nome not in colunas:
            raise ValueError(f"Coluna inexistente: {nome}. Disponiveis: {colunas}")

    indice_filtro = colunas.index(coluna_filtro)
    indices_projecao = [colunas.index(c) for c in projecao]
    comparar = OPERADORES[operador]
    referencia = _converter(valor, coluna_filtro)

    linhas_lidas = 0
    resultado = []
    inicio = time.perf_counter()

    for _, campos in ler_registros(caminho, delimitador):
        linhas_lidas += 1
        try:
            if comparar(_converter(campos[indice_filtro], coluna_filtro), referencia):
                resultado.append([campos[i] for i in indices_projecao])
        except TypeError:
            # comparacao entre texto e numero: o registro simplesmente nao casa
            continue

    duracao = time.perf_counter() - inicio

    print(f"\nSELECT {', '.join(projecao)} FROM voos "
          f"WHERE {coluna_filtro} {operador} {valor};\n")
    imprimir_tabela(projecao, resultado)
    print(f"Linhas lidas: {linhas_lidas} | Linhas retornadas: {len(resultado)} | "
          f"Tempo: {duracao * 1000:.3f} ms")
    return resultado


# ---------------------------------------------------------------------------
# Extra: comparacao entre scan sequencial e indice hash
# ---------------------------------------------------------------------------

def construir_indice(caminho=ARQUIVO, coluna="ID"):
    """Indice hash valor -> offset em bytes no arquivo.

    Guarda a posicao fisica do registro, nao o registro. E o que uma arvore B+
    faz em disco: a folha aponta para o endereco do dado.
    """
    delimitador = detectar_delimitador(caminho)
    posicao_coluna = ler_colunas(caminho, delimitador).index(coluna)
    indice = {}
    with open(caminho, "rb") as f:
        f.readline()  # cabecalho
        offset = f.tell()
        for linha in f:
            texto = linha.decode("utf-8")
            if texto.strip():
                chave = texto.split(delimitador)[posicao_coluna].strip()
                indice.setdefault(chave, offset)
            offset += len(linha)
    return indice


def buscar_com_indice(valor, indice, handle, colunas, delimitador):
    """Busca usando o indice ja construido e um arquivo ja aberto.

    Recebe o handle pronto de proposito. Reabrir o arquivo a cada consulta
    custaria mais que a propria busca e mascararia o ganho do indice, que e
    justamente o que a medicao quer isolar.
    """
    offset = indice.get(str(valor).strip())
    if offset is None:
        return None
    handle.seek(offset)  # pula direto para o registro, um unico acesso
    campos = handle.readline().decode("utf-8").strip().split(delimitador)
    return dict(zip(colunas, campos))


def gerar_arquivo_grande(origem=ARQUIVO, destino="dados_grande.txt", repeticoes=10000):
    """Replica a base original N vezes, reatribuindo IDs sequenciais.

    Serve so para o benchmark: com 30 linhas nao da para observar a diferenca
    entre O(n) e O(1), o tempo fica todo em abrir o arquivo.
    """
    delimitador = detectar_delimitador(origem)
    colunas = ler_colunas(origem, delimitador)
    base = [campos for _, campos in ler_registros(origem, delimitador)]

    novo_id = 0
    with open(destino, "w", encoding="utf-8") as saida:
        saida.write(delimitador.join(colunas) + "\n")
        for _ in range(repeticoes):
            for campos in base:
                novo_id += 1
                saida.write(delimitador.join([str(novo_id)] + campos[1:]) + "\n")
    return destino, novo_id


def comparar_scan_vs_indice(caminho=ARQUIVO):
    """Mede scan sequencial contra indice hash em duas escalas."""
    print("\nComparacao: scan sequencial x indice hash")
    print("Em cada escala busca-se o ultimo ID do arquivo, pior caso do scan.\n")

    grande, total_grande = gerar_arquivo_grande()
    cenarios = [("base original", caminho), (f"base replicada", grande)]

    print(f"{'Escala':<16} | {'Registros':>10} | {'Scan (ms)':>12} | "
          f"{'Indice (ms)':>12} | {'Ganho':>8}")
    print("-" * 72)

    try:
        for rotulo, arquivo in cenarios:
            delimitador = detectar_delimitador(arquivo)
            colunas = ler_colunas(arquivo, delimitador)
            total = contar_registros(arquivo)
            alvo = str(total)  # IDs sao sequenciais de 1 a total

            inicio = time.perf_counter()
            buscar_por_id(alvo, arquivo, verbose=False)
            tempo_scan = time.perf_counter() - inicio

            indice = construir_indice(arquivo)
            with open(arquivo, "rb") as handle:
                inicio = time.perf_counter()
                buscar_com_indice(alvo, indice, handle, colunas, delimitador)
                tempo_indice = time.perf_counter() - inicio

            ganho = tempo_scan / tempo_indice if tempo_indice > 0 else float("inf")
            print(f"{rotulo:<16} | {total:>10,} | {tempo_scan * 1000:>12.4f} | "
                  f"{tempo_indice * 1000:>12.4f} | {ganho:>7.0f}x")
    finally:
        if os.path.exists(grande):
            os.remove(grande)

    print(f"\nO scan cresce proporcional ao numero de registros. A busca indexada")
    print(f"fica praticamente constante: um seek e uma linha lida, seja em 30 ou")
    print(f"em {total_grande:,} registros.")
    print("O indice tem custo de construcao e de manutencao a cada escrita, pago")
    print("uma vez em troca de todas as consultas seguintes.")


# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

def menu():
    if not os.path.exists(ARQUIVO):
        print(f"Arquivo nao encontrado: {ARQUIVO}")
        return

    opcoes = {
        "1": "Full Table Scan (SELECT *)",
        "2": "Buscar voo por ID (WHERE ID = X)",
        "3": "Filtro + projecao (SELECT cols WHERE cond)",
        "4": "Comparar scan sequencial x indice hash",
        "0": "Sair",
    }

    while True:
        print("\n" + "=" * 58)
        print("SGBD didatico sobre arquivo texto - painel de voos")
        print("=" * 58)
        for chave, texto in opcoes.items():
            print(f"  {chave}. {texto}")

        escolha = input("\nOpcao: ").strip()

        if escolha == "1":
            full_table_scan()

        elif escolha == "2":
            buscar_por_id(input("ID do voo: ").strip())

        elif escolha == "3":
            delimitador = detectar_delimitador(ARQUIVO)
            colunas = ler_colunas(ARQUIVO, delimitador)
            print(f"\nColunas disponiveis: {', '.join(colunas)}")
            print("Exemplo: NUMERO_VOO,PORTAO  |  DESTINO  |  =  |  Brasilia")
            projecao = [c.strip().upper() for c in
                        input("Colunas a exibir (separadas por virgula): ").split(",")]
            coluna_filtro = input("Coluna do filtro: ").strip().upper()
            operador = input(f"Operador {list(OPERADORES)}: ").strip()
            valor = input("Valor: ").strip()
            try:
                consultar(projecao, coluna_filtro, operador, valor)
            except ValueError as erro:
                print(f"Erro: {erro}")

        elif escolha == "4":
            comparar_scan_vs_indice()

        elif escolha == "0":
            break

        else:
            print("Opcao invalida.")


if __name__ == "__main__":
    menu()
