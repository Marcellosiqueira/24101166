# Aula 16 — Locking, deadlocks e MVCC

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Controle de concorrência em um cenário de reserva de assentos: a condição de corrida
acontecendo, bloqueio pessimista com `SELECT ... FOR UPDATE`, espera por bloqueio, estouro
de tempo de espera, deadlock, prevenção de deadlock e MVCC — cada um com duas sessões
simultâneas, passo a passo reproduzível à mão.

| Arquivo | Conteúdo |
|---|---|
| `concorrencia.sql` | Esquema, dados de teste, `sp_reservar_assento` e `sp_resetar_cenario` |
| `concorrencia.md` | Estratégia, os experimentos passo a passo, resultados medidos e respostas |

```bash
mysql -u root -p < concorrencia.sql
```

**Ambiente de medição.** MySQL 8.0.46 em contêiner Docker (`mysql:8.0`) no Windows 11,
porta 3308. Nível de isolamento padrão `REPEATABLE-READ`,
`innodb_lock_wait_timeout = 50s`, `innodb_deadlock_detect = 1`. **Todo número deste
documento veio de execução nesse ambiente**, com os comandos exatamente na ordem em que a
seção 6 os publica. Onde um valor não foi medido, está escrito que não foi.

Sem dependências externas: a entrega é o SQL e este documento. Os experimentos são feitos
à mão, em duas sessões, como a seção 4 descreve.

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
o do PostgreSQL é `READ COMMITTED`. Isso não se "adapta" — muda o resultado observável.
Os Experimentos E e F foram rodados nos dois níveis por causa disso, e a seção 7 compara.

## 3. A estratégia em camadas do `sp_reservar_assento`

O procedimento não confia em uma única defesa. São quatro, da mais cara à mais barata, e
cada uma cobre a falha da anterior:

| # | Camada | O que ela pega | Vale fora do procedimento? |
|---|---|---|---|
| 1 | `SELECT ... FOR UPDATE` | Serializa os concorrentes: o segundo espera o primeiro terminar | Não |
| 2 | Revalidação pós-lock | Quem esperou relê o status já atualizado e desiste | Não |
| 3 | `UPDATE` condicional + `ROW_COUNT()` | A janela entre ler e escrever, se a camada 1 for removida | Não |
| 4 | `UNIQUE (assento_ativo)` | Qualquer cliente que não use o procedimento | **Sim** |

O Experimento A0 mostra o que acontece quando **nenhuma** delas está presente, e é o
experimento que justifica a existência das outras quatro.

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

## 4. Como reproduzir os experimentos

Os experimentos precisam de **duas sessões simultâneas**. No MySQL Workbench, cada aba de
query é uma sessão independente, com o seu próprio `CONNECTION_ID`, a sua própria
transação e o seu próprio read view. Duas abas bastam.

1. Abra **duas abas** de query no mesmo servidor. Chame uma de **S1** e a outra de **S2**.
2. Em cada aba, rode `USE aeroporto_concorrencia;` uma vez.
3. Confirme em cada aba que são sessões diferentes:
   ```sql
   SELECT CONNECTION_ID();
   ```
4. Execute **um comando por vez**, na ordem da coluna "Passo" de cada experimento,
   alternando de aba conforme a coluna "Sessão". No Workbench, use *Execute Current
   Statement* (`Ctrl+Enter`) — o botão de raio executa o script inteiro e não serve aqui,
   porque o ponto é justamente intercalar.
5. Entre um experimento e o próximo, rode em qualquer aba:
   ```sql
   CALL sp_resetar_cenario();
   ```
   Ele devolve os três assentos para `DISPONIVEL` e apaga as reservas, o que torna o
   roteiro reproduzível na ordem em que está escrito.

Alguns passos estão marcados com **(bloqueia)**. Neles a aba trava e o Workbench fica com
o indicador de execução girando: é o comportamento esperado, e é o objeto de estudo. A aba
destrava sozinha quando a outra sessão fizer `COMMIT` ou `ROLLBACK`, ou quando o
`innodb_lock_wait_timeout` estourar. Não cancele a execução — é isso que se quer observar.

**Sobre os tempos deste documento.** Os passos abaixo foram executados na ordem publicada,
com os tempos medidos por instrumentação em volta exatamente do comando que bloqueia, para
não depender da velocidade de digitação. Reproduzindo à mão, os desfechos, os códigos de
erro e os valores lidos são os mesmos; os tempos em segundos variam conforme o intervalo
real entre um passo e o seguinte, porque é o `COMMIT` da outra sessão que os determina
(Experimento B).

Referências fixas do banco de teste, usadas nos passos:

| Assento | `id` | `voo_id` | `numero` |
|---|---|---|---|
| 10A | 1 | 1 | `'10A'` |
| 10B | 2 | 1 | `'10B'` |
| 10C | 3 | 1 | `'10C'` |

Passageiros: `id` 1 a 4 (`Passageiro A` a `Passageiro D`).

## 5. Resultados medidos

| # | Experimento | Cenário | Resultado medido | Erro |
|---|---|---|---|---|
| **A0** | Corrida sem restrição | `UNIQUE` removida; as duas sessões leem com `SELECT` comum e escrevem | **Duas reservas CONFIRMADA para o mesmo assento**, sem erro nenhum | — |
| **A1** | Disputa pelo procedimento | S1 segura o bloqueio 2,0 s; S2 chama `sp_reservar_assento` no mesmo assento | S2 esperou **2,015 s**, acordou e foi **recusada**. Um assento, uma reserva | **1644** `Assento 10A do voo 1 nao esta disponivel (status atual: RESERVADO)` |
| **A2** | Só a `UNIQUE` | Dois `INSERT` diretos, sem procedimento, sem transação, sem `FOR UPDATE` | O segundo **rejeitado**. Após cancelar a primeira, o mesmo `INSERT` **passou** | **1062** `Duplicate entry '1' for key 'reservas.uq_reserva_assento_ativa'` |
| **A3** | Assentos diferentes | Dois passageiros chamam o procedimento ao mesmo tempo, 10A e 10B | **As duas com sucesso e sem espera**: 0,016 s cada. Duas reservas confirmadas | — |
| **B** | Duração da espera | S1 segura 1,0 s / 3,0 s | S2 esperou **1,000 s** e **3,000 s** (diferença **+0,000 s** nas duas) | — |
| **C** | Espera esgotada | `innodb_lock_wait_timeout = 2s` em S2; S1 segura 6,0 s | S2 abortou em **2,109 s**, sem esperar os 6 s. A transação de S2 **continuou viva** | **1205** `Lock wait timeout exceeded` |
| **D1** | Deadlock | S1 bloqueia `id` 1→2; S2 bloqueia `id` 2→1 | Ciclo detectado em **0,015 s**. **S1 foi a vítima**, transação desfeita inteira; **S2 sobreviveu** e confirmou | **1213** `Deadlock found when trying to get lock` |
| **D2** | Ordem crescente | As duas sessões bloqueiam `id` 1→2, na mesma ordem | **Nenhum deadlock.** S2 esperou **0,500 s** pelo `id` 1 e as duas confirmaram | — |
| **E** | MVCC em `REPEATABLE READ` | S2 fixa o read view; S1 altera e confirma; S2 relê | Mesma transação: `SELECT` simples **DISPONIVEL**, `FOR UPDATE` **RESERVADO** | — |
| **E′** | MVCC em `READ COMMITTED` | Os mesmos passos, com S2 em `READ COMMITTED` | `SELECT` simples já devolveu **RESERVADO** | — |
| **F** | Escopo do bloqueio | S1 bloqueia o 10A com e sem índice utilizável; S2 pede o **10B** | `REPEATABLE READ`: sem índice S2 **não conseguiu** o 10B; com índice **conseguiu**. `READ COMMITTED`: **conseguiu nos dois**. Reserva correta em todos os casos | **1205** só no primeiro caso |

## 6. Os experimentos, passo a passo

### 6.1 A0 — a condição de corrida acontecendo

**Pergunta.** Sem restrição nenhuma, duas sessões conseguem confirmar o mesmo assento?

Este é o experimento que justifica todos os outros. A `UNIQUE` da coluna gerada é removida
e as duas sessões fazem o que um cliente ingênuo faria: `SELECT` comum para conferir se o
assento está livre, `UPDATE` sem condição de status e `INSERT` da reserva.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `ALTER TABLE reservas DROP INDEX uq_reserva_assento_ativa;` |
| 2 | S1 | `START TRANSACTION;` |
| 3 | S1 | `SELECT status FROM assentos WHERE id = 1;` |
| 4 | S2 | `START TRANSACTION;` |
| 5 | S2 | `SELECT status FROM assentos WHERE id = 1;` |
| 6 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` |
| 7 | S1 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA');` |
| 8 | S1 | `COMMIT;` |
| 9 | S2 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` |
| 10 | S2 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (2, 1, 'CONFIRMADA');` |
| 11 | S2 | `COMMIT;` |
| 12 | S1 | `SELECT assento_id, COUNT(*) AS confirmadas FROM reservas WHERE status = 'CONFIRMADA' GROUP BY assento_id;` |

**Resultado medido.**

```
 S1 | ALTER TABLE reservas DROP INDEX uq_reserva_assento_ativa
 S1 | SELECT status FROM assentos WHERE id = 1   -> DISPONIVEL
 S2 | SELECT status FROM assentos WHERE id = 1   -> DISPONIVEL
 S1 | UPDATE ... ; INSERT ... ; COMMIT
 S2 | UPDATE ... ; INSERT ... ; COMMIT
 S1 | SELECT assento_id, COUNT(*) ... GROUP BY assento_id   -> assento 1, confirmadas 2

estado: assentos 10A=RESERVADO, 10B=DISPONIVEL, 10C=DISPONIVEL
        reserva 1: passageiro 1 -> 10A (CONFIRMADA)
        reserva 2: passageiro 2 -> 10A (CONFIRMADA)
```

**Leitura.** Duas reservas confirmadas para o assento 10A, e **nenhum erro em nenhum dos
doze passos**. Os dois passageiros saíram com o mesmo assento e os dois receberam
confirmação. É o desfecho que o sistema não pode ter, e ele acontece sem nada dar errado
do ponto de vista de cada sessão isolada.

O defeito está nos passos 3 e 5. As duas sessões leram `DISPONIVEL` e as duas decidiram
que o assento estava livre — e a segunda leitura já estava errada no instante em que foi
feita, porque S1 estava a caminho de ocupar o assento. Ler, decidir e escrever em passos
separados, sem bloqueio nem revalidação, é a condição de corrida.

Repare que o passo 9 nem chegou a esperar: o `UPDATE` de S1 já tinha sido confirmado no
passo 8. Se o passo 9 fosse executado antes do `COMMIT` de S1, ele ficaria bloqueado pela
trava de linha — mas o desfecho seria o mesmo, porque depois de destravar ele aplicaria o
`SET status = 'RESERVADO'` de novo, sem condição de status que o impedisse, e o `INSERT`
seguiria. Bloqueio de linha sozinho, sem `UPDATE` condicional nem revalidação, não
resolve.

**Restaurar a restrição** antes de seguir para o A1:

| Passo | Sessão | Comando |
|---|---|---|
| 13 | S1 | `CALL sp_resetar_cenario();` |
| 14 | S1 | `ALTER TABLE reservas ADD CONSTRAINT uq_reserva_assento_ativa UNIQUE (assento_ativo);` |
| 15 | S1 | `SHOW INDEX FROM reservas WHERE Key_name = 'uq_reserva_assento_ativa';` |

O passo 13 vem antes do 14 por necessidade: com as duas reservas duplicadas ainda na
tabela, a criação da `UNIQUE` falharia. O passo 15 confirma que o índice voltou.

### 6.2 A1 — disputa pelo mesmo assento, com o procedimento

**Pergunta.** Quem ganha o 10A, e o que a perdedora recebe?

S1 executa os passos do procedimento à mão, para que haja uma janela em que o bloqueio está
tomado e a transação ainda não confirmou. S2 chama o procedimento de verdade — é o lado de
S2 que está sob teste.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `START TRANSACTION;` |
| 2 | S1 | `SELECT id, status FROM assentos WHERE voo_id = 1 AND numero = '10A' FOR UPDATE;` |
| 3 | S2 | `CALL sp_reservar_assento(2, 1, '10A');` **(bloqueia)** |
| 4 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1 AND status = 'DISPONIVEL';` |
| 5 | S1 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA');` |
| 6 | S1 | `COMMIT;` |
| 7 | S2 | — a aba destrava sozinha e mostra o erro |
| 8 | S1 | `SELECT numero, status FROM assentos ORDER BY numero;` |

**Resultado medido.** S1 segurou o bloqueio por 2,0 s entre os passos 5 e 6.

```
(S1 CONNECTION_ID = 241, S2 CONNECTION_ID = 242)
 S1 | SELECT id, status ... FOR UPDATE   -> 1 DISPONIVEL
 S1 | UPDATE ... ; INSERT ...
 S1 | -- segura o bloqueio por 2.0s, sem COMMIT
 S1 | COMMIT
 S2 | CALL sp_reservar_assento(2, 1, '10A')
      -> ERRO 1644: Assento 10A do voo 1 nao esta disponivel (status atual: RESERVADO)
         (2.015s)

estado final: assentos 10A=RESERVADO, 10B=DISPONIVEL, 10C=DISPONIVEL
              reserva 1: passageiro 1 -> 10A (CONFIRMADA)
```

**Leitura.** O ponto não é que S2 falhou: é **onde** ela falhou. S2 não foi barrada pela
`UNIQUE` nem pelo `UPDATE` condicional — foi barrada pela revalidação pós-lock, a camada 2,
que leu `RESERVADO` num `SELECT` que, quando S2 começou a esperar, teria devolvido
`DISPONIVEL`. É esse valor relido que prova que a leitura bloqueante não usa o retrato da
transação; o Experimento E isola o comportamento.

Comparado ao A0, a diferença é inteira: mesmo cenário, mesma disputa, e aqui uma reserva
confirmada em vez de duas.

### 6.3 A2 — a `UNIQUE` sozinha, sem cliente colaborativo

**Pergunta.** A restrição segura a duplicidade quando o cliente não colabora?

As camadas 1 a 3 só existem para quem chama o procedimento. A camada 4 vale sempre.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA');` |
| 2 | S2 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (2, 1, 'CONFIRMADA');` |
| 3 | S1 | `UPDATE reservas SET status = 'CANCELADA' WHERE assento_id = 1;` |
| 4 | S2 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (2, 1, 'CONFIRMADA');` |
| 5 | S1 | `SELECT id, passageiro_id, assento_id, status FROM reservas ORDER BY id;` |

**Resultado medido.**

```
 S1 | INSERT ... VALUES (1, 1, 'CONFIRMADA')   -> aceito
 S2 | INSERT ... VALUES (2, 1, 'CONFIRMADA')
      -> ERRO 1062: Duplicate entry '1' for key 'reservas.uq_reserva_assento_ativa'
 S1 | UPDATE reservas SET status = 'CANCELADA' WHERE assento_id = 1
 S2 | INSERT ... VALUES (2, 1, 'CONFIRMADA')   -> aceito

estado final: reserva 1: passageiro 1 -> 10A (CANCELADA)
              reserva 3: passageiro 2 -> 10A (CONFIRMADA)
```

**Leitura.** Duas coisas ficam demonstradas. A duplicidade é impedida mesmo sem transação e
sem bloqueio — é a restrição declarativa fazendo o trabalho, e é exatamente o que faltava
no A0. E o cancelamento devolve o assento sem nenhuma linha de código: a coluna gerada
virou `NULL`, saiu da `UNIQUE`, e a vaga reabriu. A reserva cancelada continua na tabela,
preservando o histórico.

### 6.4 A3 — assentos diferentes do mesmo voo, ao mesmo tempo

**Pergunta.** Duas reservas de assentos distintos se atrapalham?

Requisito explícito da seção 21 do enunciado: a serialização precisa valer para o assento
disputado, e **não** para o voo inteiro. Se duas reservas de assentos diferentes se
bloqueassem, o sistema estaria correto e inútil.

Os dois comandos partem no mesmo instante, cada um na sua aba.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `CALL sp_reservar_assento(1, 1, '10A');` |
| 2 | S2 | `CALL sp_reservar_assento(2, 1, '10B');` |
| 3 | S1 | `SELECT numero, status FROM assentos ORDER BY numero;` |
| 4 | S1 | `SELECT id, passageiro_id, assento_id, status FROM reservas ORDER BY id;` |

**Resultado medido.**

```
 S1 | CALL sp_reservar_assento(1, 1, '10A')   -> sem erro, 0.016s
 S2 | CALL sp_reservar_assento(2, 1, '10B')   -> sem erro, 0.016s

estado final: assentos 10A=RESERVADO, 10B=RESERVADO, 10C=DISPONIVEL
              reserva 1: passageiro 1 -> 10A (CONFIRMADA)
              reserva 2: passageiro 2 -> 10B (CONFIRMADA)
```

**Leitura.** As duas com sucesso, nenhuma espera (0,016 s cada, contra os 2,015 s que S2
esperou no A1 pelo mesmo assento). O `FOR UPDATE` do procedimento bloqueia **a linha do
assento pedido**, não a tabela nem o voo, então reservas de assentos diferentes correm em
paralelo. É a granularidade correta: o custo do bloqueio é pago só por quem disputa o mesmo
recurso.

O Experimento F mostra que essa granularidade depende de o `WHERE` poder usar o índice — e
o `WHERE` do procedimento usa o par `(voo_id, numero)` justamente por isso.

### 6.5 B — a duração da espera é o `COMMIT` da outra sessão

**Pergunta.** A espera de S2 acompanha o tempo que S1 segura o bloqueio?

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `START TRANSACTION;` |
| 2 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 3 | S2 | `START TRANSACTION;` |
| 4 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia)** |
| 5 | S1 | `COMMIT;` — espere um tempo conhecido antes deste passo |
| 6 | S2 | — destrava no instante do `COMMIT` de S1 |
| 7 | S2 | `COMMIT;` |

Repetido com dois tempos de retenção entre os passos 4 e 5.

**Resultado medido.**

| S1 segurou | S2 esperou | Diferença |
|---|---|---|
| 1,0 s | 1,000 s | +0,000 s |
| 3,0 s | 3,000 s | +0,000 s |

**Leitura.** A espera acompanha o tempo de retenção com diferença de 0,000 s nas duas
medições. Quem determina a duração do bloqueio é o `COMMIT` da concorrente: S2 não espera
um intervalo fixo nem faz nova tentativa em laço — fica parada no `FOR UPDATE` e é
liberada no instante em que a outra transação termina.

Isso responde a uma pergunta prática: o custo de uma transação longa não é pago por ela, é
pago por todas as que precisarem das mesmas linhas. Uma transação que segura o bloqueio por
3 s e faz mais nove operações lentas antes do `COMMIT` transfere esses 3 s para cada
concorrente na fila.

### 6.6 C — a espera não é infinita (1205)

**Pergunta.** O que acontece quando a espera passa do limite da sessão?

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S2 | `SET SESSION innodb_lock_wait_timeout = 2;` |
| 2 | S2 | `SELECT @@innodb_lock_wait_timeout;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia, e falha em 2 s)** |
| 7 | S2 | `SELECT COUNT(*) FROM assentos;` — a transação de S2 ainda está viva |
| 8 | S2 | `ROLLBACK;` |
| 9 | S1 | `COMMIT;` |

O passo 9 vem depois de propósito: S1 ainda segurava o bloqueio quando S2 já havia
desistido.

**Resultado medido.** S1 segurou o bloqueio por 6,0 s; o limite de S2 era 2 s.

```
 S1 | START TRANSACTION
 S2 | SET SESSION innodb_lock_wait_timeout = 2
 S1 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE   -> 1
 S2 | START TRANSACTION
 S2 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE
      -> ERRO 1205: Lock wait timeout exceeded; try restarting transaction   (2.109s)
 S2 | SELECT COUNT(*) FROM assentos   -> 3
 S2 | ROLLBACK
 S1 | COMMIT
```

**Leitura.** S2 abortou em 2,109 s, com S1 ainda segurando o bloqueio por mais quase quatro
segundos. O limite é **por sessão** (`SET SESSION`), o que permitiu reduzi-lo só em S2 sem
tocar no servidor.

O detalhe que importa é o passo 7: **a transação de S2 sobreviveu ao erro**. Só o comando
foi desfeito. Um `SELECT` seguinte na mesma transação funcionou e devolveu as três linhas. O
cliente decide: repetir o comando, seguir por outro caminho ou desistir com `ROLLBACK`. Essa
é a diferença de fundo em relação ao deadlock do 6.7, e é o motivo de os dois erros não
poderem ser tratados pelo mesmo `catch`.

### 6.7 D1 — deadlock detectado, não esperado (1213)

**Pergunta.** O servidor detecta o ciclo, e o que sobra da transação da vítima?

S1 pede os assentos na ordem 1→2 e S2 na ordem **invertida**, 2→1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` |
| 7 | S1 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` **(bloqueia)** |
| 8 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` — fecha o ciclo |
| 9 | — | uma das duas recebe 1213 **na hora**; a outra destrava e segue |
| 10 | — | a sobrevivente faz `COMMIT;` |
| 11 | — | a vítima faz `ROLLBACK;` |
| 12 | S1 | `SHOW ENGINE INNODB STATUS;` — seção `LATEST DETECTED DEADLOCK` |

O `innodb_lock_wait_timeout` reduzido nos passos 1 e 2 não é necessário para o deadlock:
serve para que, se o ciclo não se formar por erro de roteiro, a falha apareça em 5 s em vez
de 50 s.

**Resultado medido.**

```
 S2 | SELECT id FROM assentos WHERE id = 2 FOR UPDATE   -> 2
 S1 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE   -> 1
 S1 | SELECT id FROM assentos WHERE id = 2 FOR UPDATE
      -> ERRO 1213: Deadlock found when trying to get lock   (0.015s)
 S2 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE   -> 1
 S2 | COMMIT
 S1 | ROLLBACK

vitima: S1 | sobrevivente: S2

LATEST DETECTED DEADLOCK
------------------------
2026-09-21 17:21:48 129504761689664
*** (1) TRANSACTION:
TRANSACTION 6763, ACTIVE 0 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1128, 2 row lock(s)
```

**Leitura.** Duas diferenças em relação ao 1205, e as duas aparecem na saída.

**O tempo foi 0,015 s.** Nenhuma das sessões esperou de fato. O `innodb_lock_wait_timeout`
das duas estava em 5 s e não chegou a ser consultado — o InnoDB não espera para descobrir
que há um ciclo: ele mantém um grafo de espera e detecta o fechamento no instante em que a
segunda requisição entra. Espera esgotada é um palpite sobre o futuro; deadlock é um fato
presente no grafo.

**A transação da vítima foi desfeita inteira**, não apenas o comando. Depois do 1213 não há
o que continuar: a vítima só pode recomeçar do zero.

**Quem morre não é escolhido pelo programador, e isso foi observado.** Na execução
transcrita acima a vítima foi S1; em outra execução do mesmo roteiro, sem nenhuma
alteração, a vítima foi **S2** e S1 sobreviveu. Nem a ordem em que os passos 7 e 8 chegam
ao servidor é estável: as duas sessões disputam o mesmo instante. O InnoDB escolhe a
transação com menos trabalho a desfazer, e com as duas fazendo trabalho equivalente o
resultado varia entre execuções. Nenhuma das duas pode assumir que vai ser a
sobrevivente: as duas precisam do mesmo tratamento de erro. Não foi medida a frequência
de cada desfecho — a afirmação é só a de que a escolha é do servidor e que ela de fato
mudou.

### 6.8 D2 — a mesma disputa, em ordem crescente de `id`

**Pergunta.** A ordem única de aquisição elimina o deadlock?

Rigorosamente o mesmo cenário do D1 — as mesmas duas sessões, os mesmos dois assentos, o
mesmo entrelaçamento — com **uma única mudança**: S2 também pede na ordem 1→2, em vez de
2→1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia — S1 detém o `id` 1)** |
| 7 | S1 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` |
| 8 | S1 | `COMMIT;` |
| 9 | S2 | — destrava e obtém o `id` 1 |
| 10 | S2 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` |
| 11 | S2 | `COMMIT;` |

**Resultado medido.** Houve uma pausa de 0,5 s entre os passos 6 e 7, para garantir que S2
já estava na fila do `id` 1 antes de S1 pedir o `id` 2.

```
 S1 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE   -> 1
 S2 | -- vai pedir o id = 1, que S1 detem (bloqueia)
 S1 | SELECT id FROM assentos WHERE id = 2 FOR UPDATE   -> 2
 S1 | COMMIT
 S2 | SELECT id FROM assentos WHERE id = 1 FOR UPDATE   -> 1   (esperou 0.500s)
 S2 | SELECT id FROM assentos WHERE id = 2 FOR UPDATE   -> 2
 S2 | COMMIT

houve deadlock? False
```

**Leitura.** Nenhum 1213, e as duas transações confirmaram. S2 esperou 0,500 s — o tempo
exato em que S1 ainda estava trabalhando — e depois seguiu sem obstáculo, porque quando ela
finalmente obteve o `id` 1, S1 já havia liberado o `id` 2 também.

O ciclo do D1 não se formou porque **ele não podia se formar**. Com as duas sessões pedindo
em ordem crescente de `id`, quem tem o `id` 1 nunca está esperando por quem tem o `id` 2: a
espera aponta sempre na mesma direção, e um grafo de espera que aponta sempre para o mesmo
lado não fecha ciclo. A espera continua existindo — ordem única não elimina contenção, e
nem deveria —, mas ela passa a terminar sempre.

Comparando D1 e D2: mesma carga, mesmos recursos, mesma contenção, e a única variável é a
ordem de aquisição. É a prova da resposta da **pergunta 9** da seção 8.

### 6.9 E — MVCC: a mesma transação vendo dois valores

**Pergunta.** A mesma transação pode ver dois valores diferentes da mesma linha?

Rodado **duas vezes**, mudando apenas o nível de isolamento de S2 no passo 1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S2 | `SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;` (2ª rodada: `READ COMMITTED`) |
| 2 | S2 | `START TRANSACTION;` |
| 3 | S2 | `SELECT status FROM assentos WHERE id = 1;` — **leitura 1**, fixa o read view |
| 4 | S1 | `START TRANSACTION;` |
| 5 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` |
| 6 | S1 | `COMMIT;` |
| 7 | S2 | `SELECT status FROM assentos WHERE id = 1;` — **leitura 2** |
| 8 | S2 | `SELECT status FROM assentos WHERE id = 1 FOR UPDATE;` — **leitura 3** |
| 9 | S2 | `COMMIT;` |
| 10 | S2 | `SELECT status FROM assentos WHERE id = 1;` — **leitura 4**, transação nova |

**Resultado medido.**

| Leitura | Comando | `REPEATABLE READ` | `READ COMMITTED` |
|---|---|---|---|
| 1 | `SELECT` simples, antes do `UPDATE` | `DISPONIVEL` | `DISPONIVEL` |
| 2 | `SELECT` simples, **depois** do `COMMIT` de S1 | **`DISPONIVEL`** | **`RESERVADO`** |
| 3 | `SELECT ... FOR UPDATE`, mesma transação | `RESERVADO` | `RESERVADO` |
| 4 | `SELECT` simples, transação nova | `RESERVADO` | `RESERVADO` |

**Leitura.** Em `REPEATABLE READ`, as leituras 2 e 3 são da mesma transação, com
milissegundos de distância, e discordam. Não é cache do cliente nem erro: é versionamento.
A leitura 2 é servida pelo MVCC a partir da versão antiga guardada no undo log, porque o
read view foi fixado no passo 3 e não se move. A leitura 3 ignora o retrato: uma leitura
bloqueante precisa operar sobre o que realmente está lá, senão bloquearia uma versão que já
não existe.

Em `READ COMMITTED` a divergência desaparece, porque cada comando pega um retrato novo e a
leitura 2 já vê o `UPDATE` confirmado. A leitura 3 é idêntica nos dois níveis — **a leitura
bloqueante não depende do nível de isolamento**, e é isso que a torna a base segura para
revalidar.

**É por isso que a revalidação do procedimento usa `FOR UPDATE`, e não um `SELECT`
comum.** Com `SELECT` comum em `REPEATABLE READ`, uma sessão que esperou o bloqueio releria
`DISPONIVEL` — o valor do seu retrato —, concluiria que o assento está livre e autorizaria
a reserva dobrada, reproduzindo o A0 apesar de todo o bloqueio. A camada 2 inteira depende
dessa distinção, e o A1 mostra ela funcionando: lá o valor relido foi `RESERVADO`.

### 6.10 F — o `WHERE`, o índice e o escopo do bloqueio

**Pergunta.** O bloqueio de S1 no 10A alcança o 10B?

S1 bloqueia o 10A de duas formas diferentes e S2 tenta bloquear o **10B**, um assento que
não tem nada a ver com a operação de S1. Rodado nos dois níveis de isolamento.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;` (2ª rodada: `READ COMMITTED`) |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 1;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE numero = '10A' FOR UPDATE;` — sem `voo_id` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE voo_id = 1 AND numero = '10B' FOR UPDATE;` |
| 7 | S2 | `ROLLBACK;` |
| 8 | S1 | `COMMIT;` |

Depois `CALL sp_resetar_cenario();` e os mesmos passos com o passo 4 trocado por
`SELECT id FROM assentos WHERE voo_id = 1 AND numero = '10A' FOR UPDATE;`.

Os planos que explicam a diferença:

```sql
EXPLAIN SELECT id FROM assentos WHERE numero = '10A' FOR UPDATE;
EXPLAIN SELECT id FROM assentos WHERE voo_id = 1 AND numero = '10A' FOR UPDATE;
```

**Resultado medido.**

| `WHERE` de S1 | `EXPLAIN` | S2 conseguiu o **10B**? |
|---|---|---|
| `numero = '10A'` | `type=index`, `key=uq_assento_voo`, `rows=3` | **`REPEATABLE READ`: não** (1205 em 1,047 s)<br>**`READ COMMITTED`: sim** (0,000 s) |
| `voo_id = 1 AND numero = '10A'` | `type=const`, `key=uq_assento_voo`, `rows=1` | **Sim nos dois níveis** (0,000 s) |

**A reserva saiu correta em todos os quatro casos.** Depois de cada cenário, uma chamada a
`sp_reservar_assento(1, 1, '10A')` sobre o banco resetado produziu `status = RESERVADO` e
exatamente **1** reserva confirmada.

**Leitura.** O `WHERE` não muda a correção do resultado, muda o **escopo do bloqueio**.

O InnoDB não bloqueia "a linha que o `WHERE` descreve": bloqueia as linhas que precisou
**examinar** para avaliar o `WHERE`. A tabela tem `UNIQUE (voo_id, numero)`, e `numero` não
é prefixo à esquerda desse índice, então `WHERE numero = '10A'` não tem acesso direto e
vira varredura do índice inteiro — `type=index`, `rows=3` — com trava em tudo que passou
pelo caminho, inclusive no 10B e no 10C. Com o par completo, o acesso é `type=const`,
`rows=1`, e a trava fica na única linha pedida.

**O resultado continua correto no cenário ruim**, e isso é importante para não tirar a
conclusão errada. Nenhuma reserva sai dobrada, nenhum assento fica inconsistente: as quatro
camadas da seção 3 continuam valendo, e a verificação acima confirma. O que se perde é
**concorrência**. Reservas de assentos diferentes, que no A3 correram em paralelo em
0,016 s cada, passam a se bloquear mutuamente. As consequências práticas são três, todas já
medidas em outros experimentos deste documento:

- **mais espera** — o concorrente fica parado pelo tempo da transação alheia (B);
- **mais 1205** — a espera passa a ter chance real de estourar o limite, e foi o que
  aconteceu aqui em `REPEATABLE READ`, com o limite em 1 s (C);
- **mais deadlock** — quanto mais linhas cada transação trava, mais pares de espera
  existem e maior a chance de um deles fechar ciclo (D1).

É degradação de desempenho e de disponibilidade sob carga, não perda de correção. O sintoma
no cliente é um 1205 numa operação que não disputava nada com ninguém — difícil de
diagnosticar justamente porque o dado nunca fica errado.

**A diferença entre os níveis de isolamento.** Em `READ COMMITTED`, S2 conseguiu o 10B
mesmo no cenário sem índice. O InnoDB, nesse nível, **libera as travas das linhas que não
casam com o `WHERE` depois de avaliá-las**: as linhas do 10B e do 10C foram travadas
durante a varredura e destravadas em seguida, sobrando apenas a trava do 10A, que é a linha
que de fato casou. Em `REPEATABLE READ` as travas da varredura são retidas até o fim da
transação, porque é isso que sustenta a garantia de releitura estável do nível.

Ou seja: o mesmo `WHERE` mal escrito custa muito mais caro em `REPEATABLE READ` — o padrão
do MySQL — do que em `READ COMMITTED` — o padrão do PostgreSQL. Um `WHERE` que parece
inofensivo no PostgreSQL pode serializar o sistema inteiro ao ser portado.

## 7. MVCC e isolamento: o que muda entre os dois níveis

O isolamento padrão do MySQL é `REPEATABLE READ`; o do PostgreSQL é `READ COMMITTED`. Os
Experimentos E e F foram rodados nos dois níveis, **no MySQL**, para separar o que é
diferença de nível do que é diferença de banco:

| Comportamento | `REPEATABLE READ` | `READ COMMITTED` |
|---|---|---|
| `SELECT` simples relendo linha alterada e confirmada por outra sessão (E, leitura 2) | vê o valor **antigo** | vê o valor **novo** |
| `SELECT ... FOR UPDATE` na mesma situação (E, leitura 3) | vê o valor **novo** | vê o valor **novo** |
| Travas de linhas varridas que não casam com o `WHERE` (F) | **retidas** até o fim da transação | **liberadas** após a avaliação |

O que **não** foi medido: o comportamento do PostgreSQL. Não há PostgreSQL neste ambiente.
A tabela acima é toda MySQL 8.0.46; o que se pode dizer do PostgreSQL é que o seu padrão é
`READ COMMITTED`, e portanto que um código portado sem ajuste encontra a coluna da direita
lá e a da esquerda aqui.

A consequência de projeto é que a correção do procedimento não pode depender do nível de
isolamento configurado. As quatro camadas da seção 3 funcionam nos dois níveis, porque
nenhuma delas pressupõe o comportamento do retrato: a camada 1 serializa, a 2 relê **com
bloqueio** (que, como a tabela mostra, dá o mesmo resultado nos dois níveis), a 3 revalida
no próprio `UPDATE` e a 4 é declarativa. Um procedimento que revalidasse com `SELECT`
simples estaria correto em `READ COMMITTED` por acidente do padrão e **errado em
`REPEATABLE READ`** — e voltaria a estar errado no PostgreSQL no dia em que alguém subisse
o isolamento.

## 8. Respostas às perguntas

**1. O que acontece quando duas transações tentam reservar o mesmo assento?** A segunda
para no `SELECT ... FOR UPDATE` e fica parada até a primeira confirmar ou desfazer —
2,015 s quando a primeira segurou 2,0 s (A1). Ao acordar, ela relê o status já como
`RESERVADO` e é recusada com 1644. Uma reserva confirmada, nenhum assento vendido duas
vezes.

**2. E se não houvesse restrição nenhuma?** As duas conseguiriam. Sem a `UNIQUE`, com
`SELECT` comum e `UPDATE` sem condição de status, o A0 produziu **duas reservas
CONFIRMADA para o mesmo assento e nenhum erro em nenhum passo**. É o desfecho contra o
qual todas as outras camadas existem.

**3. Por que `FOR UPDATE` e não só o `UPDATE` condicional?** O `UPDATE` condicional sozinho
também impediria a duplicidade, mas à custa de trabalho perdido: as duas transações
avançariam até a escrita e uma seria desfeita no fim. O `FOR UPDATE` serializa antes, e a
perdedora descobre o problema na revalidação, antes de escrever. Além disso, sem ele não
existe ponto seguro para reler o status (E).

**4. Duas reservas de assentos diferentes se atrapalham?** Não. Dois passageiros chamando o
procedimento ao mesmo tempo para 10A e 10B terminaram os dois com sucesso, em 0,016 s
cada, sem espera (A3). O bloqueio é da linha do assento, não do voo.

**5. A espera é indefinida?** Não. Ela termina no `COMMIT` da outra sessão — diferença de
0,000 s nas duas medições do B — ou no `innodb_lock_wait_timeout`, que abortou o comando em
2,109 s com o limite em 2 s (C).

**6. Qual a diferença entre 1205 e 1213?** O 1205 é espera esgotada: só o comando é
desfeito, **a transação continua viva** e o cliente pode tentar de novo (C). O 1213 é ciclo
detectado: a transação **inteira** da vítima é desfeita, em 0,015 s, e só resta recomeçar
(D1). Tratar os dois igual é errado nas duas direções — repetir só o comando após um 1213
opera numa transação que não existe mais, e refazer tudo após um 1205 joga fora trabalho
válido.

**7. Uma transação sempre vê o dado mais recente?** Não. Em `REPEATABLE READ`, um `SELECT`
simples vê o retrato do início da transação — a leitura 2 do E devolveu `DISPONIVEL` depois
de o `UPDATE` já estar confirmado. Só a leitura bloqueante vê a versão confirmada mais
recente, e a mesma transação devolveu `RESERVADO` no comando seguinte. Quem valida
concorrência com `SELECT` simples valida contra um retrato antigo.

**8. O nível de isolamento muda o resultado?** Muda o que o `SELECT` simples vê e por
quanto tempo as travas de varredura são retidas, mas **não** muda o que a leitura
bloqueante vê (seção 7). Em `READ COMMITTED` a leitura 2 do E já devolveu `RESERVADO`, e no
F as travas das linhas não correspondentes foram liberadas. A leitura 3 do E foi idêntica
nos dois níveis — e é sobre ela que o procedimento se apoia.

**9. Como evitar deadlock?** Ordem única de aquisição de bloqueios. O D1 e o D2 são o mesmo
cenário, com os mesmos dois assentos e a mesma contenção, e a única diferença é a ordem: em
ordem invertida (1→2 contra 2→1) houve 1213 em 0,015 s; em ordem crescente de `id` nas duas
sessões **não houve deadlock nenhum** — S2 esperou 0,500 s e as duas confirmaram. Com a
espera apontando sempre na mesma direção, o grafo não fecha ciclo. Secundariamente:
transações curtas, porque o tempo segurando bloqueio é o tempo de exposição, e o custo dele
é pago pelos concorrentes (B); e `WHERE` que use índice, para travar menos linhas e criar
menos pares de espera (F).

**10. O `WHERE` muda o escopo do bloqueio?** Sim, e sem mudar a correção. Um `WHERE` que
não pode usar o índice faz o `FOR UPDATE` travar todas as linhas varridas — três em vez de
uma no F —, e reservas de assentos independentes passam a se bloquear. A reserva continua
saindo certa; o que se degrada é espera, risco de 1205 e chance de deadlock. Em
`READ COMMITTED` o efeito é menor, porque as travas das linhas não correspondentes são
liberadas após a avaliação.

## 9. Conclusões

1. **A corrida é real e silenciosa.** Sem restrição, duas sessões confirmaram o mesmo
   assento sem um único erro (A0). Nenhuma das duas tinha como perceber: cada uma, isolada,
   fez tudo certo. É o cenário que só aparece com duas sessões, e nunca em teste sequencial.
2. **A restrição declarativa é a única camada que vale sempre.** As três camadas de
   aplicação protegem quem usa o procedimento; a `UNIQUE (assento_ativo)` protege contra
   quem não usa (A2). Se apenas uma pudesse ser mantida, seria ela.
3. **Leitura bloqueante e leitura simples respondem coisas diferentes, e a diferença é
   silenciosa.** A mesma transação devolveu `DISPONIVEL` e `RESERVADO` com milissegundos de
   distância (E). O código que revalida precisa usar `FOR UPDATE`; nada no resultado de um
   `SELECT` simples indica que ele está desatualizado. E essa é a única leitura cujo
   resultado não muda com o nível de isolamento (seção 7).
4. **Serializar o recurso certo é parte do requisito.** O bloqueio tem de valer para o
   assento disputado e não para o voo: no A3 duas reservas simultâneas de assentos
   diferentes passaram sem espera, o que é o que torna o sistema utilizável.
5. **1205 e 1213 exigem tratamentos diferentes** porque deixam a transação em estados
   diferentes: viva em um caso, desfeita no outro (C, D1).
6. **Deadlock se previne no projeto, não no `catch`.** D1 e D2 diferem só pela ordem de
   aquisição, e essa diferença é a presença ou a ausência do 1213. Ordem única elimina o
   ciclo por construção; tratar o erro é o plano B, e ele é obrigatório porque a vítima é
   escolhida pelo servidor — ela mudou entre execuções.
7. **`WHERE` sem índice é questão de escopo de bloqueio, não de correção.** O resultado
   continua certo (verificado nos quatro cenários do F), mas o `FOR UPDATE` trava todas as
   linhas varridas e reservas independentes começam a se bloquear, aumentando espera, risco
   de 1205 e chance de deadlock. O custo é maior em `REPEATABLE READ`, onde as travas de
   varredura são retidas até o fim da transação.
