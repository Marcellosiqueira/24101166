# Aula 16 — Locking, deadlocks e MVCC

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Controle de concorrência em um cenário de reserva de assentos: bloqueio pessimista com
`SELECT ... FOR UPDATE`, espera por bloqueio, estouro de tempo de espera, deadlock e
MVCC, cada um medido com duas conexões simultâneas reais.

| Arquivo | Conteúdo |
|---|---|
| `concorrencia.sql` | Esquema, dados de teste, `sp_reservar_assento` e `sp_resetar_cenario` |
| `harness.py` | Os seis experimentos, com duas conexões TCP independentes |
| `concorrencia.md` | Estratégia, resultados medidos e respostas às perguntas |

```bash
mysql -u root -p < concorrencia.sql
python harness.py            # roda os seis experimentos
python harness.py --json     # a mesma coisa, com dump JSON da timeline
```

**Ambiente de medição.** MySQL 8.0.46 em contêiner Docker (`mysql:8.0`) no Windows 11,
porta 3308. Nível de isolamento padrão `REPEATABLE-READ`,
`innodb_lock_wait_timeout = 50s`, `innodb_deadlock_detect = 1`. **Todo número deste
documento veio da execução do `harness.py` nesse ambiente.** Onde um valor não foi
medido, está escrito que não foi.

O `harness.py` depende de `mysql-connector-python`. É a única aula do repositório com
dependência externa, e o motivo está na seção 4.

---

## 1. Por que um banco separado, e não o `aeroporto` das outras aulas

O banco desta aula é o `aeroporto_concorrencia`, construído a partir do esquema sugerido
pelo professor, e não do modelo individual que as Aulas 08 a 15 desenvolvem.

A razão é estrutural, não de conveniência. O exercício inteiro gira em torno de bloquear
**a linha de um assento** e reler o seu status depois do bloqueio. No modelo individual o
assento não é uma entidade: é a coluna `assento VARCHAR(4)` dentro de `passagem`. Não
existe linha de assento para bloquear — existe a linha da passagem, que só passa a
existir depois de a reserva ter sido decidida. Fazer `FOR UPDATE` no modelo individual
bloquearia o registro da venda, não o recurso disputado, e o experimento perderia o
objeto de estudo.

O nome diferente também protege o trabalho anterior: o `aeroporto` é reconstruído do zero
pelo `sql_integridade.sql` e a Aula 15 depende dele. Um `DROP DATABASE` nesta aula
apagaria as duas.

O que as duas modelagens têm em comum está registrado: a `UNIQUE (voo_id, numero)` de
`assentos` é o equivalente exato da `UNIQUE (id_voo, assento)` que o modelo individual
carrega desde a Aula 08, e a coluna gerada da seção 2 usa o mesmo comportamento de `NULL`
sob `UNIQUE` que a Aula 10 usou para aceitar vários passageiros estrangeiros sem CPF.

## 2. Adaptações de PostgreSQL para MySQL

O enunciado é escrito em PostgreSQL e pede que as adaptações sejam feitas e justificadas.

| Enunciado (PostgreSQL) | Neste arquivo (MySQL 8) | Por que |
|---|---|---|
| `BIGSERIAL` | `BIGINT AUTO_INCREMENT` | No MySQL o contador é propriedade da coluna, não um objeto `SEQUENCE` separado |
| `TIMESTAMP` | `DATETIME` | O `TIMESTAMP` do MySQL tem faixa 1970–2038 e converte para UTC e de volta conforme o fuso da sessão. `DATETIME` guarda o valor literal |
| (sem cláusula) | `ENGINE = InnoDB` explícito | É o padrão no MySQL 8, mas nada nesta aula funciona sem ele: MyISAM não tem transação, nem bloqueio de linha, nem MVCC, e `FOR UPDATE` seria aceito e ignorado |
| `CREATE UNIQUE INDEX ... WHERE status = 'CONFIRMADA'` | coluna gerada `STORED` + `UNIQUE` | Índice parcial é específico do PostgreSQL; o MySQL não tem índice com predicado |
| `RETURNING` | `ROW_COUNT()` logo após o `UPDATE` | Não existe `RETURNING` no MySQL |

A substituição do índice parcial é a mais interessante. O enunciado quer "no máximo uma
reserva **confirmada** por assento", deixando as canceladas livres para acumular. Sem
índice parcial, a solução é uma coluna gerada:

```sql
assento_ativo BIGINT AS (IF(status = 'CONFIRMADA', assento_id, NULL)) STORED,
CONSTRAINT uq_reserva_assento_ativa UNIQUE (assento_ativo)
```

Funciona porque um índice `UNIQUE` aceita vários `NULL` — dois `NULL` não são iguais entre
si. As reservas canceladas viram `NULL` e saem da restrição; sobra exatamente uma
confirmada por assento. `STORED` e não `VIRTUAL` porque o valor precisa estar gravado para
o índice não depender de recálculo na leitura.

O efeito colateral é bom: cancelar uma reserva libera o assento automaticamente, sem
código de aplicação. O Experimento A2 mede isso.

**Uma diferença que não é de sintaxe.** O isolamento padrão do MySQL é `REPEATABLE READ`;
o do PostgreSQL é `READ COMMITTED`. Isso não se "adapta" — muda o resultado observável, e
o Experimento E depende disso. Está desenvolvido na seção 6.

## 3. A estratégia em camadas do `sp_reservar_assento`

O procedimento não confia em uma única defesa. São quatro, da mais cara à mais barata, e
cada uma cobre a falha da anterior:

| # | Camada | O que ela pega | Vale fora do procedimento? |
|---|---|---|---|
| 1 | `SELECT ... FOR UPDATE` | Serializa os concorrentes: o segundo espera o primeiro terminar | Não |
| 2 | Revalidação pós-lock | Quem esperou relê o status já atualizado e desiste | Não |
| 3 | `UPDATE` condicional + `ROW_COUNT()` | A janela entre ler e escrever, se a camada 1 for removida | Não |
| 4 | `UNIQUE (assento_ativo)` | Qualquer cliente que não use o procedimento | **Sim** |

Três decisões dentro do procedimento merecem registro, porque em todas elas o caminho
óbvio está errado.

**O `WHERE` do `FOR UPDATE` não filtra por status.** O exemplo do enunciado traz
`WHERE ... AND status = 'DISPONIVEL'`. Com esse filtro, um assento já reservado não
retorna linha, não é bloqueado, e o procedimento não consegue distinguir "o assento não
existe" de "o assento existe e está ocupado" — as duas situações viram zero linhas.
Bloqueia-se a linha primeiro e decide-se depois, que é o próprio ponto da revalidação.

**`SELECT ... INTO` sem linhas não é erro no MySQL.** Gera o aviso 1329 e deixa as
variáveis como estavam, e a execução segue. Em PL/pgSQL isso levantaria `NO_DATA_FOUND` e
o handler tomaria conta. Aqui não: sem o `IF v_assento_id IS NULL` explícito, o
procedimento seguiria com `NULL`, o `UPDATE` não acharia nada e o `INSERT` falharia por
chave estrangeira — um erro confuso, muito longe da causa. Por isso a variável nasce com
`DEFAULT NULL` e é testada.

**`ROW_COUNT()` é lido imediatamente após o `UPDATE`.** Qualquer outro comando no meio o
sobrescreve. É a primeira instrução depois do `UPDATE`, e não por estilo.

O `EXIT HANDLER FOR SQLEXCEPTION` faz `ROLLBACK` e `RESIGNAL`. O `RESIGNAL` é o que
importa: sem ele o procedimento engoliria a falha e o cliente acharia que a reserva deu
certo — o pior desfecho possível em um sistema de reservas. Com ele, o código original
(1644, 1062, 1205, 1213) chega intacto ao cliente, que foi o que permitiu montar a tabela
da seção 5.

## 4. O harness: duas conexões reais

O enunciado pede para abrir duas sessões e intercalar comandos à mão. O problema dessa
forma é que o resultado passa a depender da velocidade de quem digita: não dá para
afirmar que a sessão 2 esperou por causa do bloqueio, e não porque o comando foi colado
tarde. Também não dá para medir a espera com precisão melhor que o relógio de parede.

O `harness.py` abre **duas conexões TCP independentes** com o MySQL, cada uma na sua
thread. Cada conexão tem o seu próprio `CONNECTION_ID`, a sua própria transação e o seu
próprio read view — são duas sessões de verdade. No Experimento A1 a saída mostra
`CONNECTION_ID = 86` e `87`, conexões distintas.

A thread é o que torna o bloqueio observável: quando a sessão 2 trava num `FOR UPDATE`, é
a thread dela que fica parada, enquanto a sessão 1 continua andando até o `COMMIT`. Um
script de uma única conexão não consegue exibir isso — ele simplesmente travaria.

A ordem dos passos é garantida por `threading.Event` e `threading.Barrier`, não por
`sleep` esperando o outro lado chegar. A sessão 2 só tenta o seu bloqueio depois que a
sessão 1 sinaliza que já tem o dela. Os tempos são medidos com `time.monotonic()` em
volta exatamente da chamada que bloqueia.

Esta é a única aula do repositório que usa biblioteca externa
(`mysql-connector-python`). O cliente `mysql` de linha de comando não serve aqui: ele lê
o script inteiro e executa em sequência numa única sessão, que é justamente o que não
permite intercalar duas.

## 5. Resultados medidos

Os seis experimentos, com a saída real de `python harness.py`:

| # | Experimento | Cenário | Resultado medido | Erro |
|---|---|---|---|---|
| **A1** | Disputa pelo procedimento | S1 segura o bloqueio 2,0 s; S2 chama `sp_reservar_assento` no mesmo assento | S2 esperou **2,015 s**, acordou e foi **recusada**. Assento fica com S1, uma única reserva confirmada | **1644** `Assento 10A do voo 1 nao esta disponivel (status atual: RESERVADO)` |
| **A2** | Só a `UNIQUE` | Dois `INSERT` diretos na `reservas`, sem procedimento, sem transação, sem `FOR UPDATE` | O segundo foi **rejeitado**. Após cancelar a primeira reserva, o mesmo `INSERT` **passou** | **1062** `Duplicate entry '1' for key 'reservas.uq_reserva_assento_ativa'` |
| **B** | Duração da espera | S1 segura 1,0 s / 3,0 s | S2 esperou **1,000 s** e **3,000 s** (diferença **+0,000 s** nas duas) | — |
| **C** | Espera esgotada | `innodb_lock_wait_timeout = 2s` em S2; S1 segura 6,0 s | S2 abortou em **2,078 s**, sem esperar os 6 s. A transação de S2 **continuou viva** (um `SELECT` simples seguinte devolveu as 3 linhas) | **1205** `Lock wait timeout exceeded; try restarting transaction` |
| **D** | Deadlock | S1 bloqueia 10A→10B; S2 bloqueia 10B→10A | Ciclo detectado em **0,000 s**. **S2 foi a vítima** e teve a transação desfeita; **S1 sobreviveu** e confirmou | **1213** `Deadlock found when trying to get lock; try restarting transaction` |
| **E** | MVCC | S2 fixa o read view; S1 altera e confirma; S2 relê | Mesma transação, duas respostas: `SELECT` simples **DISPONIVEL**, `FOR UPDATE` **RESERVADO** | — |
| **F** | Alcance do bloqueio | S1 bloqueia o 10A com e sem índice utilizável; S2 pede o **10B** | Sem índice, S2 **não conseguiu** o 10B (`type=index`, `rows=3`). Com índice, S2 **conseguiu** (`type=const`, `rows=1`) | **1205** no primeiro caso |

### 5.1 A1 — quem ganha, e o que a perdedora recebe

```
[  0.250s]  S1 | SELECT ... FOR UPDATE -> id=1, status=DISPONIVEL (linha bloqueada)
[  0.250s]  S2 | chama sp_reservar_assento(2, 1, '10A') - vai travar no FOR UPDATE
[  0.250s]  S1 | segurando o bloqueio por 2.0s (sem COMMIT) de proposito
[  2.265s]  S1 | COMMIT - bloqueio liberado
[  2.265s]  S2 | destravou depois de 2.015s e foi RECUSADA
[  2.265s]  S2 | ERRO 1644: Assento 10A do voo 1 nao esta disponivel (status atual: RESERVADO)
```

O ponto não é que S2 falhou: é **onde** ela falhou. S2 não foi barrada pela `UNIQUE` nem
pelo `UPDATE` condicional — foi barrada pela revalidação pós-lock, a camada 2, que leu
`RESERVADO` num `SELECT` que, quando S2 começou a esperar, teria devolvido `DISPONIVEL`.
É esse valor relido que prova que a leitura bloqueante não usa o retrato da transação. O
Experimento E isola esse comportamento.

O estado final tem **uma** reserva confirmada e o assento `RESERVADO`. Nenhum assento
vendido duas vezes, e nenhuma reserva órfã: o assento não fica `RESERVADO` sem reserva
correspondente, porque o `COMMIT` do procedimento só acontece no fim.

### 5.2 A2 — a restrição sozinha, sem cliente colaborativo

As camadas 1 a 3 só existem para quem chama o procedimento. A camada 4 vale sempre, e A2
é o cenário do cliente que ignora a aplicação e escreve direto na tabela:

```
[  2.609s]  S1 | INSERT direto na reservas (assento 1), sem transacao explicita
[  2.609s]  S1 | aceito
[  2.609s]  S2 | INSERT direto na reservas para o MESMO assento 1
[  2.609s]  S2 | ERRO 1062: Duplicate entry '1' for key 'reservas.uq_reserva_assento_ativa'
[  2.609s]  S1 | UPDATE reservas SET status = 'CANCELADA' (libera o assento_ativo)
[  2.609s]  S2 | tenta de novo o mesmo INSERT depois do cancelamento
[  2.609s]  S2 | aceito - o cancelamento devolveu o assento
```

Duas coisas ficam demonstradas. A duplicidade é impedida mesmo sem transação e sem
bloqueio — é a restrição declarativa fazendo o trabalho. E o cancelamento devolve o
assento sem nenhuma linha de código: a coluna gerada virou `NULL`, saiu da `UNIQUE`, e a
vaga reabriu. A mesma reserva cancelada continua na tabela, preservando o histórico.

### 5.3 B — a espera é o `COMMIT` da outra, não o acaso

| S1 segurou | S2 esperou | Diferença |
|---|---|---|
| 1,0 s | 1,000 s | +0,000 s |
| 3,0 s | 3,000 s | +0,000 s |

A espera acompanha o tempo de retenção com diferença de 0,000 s nas duas medições. Quem
determina a duração do bloqueio é o `COMMIT` da concorrente: S2 não espera um intervalo
fixo nem faz nova tentativa em laço — ela fica parada no `FOR UPDATE` e é liberada no
instante em que a outra transação termina.

Isso responde a uma pergunta prática: o custo de uma transação longa não é pago por ela,
é pago por todas as que precisarem das mesmas linhas. Uma transação que segura o bloqueio
por 3 s e faz mais nove operações lentas antes do `COMMIT` transfere esses 3 s para cada
concorrente na fila.

### 5.4 C — a espera não é infinita (1205)

```
[  7.640s]  S2 | innodb_lock_wait_timeout da sessao = 2s
[  7.640s]  S1 | bloqueio tomado, vai segurar por 6.0s
[  9.718s]  S2 | ERRO 1205 depois de 2.078s: Lock wait timeout exceeded
[  9.718s]  S2 | a transacao continua viva apos o 1205 (SELECT simples: 3 assentos)
[ 13.640s]  S1 | COMMIT
```

S2 abortou em 2,078 s, com S1 ainda segurando o bloqueio por mais quatro segundos. O
limite é **por sessão** (`SET SESSION`), o que permitiu reduzi-lo só em S2 sem tocar no
servidor.

O detalhe que importa é a última linha antes do `COMMIT` de S1: **a transação de S2
sobreviveu ao erro**. Só o comando foi desfeito. Um `SELECT` seguinte na mesma transação
funcionou normalmente e devolveu as três linhas. O cliente decide: repetir o comando,
seguir por outro caminho ou desistir com `ROLLBACK`. Essa é a diferença de fundo em
relação ao deadlock da seção 5.5, e é o motivo de os dois erros não poderem ser tratados
pelo mesmo `catch`.

### 5.5 D — deadlock detectado, não esperado (1213)

```
[ 14.093s]  S2 | bloqueou 10B (uma linha)
[ 14.093s]  S1 | bloqueou 10A (uma linha)
[ 14.093s]  S1 | agora pede 10B - que a outra sessao detem
[ 14.093s]  S2 | agora pede 10A - que a outra sessao detem
[ 14.093s]  S2 | ERRO 1213 depois de 0.000s: Deadlock found when trying to get lock
[ 14.093s]  S1 | conseguiu 10B depois de 0.000s - sobreviveu
[ 14.109s]  S1 | COMMIT
```

Duas diferenças em relação ao 1205, e as duas aparecem na saída:

**O tempo foi 0,000 s.** Nenhuma das sessões esperou. O `innodb_lock_wait_timeout` das
duas estava em 5 s e não chegou a ser consultado — o InnoDB não espera para descobrir que
há um ciclo, ele mantém um grafo de espera e detecta o fechamento no instante em que a
segunda requisição entra. Espera esgotada é um palpite sobre o futuro; deadlock é um fato
presente no grafo.

**A transação da vítima foi desfeita inteira**, não apenas o comando. Depois do 1213 não
há o que continuar: S2 só pode recomeçar do zero.

O servidor confirma que foi ciclo e não espera, em `SHOW ENGINE INNODB STATUS`:

```
LATEST DETECTED DEADLOCK
------------------------
2026-09-21 15:55:38 129504761689664
*** (1) TRANSACTION:
TRANSACTION 5443, ACTIVE 0 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 4 lock struct(s), heap size 1128, 3 row lock(s)
```

**Quem morre não é escolhido pelo programador, e isso foi observado.** Na execução
transcrita acima a vítima foi S2; em outra execução do mesmo experimento, sem nenhuma
alteração no código, a vítima foi **S1** e S2 sobreviveu. O InnoDB escolhe a transação com
menos trabalho a desfazer, e com as duas sessões fazendo trabalho equivalente o resultado
varia entre execuções. Nenhuma das duas pode assumir que vai ser a sobrevivente: as duas
precisam do mesmo tratamento de erro. Não foi medida a frequência de cada desfecho — a
afirmação é só a de que a escolha é do servidor e que ela de fato mudou.

A prevenção não está no tratamento do erro, e sim na **ordem de aquisição**. O ciclo só
existiu porque S1 pediu 10A→10B e S2 pediu 10B→10A. Se as duas pedirem sempre na mesma
ordem — por `id` crescente, por exemplo — o ciclo é impossível por construção, e o custo
é ordenar uma lista antes de bloquear. É a recomendação que vale para a reserva de
múltiplos assentos numa compra só.

### 5.6 E — MVCC: a mesma transação vendo dois valores

```
[ 14.687s]  S2 | START TRANSACTION + SELECT simples -> DISPONIVEL (read view fixado)
[ 14.703s]  S1 | UPDATE assentos SET status = 'RESERVADO' WHERE id = 1
[ 14.703s]  S1 | COMMIT
[ 14.703s]  S2 | SELECT simples DEPOIS do COMMIT de S1 -> DISPONIVEL (retrato do MVCC)
[ 14.718s]  S2 | SELECT ... FOR UPDATE na MESMA transacao -> RESERVADO (versao confirmada)
[ 14.718s]  S2 | depois do COMMIT, transacao nova -> RESERVADO
```

| Leitura | Comando | Resultado |
|---|---|---|
| 1 | `SELECT` simples, antes do `UPDATE` de S1 | `DISPONIVEL` |
| 2 | `SELECT` simples, **depois** do `COMMIT` de S1 | `DISPONIVEL` |
| 3 | `SELECT ... FOR UPDATE`, **mesma transação** | `RESERVADO` |
| 4 | `SELECT` simples, transação nova | `RESERVADO` |

As leituras 2 e 3 são da mesma transação, com milissegundos de distância, e discordam.
Não é cache do cliente nem erro: é versionamento.

A leitura 2 é servida pelo MVCC a partir da versão antiga guardada no undo log, porque em
`REPEATABLE READ` o read view foi fixado na primeira leitura e não se move. A leitura 3
ignora o retrato: uma leitura bloqueante precisa operar sobre o que realmente está lá,
senão bloquearia uma versão que já não existe.

**É por isso que a revalidação do procedimento usa `FOR UPDATE`, e não um `SELECT`
comum.** Com `SELECT` comum, uma sessão que esperou o bloqueio releria `DISPONIVEL` — o
valor do seu retrato —, concluiria que o assento está livre e autorizaria a reserva
dobrada. A camada 2 inteira depende dessa distinção, e o A1 mostra ela funcionando: lá o
valor relido foi `RESERVADO`.

### 5.7 F — o `WHERE` decide quantas linhas ficam bloqueadas

Este experimento não estava previsto. Ele nasceu de um defeito real: a primeira versão do
Experimento D filtrava por `numero = '10A'` e **nunca produzia deadlock**. As duas sessões
ficavam cerca de 50 s paradas e saíam por 1205. O diagnóstico está na seção 7.

| `WHERE` de S1 | `EXPLAIN` | S2 conseguiu o **10B**? |
|---|---|---|
| `numero = '10A'` | `type=index`, `key=uq_assento_voo`, `rows=3` | **Não** — erro 1205 |
| `voo_id = 1 AND numero = '10A'` | `type=const`, `key=uq_assento_voo`, `rows=1` | **Sim** |

S1 pediu um assento e bloqueou três. O InnoDB não bloqueia "a linha que o `WHERE`
descreve": bloqueia toda linha que precisou **examinar** para avaliar o `WHERE`. A tabela
tem `UNIQUE (voo_id, numero)`, e `numero` não é prefixo à esquerda desse índice, então
`WHERE numero = '10A'` não tem acesso direto e vira varredura — com bloqueio em tudo que
passou pelo caminho.

O efeito prático é a perda da concorrência inteira sem que nenhuma regra de negócio peça
isso: uma reserva do 10A impede a reserva **simultânea** do 10B e do 10C, que nada têm a
ver com ela. E o sintoma no cliente é um 1205 depois de 50 s, não um erro de lógica — o
tipo de problema que aparece em produção sob carga e não aparece em teste com uma sessão.

O índice, aqui, não é otimização de leitura. É requisito de correção da concorrência.

## 6. MVCC e isolamento: MySQL e PostgreSQL divergem

O isolamento padrão do MySQL é `REPEATABLE READ`; o do PostgreSQL é `READ COMMITTED`. O
Experimento E foi medido no MySQL, e a leitura 2 devolveu `DISPONIVEL`.

**No PostgreSQL, com o padrão dele, a leitura 2 devolveria `RESERVADO`**, porque em
`READ COMMITTED` cada comando pega um retrato novo, e o `UPDATE` de S1 já estava
confirmado. Isso **não foi medido** — não há PostgreSQL neste ambiente, e a afirmação vem
da definição dos dois níveis, não de execução.

A consequência de projeto é que a correção do procedimento não pode depender do nível de
isolamento configurado. As quatro camadas da seção 3 funcionam nos dois bancos e nos dois
níveis, porque nenhuma delas pressupõe o comportamento do retrato: a camada 1 serializa,
a 2 relê **com bloqueio** (que ignora o retrato em ambos), a 3 revalida no próprio
`UPDATE` e a 4 é declarativa. Um procedimento que revalidasse com `SELECT` simples estaria
correto no PostgreSQL por acidente do padrão e **errado no MySQL** — e voltaria a estar
errado no PostgreSQL no dia em que alguém subisse o isolamento para `REPEATABLE READ`.

## 7. O defeito que o Experimento F revelou

Vale registrar o erro, porque o sintoma não apontava para a causa.

**Sintoma.** O Experimento D não produzia deadlock nenhum. A saída trazia as duas sessões
"bloqueando" o seu primeiro assento e depois seguindo em frente sem erro, com um vão de
52 s na timeline entre um evento e o seguinte.

**Dois defeitos, não um.**

O primeiro estava no `WHERE numero = '10A'`, sem `voo_id`: S1 bloqueava as três linhas em
vez de uma, S2 travava no seu **primeiro** bloqueio e o ciclo nunca se formava. Não havia
deadlock para detectar — havia uma fila comum, resolvida por 1205 depois dos 50 s do
padrão.

O segundo estava no harness, e foi o que escondeu o primeiro: o código não conferia o erro
do primeiro `FOR UPDATE`. A chamada devolvia o 1205, o valor de retorno era descartado, e
a linha `bloqueou 10B` era impressa de qualquer forma. **O harness relatava como sucesso
um comando que havia falhado** — o vão de 52 s na timeline era a única pista.

**Correções.** O `WHERE` passou a usar o par completo `(voo_id, numero)`, que é acesso
`type=const` a uma linha. O erro do primeiro bloqueio passou a ser conferido e registrado
como inesperado. E o `innodb_lock_wait_timeout` do Experimento D foi reduzido para 5 s,
para que uma falha futura apareça em segundos em vez de ficar 50 s parada parecendo
lentidão. Com isso o deadlock passou a ocorrer em 0,000 s, como a seção 5.5 mostra.

A lição de método é a que ficou no arquivo: em teste de concorrência, **não conferir o
retorno de um comando que pode bloquear transforma uma falha em um falso positivo
silencioso**. O relógio foi o que denunciou.

## 8. Respostas às perguntas do enunciado

**O que acontece quando duas transações tentam reservar o mesmo assento?** A segunda para
no `SELECT ... FOR UPDATE` e fica parada até a primeira confirmar ou desfazer — 2,015 s
quando a primeira segurou 2,0 s (A1). Ao acordar, ela relê o status já como `RESERVADO` e
é recusada com 1644. Uma reserva confirmada, nenhum assento vendido duas vezes.

**Por que `FOR UPDATE` e não só o `UPDATE` condicional?** O `UPDATE` condicional sozinho
também impediria a duplicidade, mas à custa de trabalho perdido: as duas transações
avançariam até a escrita e uma seria desfeita no fim. O `FOR UPDATE` serializa antes, e a
perdedora descobre o problema na revalidação, antes de escrever. Além disso, sem ele não
existe ponto seguro para reler o status: o A1 depende da leitura bloqueante (E).

**A espera é indefinida?** Não. Ela termina no `COMMIT` da outra sessão (B, com diferença
de 0,000 s nas duas medições) ou no `innodb_lock_wait_timeout`, que abortou o comando em
2,078 s com o limite em 2 s (C).

**Qual a diferença entre 1205 e 1213?** O 1205 é espera esgotada: só o comando é desfeito,
**a transação continua viva** e o cliente pode tentar de novo (C). O 1213 é ciclo
detectado: a transação **inteira** da vítima é desfeita, em 0,000 s, e só resta
recomeçar (D). Tratar os dois igual é errado nas duas direções — repetir só o comando após
um 1213 opera numa transação que não existe mais, e refazer tudo após um 1205 joga fora
trabalho válido.

**Como evitar deadlock?** Ordem única de aquisição de bloqueios. O ciclo de D só existiu
porque as sessões pediram 10A→10B e 10B→10A; pedindo sempre em ordem crescente de `id`, o
ciclo é impossível por construção. Secundariamente: transações curtas, porque o tempo
segurando bloqueio é o tempo de exposição, e o custo dele é pago pelos concorrentes (B).

**Uma transação sempre vê o dado mais recente?** Não. Em `REPEATABLE READ`, um `SELECT`
simples vê o retrato do início da transação — a leitura 2 de E devolveu `DISPONIVEL` depois
de o `UPDATE` já estar confirmado. Só a leitura bloqueante vê a versão confirmada mais
recente, e a mesma transação devolveu `RESERVADO` no comando seguinte. Quem valida
concorrência com `SELECT` simples valida contra um retrato antigo.

## 9. Conclusões

1. **A restrição declarativa é a única camada que vale sempre.** As três camadas de
   aplicação protegem quem usa o procedimento; a `UNIQUE (assento_ativo)` protege contra
   quem não usa (A2). Se apenas uma pudesse ser mantida, seria ela.
2. **Leitura bloqueante e leitura simples respondem coisas diferentes, e a diferença é
   silenciosa.** A mesma transação devolveu `DISPONIVEL` e `RESERVADO` com milissegundos
   de distância (E). O código que revalida precisa usar `FOR UPDATE`; nada no resultado de
   um `SELECT` simples indica que ele está desatualizado.
3. **1205 e 1213 exigem tratamentos diferentes** porque deixam a transação em estados
   diferentes: viva em um caso, desfeita no outro (C, D).
4. **Deadlock se previne no projeto, não no `catch`.** Ordem única de aquisição elimina o
   ciclo por construção; tratar o 1213 é o plano B.
5. **Índice é requisito de correção da concorrência, não só de desempenho.** Um `WHERE`
   sem índice utilizável fez uma sessão bloquear três linhas em vez de uma e serializou
   reservas de assentos independentes (F) — a conclusão que a Aula 14 não alcançaria,
   porque lá o índice foi avaliado com uma sessão só e o veredito foi não mantê-lo.
6. **Teste de concorrência que não confere o retorno de comando bloqueante mente.** O
   defeito da seção 7 imprimiu sucesso sobre um 1205 e só foi pego pelo relógio.
