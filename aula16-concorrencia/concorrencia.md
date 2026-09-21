# Aula 16: locking, deadlocks e MVCC

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Controle de concorrência em um cenário de reserva de assentos: a condição de corrida
acontecendo, bloqueio pessimista com `SELECT ... FOR UPDATE`, espera por bloqueio, estouro
de tempo de espera, deadlock, prevenção de deadlock, MVCC e os três níveis de isolamento.
Cada experimento usa duas sessões simultâneas, com passo a passo reproduzível à mão.

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

## 1. Por que um banco separado

O banco desta aula é o `aeroporto_concorrencia`, construído a partir do esquema sugerido
pelo professor, e não do modelo individual que as Aulas 08 a 15 desenvolvem.

A razão é estrutural. O exercício inteiro gira em torno de bloquear **a linha de um
assento** e reler o seu status depois do bloqueio. No modelo individual o assento não é
uma entidade: é a coluna `assento VARCHAR(4)` dentro de `passagem`. Não existe linha de
assento para bloquear. Existe a linha da passagem, que só passa a existir depois de a
reserva ter sido decidida. Fazer `FOR UPDATE` no modelo individual bloquearia o registro
da venda em vez do recurso disputado, e o experimento perderia o objeto de estudo.

O nome diferente também protege o trabalho anterior: o `aeroporto` é reconstruído do zero
pelo `sql_integridade.sql` e a Aula 15 depende dele. Um `DROP DATABASE` nesta aula
apagaria as duas.

O que as duas modelagens têm em comum está registrado: a `UNIQUE (voo_id, numero)` de
`assentos` é o equivalente exato da `UNIQUE (id_voo, assento)` que o modelo individual
carrega desde a Aula 08, e a coluna gerada da seção 2 usa o mesmo comportamento de `NULL`
sob `UNIQUE` que a Aula 10 usou para aceitar vários passageiros estrangeiros sem CPF.

**A ligação com a limitação documentada na Aula 10.** A trigger
`trg_passagem_capacidade_insert`, criada na Aula 10 para impedir que as passagens vendidas
passassem da capacidade da aeronave, registrou como limitação conhecida que duas inserções
simultâneas podem ler a mesma contagem: as duas executam o `SELECT COUNT(*)` antes de
qualquer uma gravar, as duas concluem que ainda há assento, e as duas passam. Essa é
exatamente a condição de corrida que o Experimento A0 desta aula reproduz e mede, com a
diferença de que lá o valor lido é uma contagem e aqui é um status. A correção seria a
mesma que o `sp_reservar_assento` aplica: travar a linha do voo com
`SELECT ... FOR UPDATE` no início da trigger, antes de contar, para que a segunda inserção
espere e reconte depois da primeira. A Aula 10 não é alterada por esta aula, e o registro
aqui serve para ligar a limitação que ela documentou ao mecanismo que a resolve.

## 2. Adaptações de PostgreSQL para MySQL

O enunciado é escrito em PostgreSQL e pede que as adaptações sejam feitas e justificadas.

| Enunciado (PostgreSQL) | Neste arquivo (MySQL 8) | Por que |
|---|---|---|
| `BIGSERIAL` | `BIGINT AUTO_INCREMENT` | No MySQL o contador é propriedade da coluna, e não um objeto `SEQUENCE` separado |
| `TIMESTAMP` | `DATETIME` | O `TIMESTAMP` do MySQL tem faixa 1970 a 2038 e converte para UTC e de volta conforme o fuso da sessão. `DATETIME` guarda o valor literal |
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

Funciona porque um índice `UNIQUE` aceita vários `NULL`: dois `NULL` não são considerados
iguais entre si. As reservas canceladas viram `NULL` e saem da restrição, sobrando
exatamente uma confirmada por assento. `STORED` em vez de `VIRTUAL` porque o valor precisa
estar gravado para o índice não depender de recálculo na leitura.

O efeito colateral é bom: cancelar uma reserva libera o assento automaticamente, sem
código de aplicação. O Experimento A2 mede isso.

**Uma diferença que vai além da sintaxe.** O isolamento padrão do MySQL é
`REPEATABLE READ`, e o do PostgreSQL é `READ COMMITTED`. Isso muda o resultado observável.
Os Experimentos A0′, E e F foram rodados em mais de um nível por causa disso, e a seção 7
compara os três.

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
existe" de "o assento existe e está ocupado": as duas situações viram zero linhas.
Bloqueia-se a linha primeiro e decide-se depois, que é o próprio ponto da revalidação.

**`SELECT ... INTO` sem linhas não é erro no MySQL.** Gera o aviso 1329 e deixa as
variáveis como estavam, e a execução segue. Em PL/pgSQL isso levantaria `NO_DATA_FOUND` e
o handler tomaria conta. Aqui não: sem o `IF v_assento_id IS NULL` explícito, o
procedimento seguiria com `NULL`, o `UPDATE` não acharia nada e o `INSERT` falharia por
chave estrangeira, um erro confuso e muito longe da causa. Por isso a variável nasce com
`DEFAULT NULL` e é testada.

**`ROW_COUNT()` é lido imediatamente após o `UPDATE`.** Qualquer outro comando no meio o
sobrescreve. É a primeira instrução depois do `UPDATE`, por necessidade e não por estilo.

O `EXIT HANDLER FOR SQLEXCEPTION` faz `ROLLBACK` e `RESIGNAL`. O `RESIGNAL` é o que
importa: sem ele o procedimento engoliria a falha e o cliente acharia que a reserva deu
certo, o pior desfecho possível em um sistema de reservas. Com ele, o código original
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
   Statement* (`Ctrl+Enter`). O botão de raio executa o script inteiro e não serve aqui,
   porque o ponto é justamente intercalar.
5. Entre um experimento e o próximo, rode em qualquer aba:
   ```sql
   CALL sp_resetar_cenario();
   ```
   Ele devolve os três assentos para `DISPONIVEL` e apaga as reservas, o que torna o
   roteiro reproduzível na ordem em que está escrito.

Alguns passos estão marcados com **(bloqueia)**. Neles a aba trava e o Workbench fica com
o indicador de execução girando. Esse é o comportamento esperado, e é o objeto de estudo.
A aba destrava sozinha quando a outra sessão fizer `COMMIT` ou `ROLLBACK`, ou quando o
`innodb_lock_wait_timeout` estourar. Não cancele a execução, porque é isso que se quer
observar.

**Sobre os tempos deste documento.** Os passos abaixo foram executados na ordem publicada,
com os tempos medidos por instrumentação em volta exatamente do comando que bloqueia, para
não depender da velocidade de digitação. Reproduzindo à mão, os desfechos, os códigos de
erro e os valores lidos são os mesmos. Os tempos em segundos variam conforme o intervalo
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
| **A0** | Corrida sem restrição | `UNIQUE` removida; as duas sessões leem com `SELECT` comum e escrevem | **Duas reservas CONFIRMADA para o mesmo assento**, sem erro nenhum | nenhum |
| **A0′** | O mesmo roteiro em `SERIALIZABLE` | `UNIQUE` removida; as duas sessões em `SERIALIZABLE` | As duas leituras passam e leem `DISPONIVEL`. O `UPDATE` de S1 esperou **0,313 s** e passou; o de S2 foi morto. **Uma** reserva confirmada | **1213** `Deadlock found when trying to get lock` |
| **A1** | Disputa pelo procedimento | S1 segura o bloqueio 2,0 s; S2 chama `sp_reservar_assento` no mesmo assento | S2 esperou **2,015 s**, acordou e foi **recusada**. Um assento, uma reserva | **1644** `Assento 10A do voo 1 nao esta disponivel (status atual: RESERVADO)` |
| **A2** | Só a `UNIQUE` | Dois `INSERT` diretos, sem procedimento, sem transação, sem `FOR UPDATE` | O segundo **rejeitado**. Após cancelar a primeira, o mesmo `INSERT` **passou** | **1062** `Duplicate entry '1' for key 'reservas.uq_reserva_assento_ativa'` |
| **A3** | Assentos diferentes | Dois passageiros chamam o procedimento ao mesmo tempo, 10A e 10B | **As duas com sucesso e sem espera**: 0,016 s cada. Duas reservas confirmadas | nenhum |
| **B** | Duração da espera | S1 segura 1,0 s / 3,0 s | S2 esperou **1,000 s** e **3,000 s** (diferença **+0,000 s** nas duas) | nenhum |
| **C** | Espera esgotada | `innodb_lock_wait_timeout = 2s` em S2; S1 segura 6,0 s | S2 abortou em **2,109 s**, sem esperar os 6 s. A transação de S2 **continuou viva** | **1205** `Lock wait timeout exceeded` |
| **D1** | Deadlock | S1 bloqueia `id` 1→2; S2 bloqueia `id` 2→1 | Ciclo detectado em **0,015 s**. Vítima: **S1 nesta execução; variou entre execuções (6.8)**. A transação da vítima é desfeita inteira e a outra confirma | **1213** `Deadlock found when trying to get lock` |
| **D2** | Ordem crescente | As duas sessões bloqueiam `id` 1→2, na mesma ordem | **Nenhum deadlock.** S2 esperou **0,500 s** pelo `id` 1 e as duas confirmaram | nenhum |
| **E** | MVCC em `REPEATABLE READ` | S2 fixa o read view; S1 altera e confirma; S2 relê | Mesma transação: `SELECT` simples **DISPONIVEL**, `FOR UPDATE` **RESERVADO** | nenhum |
| **E′** | MVCC em `READ COMMITTED` | Os mesmos passos, com S2 em `READ COMMITTED` | `SELECT` simples já devolveu **RESERVADO** | nenhum |
| **F** | Escopo do bloqueio | S1 bloqueia o 10A com e sem índice utilizável; S2 pede o **10B** | `REPEATABLE READ`: sem índice S2 **não conseguiu** o 10B; com índice **conseguiu**. `READ COMMITTED`: **conseguiu nos dois**. Reserva correta em todos os casos | **1205** só no primeiro caso |

## 6. Os experimentos, passo a passo

### 6.1 A0: a condição de corrida acontecendo

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
confirmação. É o desfecho que o sistema não pode ter, e ele acontece sem que nada dê
errado do ponto de vista de cada sessão isolada.

O defeito está nos passos 3 e 5. As duas sessões leram `DISPONIVEL` e as duas decidiram
que o assento estava livre. A segunda leitura já estava errada no instante em que foi
feita, porque S1 estava a caminho de ocupar o assento. Ler, decidir e escrever em passos
separados, sem bloqueio nem revalidação, produz a condição de corrida.

Repare que o passo 9 nem chegou a esperar, porque o `UPDATE` de S1 já tinha sido
confirmado no passo 8. Se o passo 9 fosse executado antes do `COMMIT` de S1, ele ficaria
bloqueado pela trava de linha, e o desfecho seria o mesmo: depois de destravar ele
aplicaria o `SET status = 'RESERVADO'` de novo, sem condição de status que o impedisse, e
o `INSERT` seguiria. Bloqueio de linha sozinho, sem `UPDATE` condicional nem revalidação,
não resolve.

**Restaurar a restrição** antes de seguir para o A1:

| Passo | Sessão | Comando |
|---|---|---|
| 13 | S1 | `CALL sp_resetar_cenario();` |
| 14 | S1 | `ALTER TABLE reservas ADD CONSTRAINT uq_reserva_assento_ativa UNIQUE (assento_ativo);` |
| 15 | S1 | `SHOW INDEX FROM reservas WHERE Key_name = 'uq_reserva_assento_ativa';` |

O passo 13 vem antes do 14 por necessidade: com as duas reservas duplicadas ainda na
tabela, a criação da `UNIQUE` falharia. O passo 15 confirma que o índice voltou.

### 6.2 A0′: o mesmo roteiro em SERIALIZABLE

**Pergunta.** O nível `SERIALIZABLE` impede a corrida do A0, mesmo sem a `UNIQUE`?

Rigorosamente o mesmo roteiro do A0, com a `UNIQUE` removida e uma única mudança: as duas
sessões passam para `SERIALIZABLE` antes de abrir as transações.

No MySQL, `SERIALIZABLE` faz o servidor promover todo `SELECT` comum a
`SELECT ... LOCK IN SHARE MODE`. Isso muda o A0 no passo da leitura, que deixa de ser uma
leitura sem trava.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `ALTER TABLE reservas DROP INDEX uq_reserva_assento_ativa;` |
| 2 | S1 | `SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;` |
| 3 | S2 | `SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;` |
| 4 | S1 | `START TRANSACTION;` |
| 5 | S1 | `SELECT status FROM assentos WHERE id = 1;` (toma trava compartilhada) |
| 6 | S2 | `START TRANSACTION;` |
| 7 | S2 | `SELECT status FROM assentos WHERE id = 1;` (toma trava compartilhada também) |
| 8 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` **(bloqueia)** |
| 9 | S2 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` fecha o ciclo |
| 10 | S2 | recebe 1213 na hora; `ROLLBACK;` |
| 11 | S1 | destrava, segue com `INSERT ...` e `COMMIT;` |
| 12 | S1 | `SELECT assento_id, COUNT(*) AS confirmadas FROM reservas WHERE status = 'CONFIRMADA' GROUP BY assento_id;` |

Depois, restaurar a restrição com os passos 13 a 15 do A0.

**Resultado medido.**

```
 S1 | SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE
 S2 | SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE
 S1 | SELECT @@transaction_isolation   -> SERIALIZABLE
 S1 | SELECT status FROM assentos WHERE id = 1   -> DISPONIVEL
 S2 | SELECT status FROM assentos WHERE id = 1   -> DISPONIVEL
 S2 | UPDATE assentos SET status = 'RESERVADO' WHERE id = 1
      -> ERRO 1213: Deadlock found when trying to get lock   (0.000s)
 S1 | UPDATE assentos SET status = 'RESERVADO' WHERE id = 1   (0.313s)
 S2 | ROLLBACK
 S1 | INSERT INTO reservas ... VALUES (1, 1, 'CONFIRMADA')
 S1 | COMMIT

assentos: 10A=RESERVADO, 10B=DISPONIVEL, 10C=DISPONIVEL
reservas confirmadas: 1
```

**Leitura.** A corrida do A0 foi impedida: uma reserva confirmada em vez de duas, sem
`UNIQUE` e sem nenhuma mudança no SQL da aplicação. O preço aparece na forma do desfecho.

As duas leituras dos passos 5 e 7 **passaram as duas**, e as duas leram `DISPONIVEL`,
igual ao A0. Travas compartilhadas são compatíveis entre si, então a promoção do `SELECT`
não serializa as leituras. O conflito aparece no `UPDATE`: cada sessão precisa de trava
exclusiva sobre a linha que a outra ainda mantém em modo compartilhado, e nenhuma pode
soltar a sua enquanto a transação está aberta. As duas ficam esperando uma pela outra, e o
InnoDB detecta o ciclo imediatamente.

O erro real é **1213**, o mesmo do D1. O MySQL sinaliza esse conflito como deadlock, por
uma característica da implementação: o `SERIALIZABLE` dele é construído sobre
travas de linha, e a falha de serialização chega ao cliente como deadlock. O PostgreSQL,
que usa Serializable Snapshot Isolation, sinaliza esse tipo de conflito com o
`SQLSTATE 40001` (`could not serialize access`). Esse comportamento do PostgreSQL **não
foi medido**, porque não há PostgreSQL neste ambiente.

Nas três execuções deste roteiro a vítima foi sempre S2, diferente do D1. A razão é o
roteiro: aqui S1 pede a trava exclusiva primeiro e S2 é quem fecha o ciclo, então o InnoDB
mata S2. No D1 as duas sessões disputam o mesmo instante e a escolha varia.

A consequência prática está na resposta da pergunta 12: elevar o isolamento não elimina o
tratamento de erro da aplicação, e sim troca o erro que ela precisa tratar. Sob
`SERIALIZABLE` a reserva passa a falhar com 1213 em disputa normal, e o cliente precisa
repetir a transação inteira.

### 6.3 A1: disputa pelo mesmo assento com o procedimento

**Pergunta.** Quem ganha o 10A, e o que a perdedora recebe?

S1 executa os passos do procedimento à mão, para que haja uma janela em que o bloqueio está
tomado e a transação ainda não confirmou. S2 chama o procedimento de verdade, e é o lado de
S2 que está sob teste.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `START TRANSACTION;` |
| 2 | S1 | `SELECT id, status FROM assentos WHERE voo_id = 1 AND numero = '10A' FOR UPDATE;` |
| 3 | S2 | `CALL sp_reservar_assento(2, 1, '10A');` **(bloqueia)** |
| 4 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1 AND status = 'DISPONIVEL';` |
| 5 | S1 | `INSERT INTO reservas (passageiro_id, assento_id, status) VALUES (1, 1, 'CONFIRMADA');` |
| 6 | S1 | `COMMIT;` |
| 7 | S2 | a aba destrava sozinha e mostra o erro |
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

**Leitura.** O que este experimento localiza é **onde** S2 falhou. S2 não foi barrada pela
`UNIQUE` nem pelo `UPDATE` condicional. Foi barrada pela revalidação pós-lock, a camada 2,
que leu `RESERVADO` num `SELECT` que, quando S2 começou a esperar, teria devolvido
`DISPONIVEL`. É esse valor relido que prova que a leitura bloqueante não usa o retrato da
transação, e o Experimento E isola o comportamento.

Comparado ao A0, a diferença é inteira: mesmo cenário, mesma disputa, e aqui uma reserva
confirmada em vez de duas.

### 6.4 A2: a UNIQUE sozinha, sem cliente colaborativo

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
sem bloqueio, pela restrição declarativa, que é exatamente o que faltava no A0. E o
cancelamento devolve o assento sem nenhuma linha de código: a coluna gerada virou `NULL`,
saiu da `UNIQUE`, e a vaga reabriu. A reserva cancelada continua na tabela, preservando o
histórico.

### 6.5 A3: assentos diferentes do mesmo voo, ao mesmo tempo

**Pergunta.** Duas reservas de assentos distintos se atrapalham?

Requisito explícito da seção 21 do enunciado: a serialização precisa valer para o assento
disputado. Se valesse para o voo inteiro, duas reservas de assentos diferentes se
bloqueariam e o sistema ficaria correto e inútil.

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
assento pedido**, e não a tabela nem o voo, então reservas de assentos diferentes correm em
paralelo. É a granularidade correta: o custo do bloqueio é pago só por quem disputa o mesmo
recurso.

O Experimento F mostra que essa granularidade depende de o `WHERE` poder usar o índice, e
o `WHERE` do procedimento usa o par `(voo_id, numero)` justamente por isso.

### 6.6 B: duração da espera

**Pergunta.** A espera de S2 acompanha o tempo que S1 segura o bloqueio?

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `START TRANSACTION;` |
| 2 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 3 | S2 | `START TRANSACTION;` |
| 4 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia)** |
| 5 | S1 | `COMMIT;` (espere um tempo conhecido antes deste passo) |
| 6 | S2 | destrava no instante do `COMMIT` de S1 |
| 7 | S2 | `COMMIT;` |

Repetido com dois tempos de retenção entre os passos 4 e 5.

**Resultado medido.**

| S1 segurou | S2 esperou | Diferença |
|---|---|---|
| 1,0 s | 1,000 s | +0,000 s |
| 3,0 s | 3,000 s | +0,000 s |

**Leitura.** A espera acompanha o tempo de retenção com diferença de 0,000 s nas duas
medições. Quem determina a duração do bloqueio é o `COMMIT` da concorrente. S2 não espera
um intervalo fixo nem faz nova tentativa em laço: fica parada no `FOR UPDATE` e é liberada
no instante em que a outra transação termina.

Isso responde a uma pergunta prática: o custo de uma transação longa é pago por todas as
que precisarem das mesmas linhas. Uma transação que segura o bloqueio por 3 s e faz mais
nove operações lentas antes do `COMMIT` transfere esses 3 s para cada concorrente na fila.

### 6.7 C: espera esgotada (1205)

**Pergunta.** O que acontece quando a espera passa do limite da sessão?

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S2 | `SET SESSION innodb_lock_wait_timeout = 2;` |
| 2 | S2 | `SELECT @@innodb_lock_wait_timeout;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia, e falha em 2 s)** |
| 7 | S2 | `SELECT COUNT(*) FROM assentos;` (a transação de S2 ainda está viva) |
| 8 | S2 | `ROLLBACK;` |
| 9 | S1 | `COMMIT;` |

O passo 9 vem depois de propósito: S1 ainda segurava o bloqueio quando S2 já havia
desistido.

**Resultado medido.** S1 segurou o bloqueio por 6,0 s, e o limite de S2 era 2 s.

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
cliente decide o que fazer: repetir o comando, seguir por outro caminho ou desistir com
`ROLLBACK`. Essa é a diferença de fundo em relação ao deadlock do 6.8, e é o motivo de os
dois erros não poderem ser tratados pelo mesmo `catch`.

### 6.8 D1: deadlock por ordem invertida (1213)

**Pergunta.** O servidor detecta o ciclo, e o que sobra da transação da vítima?

S1 pede os assentos na ordem 1 para 2, e S2 na ordem **invertida**, 2 para 1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` |
| 7 | S1 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` **(bloqueia)** |
| 8 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` fecha o ciclo |
| 9 | (as duas) | uma das duas recebe 1213 na hora; a outra destrava e segue |
| 10 | (a sobrevivente) | `COMMIT;` |
| 11 | (a vítima) | `ROLLBACK;` |
| 12 | S1 | `SHOW ENGINE INNODB STATUS;` seção `LATEST DETECTED DEADLOCK` |

O `innodb_lock_wait_timeout` reduzido nos passos 1 e 2 não é necessário para o deadlock.
Ele serve para que, se o ciclo não se formar por erro de roteiro, a falha apareça em 5 s
em vez de 50 s.

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
das duas estava em 5 s e não chegou a ser consultado. O InnoDB mantém um grafo de espera e
detecta o fechamento do ciclo no instante em que a segunda requisição entra, sem precisar
esperar. O 1205 depende de um tempo decorrido; o 1213 depende apenas do estado do grafo.

**A transação da vítima foi desfeita inteira**, e não apenas o comando. Depois do 1213 não
há o que continuar, e a vítima só pode recomeçar do zero.

**A escolha da vítima é do servidor, e isso foi observado.** Na execução transcrita acima a
vítima foi S1. Em outra execução do mesmo roteiro, sem nenhuma alteração, a vítima foi
**S2** e S1 sobreviveu. A ordem em que os passos 7 e 8 chegam ao servidor também varia,
porque as duas sessões disputam o mesmo instante. O InnoDB escolhe a transação com menos
trabalho a desfazer, e com as duas fazendo trabalho equivalente o resultado muda entre
execuções. Nenhuma das duas pode assumir que vai ser a sobrevivente, e as duas precisam do
mesmo tratamento de erro. A frequência de cada desfecho não foi medida, e a afirmação aqui
se limita a registrar que a escolha é do servidor e que ela mudou.

### 6.9 D2: a mesma disputa em ordem crescente de `id`

**Pergunta.** A ordem única de aquisição elimina o deadlock?

Rigorosamente o mesmo cenário do D1, com as mesmas duas sessões, os mesmos dois assentos e
o mesmo entrelaçamento, com **uma única mudança**: S2 também pede na ordem 1 para 2, em vez
de 2 para 1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 5;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` |
| 5 | S2 | `START TRANSACTION;` |
| 6 | S2 | `SELECT id FROM assentos WHERE id = 1 FOR UPDATE;` **(bloqueia, S1 detém o `id` 1)** |
| 7 | S1 | `SELECT id FROM assentos WHERE id = 2 FOR UPDATE;` |
| 8 | S1 | `COMMIT;` |
| 9 | S2 | destrava e obtém o `id` 1 |
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

**Leitura.** Nenhum 1213, e as duas transações confirmaram. S2 esperou 0,500 s, o tempo
exato em que S1 ainda estava trabalhando, e depois seguiu sem obstáculo, porque quando ela
finalmente obteve o `id` 1, S1 já havia liberado o `id` 2 também.

O ciclo do D1 não se formou porque não podia se formar. Com as duas sessões pedindo em
ordem crescente de `id`, quem tem o `id` 1 nunca está esperando por quem tem o `id` 2: a
espera aponta sempre na mesma direção, e um grafo de espera que aponta sempre para o mesmo
lado não fecha ciclo. A contenção continua existindo, e a ordem única não promete eliminá-la.
O que muda é que a espera passa a terminar sempre.

Comparando D1 e D2: mesma carga, mesmos recursos, mesma contenção, e a única variável é a
ordem de aquisição. É a prova da resposta da **pergunta 9** da seção 8.

### 6.10 E: MVCC nos dois níveis de isolamento

**Pergunta.** A mesma transação pode ver dois valores diferentes da mesma linha?

Rodado **duas vezes**, mudando apenas o nível de isolamento de S2 no passo 1.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S2 | `SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;` (2ª rodada: `READ COMMITTED`) |
| 2 | S2 | `START TRANSACTION;` |
| 3 | S2 | `SELECT status FROM assentos WHERE id = 1;` **leitura 1**, fixa o read view |
| 4 | S1 | `START TRANSACTION;` |
| 5 | S1 | `UPDATE assentos SET status = 'RESERVADO' WHERE id = 1;` |
| 6 | S1 | `COMMIT;` |
| 7 | S2 | `SELECT status FROM assentos WHERE id = 1;` **leitura 2** |
| 8 | S2 | `SELECT status FROM assentos WHERE id = 1 FOR UPDATE;` **leitura 3** |
| 9 | S2 | `COMMIT;` |
| 10 | S2 | `SELECT status FROM assentos WHERE id = 1;` **leitura 4**, transação nova |

**Resultado medido.**

| Leitura | Comando | `REPEATABLE READ` | `READ COMMITTED` |
|---|---|---|---|
| 1 | `SELECT` simples, antes do `UPDATE` | `DISPONIVEL` | `DISPONIVEL` |
| 2 | `SELECT` simples, **depois** do `COMMIT` de S1 | **`DISPONIVEL`** | **`RESERVADO`** |
| 3 | `SELECT ... FOR UPDATE`, mesma transação | `RESERVADO` | `RESERVADO` |
| 4 | `SELECT` simples, transação nova | `RESERVADO` | `RESERVADO` |

**Leitura.** Em `REPEATABLE READ`, as leituras 2 e 3 são da mesma transação, com
milissegundos de distância, e discordam. O mecanismo por trás disso é o versionamento. A
leitura 2 é servida pelo MVCC a partir da versão antiga guardada no undo log, porque o
read view foi fixado no passo 3 e não se move. A leitura 3 ignora o retrato, porque uma
leitura bloqueante precisa operar sobre o que realmente está lá, e travar uma versão que
já não existe não faria sentido.

Em `READ COMMITTED` a divergência desaparece, porque cada comando pega um retrato novo e a
leitura 2 já vê o `UPDATE` confirmado. A leitura 3 é idêntica nos dois níveis. **A leitura
bloqueante não depende do nível de isolamento**, e é isso que a torna a base segura para
revalidar.

Essa é a razão de a revalidação do procedimento usar `FOR UPDATE` em vez de um `SELECT`
comum. Com `SELECT` comum em `REPEATABLE READ`, uma sessão que esperou o bloqueio releria
`DISPONIVEL`, o valor do seu retrato, concluiria que o assento está livre e autorizaria a
reserva dobrada, reproduzindo o A0 apesar de todo o bloqueio. A camada 2 inteira depende
dessa distinção, e o A1 mostra ela funcionando: lá o valor relido foi `RESERVADO`.

### 6.11 F: o `WHERE`, o índice e o escopo do bloqueio

**Pergunta.** O bloqueio de S1 no 10A alcança o 10B?

S1 bloqueia o 10A de duas formas diferentes e S2 tenta bloquear o **10B**, um assento que
não tem nada a ver com a operação de S1. Rodado nos dois níveis de isolamento.

| Passo | Sessão | Comando |
|---|---|---|
| 1 | S1 | `SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;` (2ª rodada: `READ COMMITTED`) |
| 2 | S2 | `SET SESSION innodb_lock_wait_timeout = 1;` |
| 3 | S1 | `START TRANSACTION;` |
| 4 | S1 | `SELECT id FROM assentos WHERE numero = '10A' FOR UPDATE;` (sem `voo_id`) |
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
| `numero = '10A'` | `type=index`, `key=uq_assento_voo`, `rows=3` | `REPEATABLE READ`: **não** (1205 em 1,047 s)<br>`READ COMMITTED`: **sim** (0,000 s) |
| `voo_id = 1 AND numero = '10A'` | `type=const`, `key=uq_assento_voo`, `rows=1` | **Sim nos dois níveis** (0,000 s) |

**A reserva saiu correta em todos os quatro casos.** Depois de cada cenário, uma chamada a
`sp_reservar_assento(1, 1, '10A')` sobre o banco resetado produziu `status = RESERVADO` e
exatamente **1** reserva confirmada.

**Leitura.** O `WHERE` muda o **escopo do bloqueio** e preserva a correção do resultado.

O InnoDB bloqueia as linhas que precisou **examinar** para avaliar o `WHERE`, e não apenas
a linha que o `WHERE` descreve. A tabela tem `UNIQUE (voo_id, numero)`, e `numero` não é
prefixo à esquerda desse índice, então `WHERE numero = '10A'` não tem acesso direto e vira
varredura do índice inteiro, `type=index` com `rows=3`, travando tudo que passou pelo
caminho, inclusive o 10B e o 10C. Com o par completo, o acesso é `type=const` com
`rows=1`, e a trava fica na única linha pedida.

**O resultado continua correto no cenário ruim**, e isso é importante para não tirar a
conclusão errada. Nenhuma reserva sai dobrada e nenhum assento fica inconsistente: as
quatro camadas da seção 3 continuam valendo, e a verificação acima confirma. O que se
perde é **concorrência**. Reservas de assentos diferentes, que no A3 correram em paralelo
em 0,016 s cada, passam a se bloquear mutuamente. As consequências práticas são três,
todas já medidas em outros experimentos deste documento:

- **mais espera**, porque o concorrente fica parado pelo tempo da transação alheia (B);
- **mais 1205**, porque a espera passa a ter chance real de estourar o limite, e foi o que
  aconteceu aqui em `REPEATABLE READ`, com o limite em 1 s (C);
- **mais deadlock**, porque quanto mais linhas cada transação trava, mais pares de espera
  existem e maior a chance de um deles fechar ciclo (D1).

O efeito é degradação de desempenho e de disponibilidade sob carga. O sintoma no cliente é
um 1205 numa operação que não disputava nada com ninguém, difícil de diagnosticar
justamente porque o dado nunca fica errado.

**A diferença entre os níveis de isolamento.** Em `READ COMMITTED`, S2 conseguiu o 10B
mesmo no cenário sem índice. O InnoDB, nesse nível, **libera as travas das linhas que não
casam com o `WHERE` depois de avaliá-las**: as linhas do 10B e do 10C foram travadas
durante a varredura e destravadas em seguida, sobrando apenas a trava do 10A, que é a linha
que de fato casou. Em `REPEATABLE READ` as travas da varredura são retidas até o fim da
transação, porque é isso que sustenta a garantia de releitura estável do nível.

O mesmo `WHERE` mal escrito custa mais caro em `REPEATABLE READ`, o padrão do MySQL, do que
em `READ COMMITTED`, o padrão do PostgreSQL. Um `WHERE` que parece inofensivo no PostgreSQL
pode serializar o sistema inteiro ao ser portado.

## 7. Os três níveis de isolamento, medidos

O isolamento padrão do MySQL é `REPEATABLE READ`, e o do PostgreSQL é `READ COMMITTED`. Os
Experimentos A0′, E e F foram rodados em mais de um nível, **no MySQL**, para separar o que
é diferença de nível do que é diferença de banco:

| Comportamento | `READ COMMITTED` | `REPEATABLE READ` | `SERIALIZABLE` |
|---|---|---|---|
| `SELECT` simples relendo linha alterada e confirmada por outra sessão (E, leitura 2) | vê o valor **novo** | vê o valor **antigo** | não medido nesta forma; o `SELECT` passa a tomar trava compartilhada |
| `SELECT ... FOR UPDATE` na mesma situação (E, leitura 3) | vê o valor **novo** | vê o valor **novo** | vê o valor **novo** |
| Travas de linhas varridas que não casam com o `WHERE` (F) | **liberadas** após a avaliação | **retidas** até o fim da transação | não medido |
| `SELECT` comum toma trava? (A0′) | não | não | **sim**, promovido a `LOCK IN SHARE MODE` |
| Corrida do A0 sem a `UNIQUE` (A0, A0′) | acontece | acontece | **impedida**, ao custo de 1213 |

O que **não** foi medido: o comportamento do PostgreSQL, porque não há PostgreSQL neste
ambiente. A tabela acima é toda MySQL 8.0.46. O que se pode dizer do PostgreSQL é que o seu
padrão é `READ COMMITTED`, e portanto que um código portado sem ajuste encontra a coluna da
esquerda lá e a do meio aqui.

A consequência de projeto é que a correção do procedimento não pode depender do nível de
isolamento configurado. As quatro camadas da seção 3 funcionam nos três níveis, porque
nenhuma delas pressupõe o comportamento do retrato: a camada 1 serializa, a 2 relê **com
bloqueio**, que dá o mesmo resultado nos três níveis, a 3 revalida no próprio `UPDATE` e a
4 é declarativa. Um procedimento que revalidasse com `SELECT` simples estaria correto em
`READ COMMITTED` por acidente do padrão e errado em `REPEATABLE READ`, e voltaria a estar
errado no PostgreSQL no dia em que alguém subisse o isolamento.

## 8. Respostas às perguntas da seção 20 do enunciado

**1. Por que uma consulta simples não é suficiente para verificar a disponibilidade de um
assento?** Porque o valor lido pode deixar de ser verdadeiro antes de a escrita acontecer.
No A0 as duas sessões executaram `SELECT status` e as duas leram `DISPONIVEL`; a segunda
leitura já estava errada no instante em que foi feita. As duas prosseguiram e o assento foi
confirmado duas vezes, sem erro em nenhum dos doze passos.

**2. Qual é a finalidade do `SELECT ... FOR UPDATE`?** Tomar trava exclusiva sobre a linha
antes de decidir, para que a sessão possa ler o estado atual e escrever sem que ninguém
mude a linha no meio. No procedimento ele tem duas finalidades concretas que o `UPDATE`
condicional sozinho não atende. A primeira é distinguir "o assento não existe" de "o
assento existe e está ocupado": o `SELECT ... FOR UPDATE` sem filtro de status devolve a
linha ocupada e permite responder as duas situações de forma diferente, enquanto um
`UPDATE ... WHERE status = 'DISPONIVEL'` devolve `ROW_COUNT() = 0` nos dois casos. A
segunda é permitir validar outras condições com a linha já travada e antes de qualquer
escrita, como o A1 mostra, onde a recusa vem da revalidação e não da escrita. O valor que o
`FOR UPDATE` relê é a versão confirmada mais recente, o que o E comprova.

**3. Quando o bloqueio é liberado?** No `COMMIT` ou no `ROLLBACK` da transação que o detém.
No B, S1 segurou 1,0 s e 3,0 s, e S2 esperou 1,000 s e 3,000 s, com diferença de 0,000 s
nas duas medições. A espera de quem aguarda também pode terminar antes disso pelo lado
dela, quando o `innodb_lock_wait_timeout` estoura: no C, S2 abortou em 2,109 s com o limite
em 2 s, enquanto S1 ainda mantinha o bloqueio.

**4. O que acontece com a segunda sessão que tenta reservar o mesmo assento?** Ela fica
parada no `SELECT ... FOR UPDATE`, sem erro e sem resposta, até a primeira terminar. No A1
esperou 2,015 s, e no B a espera acompanhou exatamente o tempo de retenção. Ao destravar,
ela relê o status, encontra `RESERVADO` e é recusada com 1644.

**5. Por que revalidar o status depois do bloqueio?** Porque a sessão que esperou começou a
esperar num mundo em que o assento estava livre e acordou noutro. O valor que ela tinha
antes do bloqueio está velho. No A1, a recusa vem exatamente dessa releitura, que devolveu
`RESERVADO`. A revalidação precisa ser feita com `FOR UPDATE`: o E mostra que, em
`REPEATABLE READ`, um `SELECT` comum na mesma transação ainda devolveria `DISPONIVEL`, e a
reserva dobrada seria autorizada.

**6. O que é uma condição de corrida?** É quando o resultado depende da ordem e do
entrelaçamento de operações concorrentes, e uma decisão é tomada sobre um estado que outra
sessão já mudou. O A0 é o caso completo: ler, decidir e escrever em passos separados, com
duas sessões lendo o mesmo `DISPONIVEL`, decidindo as duas que o assento estava livre e
gravando as duas, resultado de duas reservas confirmadas para o mesmo assento sem nenhum
erro.

**7. Qual é a diferença entre bloqueio e MVCC?** Bloqueio faz a sessão esperar, e MVCC faz
a sessão ler uma versão. No B, a leitura bloqueante de S2 ficou 1,000 s e 3,000 s parada
até o `COMMIT` de S1. No E, a leitura sem trava não esperou nada e devolveu `DISPONIVEL`
depois de o `UPDATE` já estar confirmado, servida pela versão antiga do undo log. O MVCC dá
leitura sem espera ao custo de o valor ser do retrato da transação; o bloqueio dá o valor
confirmado mais recente ao custo da espera. Na mesma transação do E, a leitura 2 devolveu
`DISPONIVEL` e a leitura 3, com `FOR UPDATE`, devolveu `RESERVADO`.

**8. Como ocorre um deadlock?** Quando duas transações esperam uma pela outra em ciclo, cada
uma detendo um recurso que a outra pediu. No D1, S1 tomou o `id` 1 e pediu o `id` 2,
enquanto S2 tomou o `id` 2 e pediu o `id` 1. O ciclo fechou no instante em que a segunda
requisição entrou, e o InnoDB o detectou em 0,015 s, sem consultar o tempo de espera. A
transação da vítima foi desfeita inteira.

**9. Por que adquirir os bloqueios na mesma ordem reduz a chance de deadlock?** Porque o
ciclo deixa de ser possível. O D2 é o mesmo cenário do D1, com os mesmos dois assentos e a
mesma contenção, mudando só a ordem: com as duas sessões pedindo em ordem crescente de
`id`, não houve deadlock nenhum, S2 esperou 0,500 s e as duas confirmaram. Em ordem
invertida, o D1 deu 1213 em 0,015 s. Com todas as transações pedindo na mesma ordem, a
espera aponta sempre na mesma direção, e um grafo de espera com direção única não fecha
ciclo. A contenção continua, e o que desaparece é o ciclo.

**10. Qual é a diferença entre `READ COMMITTED`, `REPEATABLE READ` e `SERIALIZABLE`?** Os
três diferem no que uma leitura vê e em quantas travas ela toma, medido na seção 7. Em
`READ COMMITTED` cada comando pega um retrato novo, e no E a segunda leitura já viu
`RESERVADO`; no F as travas das linhas que não casam com o `WHERE` são liberadas após a
avaliação. Em `REPEATABLE READ`, o padrão do MySQL, o retrato é fixado na primeira leitura
e no E a segunda leitura ainda devolveu `DISPONIVEL`; no F as travas da varredura são
retidas até o fim da transação. Em `SERIALIZABLE`, todo `SELECT` comum é promovido a
`LOCK IN SHARE MODE`, e no A0′ isso impediu a corrida do A0 mesmo sem a `UNIQUE`, ao custo
de as duas sessões caírem em deadlock quando tentaram escrever, com 1213 para a vítima. A
adaptação registrada na seção 2 depende dessa diferença: o padrão do MySQL é
`REPEATABLE READ` e o do PostgreSQL é `READ COMMITTED`, então o mesmo código muda de
comportamento ao ser portado sem ajuste.

**11. Por que manter uma restrição `UNIQUE` mesmo havendo validação na aplicação?** Porque
a validação da aplicação só vale para quem passa por ela, e não impede a corrida nem quando
passa. O A0 mostra as duas falhas juntas: sem a `UNIQUE`, duas sessões que fizeram a
verificação correta em SQL confirmaram o mesmo assento. O A2 mostra a restrição agindo
sozinha contra um cliente que não usa o procedimento, não abre transação e não bloqueia
nada, recusando o segundo `INSERT` com 1062. Das quatro camadas da seção 3, a `UNIQUE` é a
única que vale fora do procedimento.

**12. Como tratar deadlock e falha de serialização na aplicação?** O 1213 e o erro de
serialização desfazem a transação inteira, então o tratamento é repetir a transação
completa, do `START TRANSACTION` em diante, com limite de tentativas e espera crescente
entre elas, para não transformar a repetição em nova fonte de contenção. Não faz sentido
repetir apenas o comando que falhou, porque a transação em que ele estava já não existe. O
1205 é diferente: no C, a transação de S2 continuou viva depois do erro e um `SELECT`
seguinte funcionou, o que deixa o cliente decidir entre repetir só o comando, seguir por
outro caminho ou desfazer. Tratar os dois com o mesmo `catch` erra nas duas direções:
repetir só o comando após um 1213 opera numa transação que não existe mais, e refazer tudo
após um 1205 joga fora trabalho válido. A vítima do deadlock é escolhida pelo servidor e
mudou entre execuções do D1, então as duas pontas precisam do mesmo tratamento. Elevar o
isolamento não dispensa esse código: o A0′ mostra a reserva falhando com 1213 em disputa
normal sob `SERIALIZABLE`.

## 9. Conclusões

1. **A corrida é real e silenciosa.** Sem restrição, duas sessões confirmaram o mesmo
   assento sem um único erro (A0). Nenhuma das duas tinha como perceber, porque cada uma,
   isolada, fez tudo certo. É o cenário que só aparece com duas sessões, e nunca em teste
   sequencial.
2. **A restrição declarativa é a única camada que vale sempre.** As três camadas de
   aplicação protegem quem usa o procedimento, e a `UNIQUE (assento_ativo)` protege contra
   quem não usa (A2). Se apenas uma pudesse ser mantida, seria ela.
3. **Leitura bloqueante e leitura simples respondem coisas diferentes, e a diferença é
   silenciosa.** A mesma transação devolveu `DISPONIVEL` e `RESERVADO` com milissegundos de
   distância (E). O código que revalida precisa usar `FOR UPDATE`, e nada no resultado de um
   `SELECT` simples indica que ele está desatualizado. Essa é a única leitura cujo resultado
   se mantém igual nos três níveis de isolamento (seção 7).
4. **Serializar o recurso certo é parte do requisito.** O bloqueio tem de valer para o
   assento disputado: no A3 duas reservas simultâneas de assentos diferentes passaram sem
   espera, o que é o que torna o sistema utilizável.
5. **1205 e 1213 exigem tratamentos diferentes** porque deixam a transação em estados
   diferentes, viva em um caso e desfeita no outro (C, D1).
6. **Deadlock se previne no projeto.** D1 e D2 diferem só pela ordem de aquisição, e essa
   diferença é a presença ou a ausência do 1213. Ordem única elimina o ciclo por construção,
   e o tratamento do erro continua obrigatório, porque a vítima é escolhida pelo servidor e
   mudou entre execuções.
7. **Elevar o isolamento troca o erro que a aplicação precisa tratar.** Sob `SERIALIZABLE` a
   corrida do A0 foi impedida sem a `UNIQUE`, mas as duas sessões caíram em deadlock ao
   escrever, e a vítima recebeu 1213 (A0′). O cliente continua precisando de repetição da
   transação.
8. **`WHERE` sem índice amplia o escopo do bloqueio e preserva a correção.** O resultado
   continua certo, verificado nos quatro cenários do F, e o `FOR UPDATE` trava todas as
   linhas varridas, de modo que reservas independentes começam a se bloquear, aumentando
   espera, risco de 1205 e chance de deadlock. O custo é maior em `REPEATABLE READ`, onde as
   travas de varredura são retidas até o fim da transação.
