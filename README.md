# Banco de Dados — IDP

Marcello Azevedo Pinheiro Siqueira
Matrícula 24101166

Entregas da disciplina. A numeração das pastas segue a numeração do repositório de
materiais do professor.

| Aula | Atividade | Entrega |
| --- | --- | --- |
| 02 | Conceito de dado e informação: sistema de aeroporto | [`atividade-01-aeroporto/`](atividade-01-aeroporto/) |
| 03 | Relacionamento de entidades utilizando arquivos | [`aula03-relacionamento-arquivos/`](aula03-relacionamento-arquivos/) |
| 04 | Simulando um SGBD sobre arquivos de texto | [`aula04-sgbd-arquivo/`](aula04-sgbd-arquivo/) |
| 05 | Modelagem de dados: sistema de aeroporto | [`aula05-modelagem-dados/`](aula05-modelagem-dados/) |
| 06 | Dicionário de dados do sistema de aeroporto | [`aula06-dicionario-dados/`](aula06-dicionario-dados/) |
| 08 | Criação do banco de dados no MySQL | [`aula08-criacao-banco/`](aula08-criacao-banco/) |
| 09 | Normalização do banco de dados | [`aula09-normalizacao/`](aula09-normalizacao/) |
| 10 | Restrições de integridade | [`aula10-integridade/`](aula10-integridade/) |
| 14 | Views e índices | [`aula14-views-indices/`](aula14-views-indices/) |
| 15 | Triggers | [`aula15-triggers/`](aula15-triggers/) |
| 16 | Locking, deadlocks e MVCC | [`aula16-concorrencia/`](aula16-concorrencia/) |

O nome `atividade-01-aeroporto` foi mantido porque o enunciado da Aula 02 pedia
explicitamente esse nome.

## Aula 02 — Conceito de dado e informação

Levantamento dos dados que um sistema de gerenciamento de aeroporto precisa armazenar e
das informações que ele deve fornecer a partir deles. Entrega em Markdown, sem código.

## Aula 03 — Relacionamento de entidades

Sistema acadêmico em Python puro, sem SGBD, relacionando `alunos.txt` e `notas.txt` para
responder consultas do tipo "qual nota o aluno X tirou na disciplina Y". O `ID_ALUNO` das
notas funciona como chave estrangeira feita à mão.

```bash
cd aula03-relacionamento-arquivos
python aula03.py
```

Os arquivos de dados são gerados na execução e estão no `.gitignore`.

## Aula 04 — Simulando um SGBD

Três operações de consulta implementadas diretamente sobre arquivo texto, usando o painel
de voos fornecido pelo professor:

- Full table scan, equivalente a `SELECT *`
- Busca por chave primária com early exit, equivalente a `WHERE ID = X`
- Filtro e projeção, equivalente a `SELECT col1, col2 WHERE condição`

Inclui um benchmark comparando o scan sequencial com um índice hash de offsets em duas
escalas, e as respostas das questões de reflexão sobre desempenho, indexação e
concorrência.

```bash
cd aula04-sgbd-arquivo
python sgbd.py    # menu interativo
python demo.py    # todas as consultas de uma vez
```

## Aula 05 — Modelagem de dados

Modelo de dados de um sistema de aeroporto a partir das entidades PASSAGEIRO, VOO e
AERONAVE: atributos, chaves, cardinalidades, resolução do relacionamento N:N por tabela
associativa, modelo lógico e diagrama.

Entregue em PDF e em Markdown. O DDL do apêndice foi executado e testado contra as
violações que o documento afirma que o banco recusa.

## Aula 06 — Dicionário de dados

Documentação técnica do banco `aeroporto` sobre o modelo de dicionário fornecido
pelo professor: ficha de cada uma das quatro tabelas com tipo, tamanho,
obrigatoriedade, chave, default, domínio e exemplo de cada campo, mais os
relacionamentos, 9 regras de negócio, os domínios controlados e os 11 índices.

Entregue em `.docx`, formato do modelo original.

## Aula 08 — Criação do banco de dados

Implementação em MySQL do modelo da Aula 05: banco `aeroporto` com as tabelas
`aeronave`, `passageiro`, `voo` e a associativa `passagem`, mais os dados de
exemplo e as consultas.

Inclui um script de verificação que roda 10 comandos que devem ser recusados pelo
banco e 3 que devem passar, provando que as regras de negócio do modelo estão nas
constraints e não apenas na aplicação.

```bash
mysql -u root -p < aeroporto.sql
mysql -u root -p --force aeroporto < testes_constraints.sql
```

## Aula 09 — Normalização do banco de dados

Análise de normalização do banco `aeroporto` partindo do SQL da Aula 08, percorrendo da
1FN à 5FN. Duas violações com dependência funcional identificada e anomalia concreta:

- **2FN em `voo`** — `numero_voo` determina origem e destino, e é apenas parte da chave
  candidata `(numero_voo, data_hora_partida)`. Extraída a tabela `rota`.
- **3FN em `aeronave`** — `modelo` determina `fabricante`, dependência transitiva.
  Extraída a tabela `modelo_aeronave`.

As outras três formas normais são verificadas e mantidas sem alteração, com justificativa,
como o enunciado pede. Quatro dependências plausíveis foram examinadas e descartadas por
análise do domínio, entre elas a capacidade de assentos, que permanece em `aeronave`
porque a mesma aeronave pode ter configurações de cabine diferentes.

Quatro tabelas passam a seis. O SQL normalizado foi executado em MySQL 8.0.46 e as cinco
consultas da Aula 08 retornam resultado idêntico nos dois esquemas.

```bash
mysql -u root -p < sql_aula_8.sql        # banco da Aula 08, preservado
mysql -u root -p < sql_normalizado.sql   # banco normalizado
```

## Aula 10 — Restrições de integridade

Regras de integridade do banco `aeroporto` sobre o esquema normalizado da Aula 09,
organizadas nas sete categorias do enunciado: entidade, referencial, domínio, chave,
unicidade, obrigatoriedade e regras de negócio. Cada restrição tem justificativa do
problema que evita, incluindo o que `ON DELETE CASCADE` destruiria em cada uma das cinco
chaves estrangeiras.

Quatro regras novas em relação à Aula 09: chegada prevista posterior à partida, formato
IATA em origem e destino, e o limite de passagens vendidas pela capacidade da aeronave —
esta última por trigger, por ser a única forma de expressá-la no SGBD, já que o `CHECK` do
MySQL não aceita subconsulta nem agregação.

Inclui uma seção sobre as regras **deliberadamente não implementadas**, com o motivo de
cada uma: `UNIQUE` em e-mail bloquearia família que compartilha contato, `NOT NULL` em
portão impediria cadastrar voo programado, e a detecção de voos simultâneos do mesmo
passageiro bloquearia conexão legítima.

44 testes executados em MySQL 8.0.46: 34 comandos que devem ser recusados, com o código de
erro conferido na saída do servidor, e 10 contraprovas mostrando que nenhuma restrição
bloqueia operação válida. As recusas cobrem as três operações que alteram dados — inserção,
exclusão e atualização —, porque restrição que vale ao inserir e não vale ao atualizar é um
buraco clássico, e é a razão de a trigger de capacidade ter uma segunda versão.

```bash
mysql -u root -p < sql_integridade.sql
```

## Aula 14 — Views e índices

Três views sobre o banco da Aula 10:

- `vw_painel_voos`, com `JOIN` entre voo, rota, aeronave e modelo, declarada com
  `ALGORITHM = TEMPTABLE` para ser somente leitura;
- `vw_ocupacao_voo`, com agregação e `LEFT JOIN`, para ocupação por voo;
- `vw_passagens_pendentes_checkin`, simples e atualizável, com `WITH CHECK OPTION`.

O índice `idx_voo_status` foi medido com `performance_schema` em quatro cenários: a tabela
real e três variações de uma cópia com 200 mil linhas. O ganho dependeu da seletividade: a
consulta ficou cerca de 13 vezes mais rápida para um status raro e mais lenta para os
status comuns. O `UPDATE` de status ficou cerca de 42% mais caro. A conclusão é não manter o
índice no volume atual do projeto.

```bash
mysql -u root -p < views_indices.sql
```

## Aula 15 — Triggers

Três desafios de trigger sobre o banco da Aula 10, somando oito triggers no banco:

- **Validação de regra de negócio com `BEFORE UPDATE`.** A regra de capacidade da Aula 10
  só cobria a venda de passagem. Faltavam as duas outras portas para o mesmo estado
  inválido: trocar o voo por uma aeronave menor e reduzir a capacidade de uma aeronave já
  em operação. A segunda compara com o voo **mais cheio** da aeronave, não com um voo
  qualquer.
- **Auditoria com `AFTER UPDATE`.** Log de alteração de `status` e `portao` em `voo`, uma
  linha por campo alterado, com valor anterior, posterior, data e usuário. A comparação usa
  `<=>` e não `<>`, porque `portao` aceita `NULL` e `NULL <> NULL` é desconhecido — com
  `<>` a liberação e a primeira atribuição de portão não entrariam no log.
- **Sincronização com `AFTER INSERT`, `AFTER DELETE` e `AFTER UPDATE`.** Coluna derivada
  `voo.passagens_vendidas` mantida pelo SGBD, incluindo o remanejamento de passagem entre
  voos, que precisa decrementar um voo e incrementar outro no mesmo comando.

A cadeia de triggers é o ponto delicado: o `AFTER INSERT` em `passagem` atualiza `voo`, o
que dispara o `BEFORE UPDATE` de `voo`. As guardas `IF` são o que evita tanto o erro 1442
quanto o disparo indevido das validações.

A bateria de testes cobre os três desafios com recusa por `SIGNAL` (1644), aceitação do
caso válido e os casos-limite de "exceder" contra "atingir". O contador derivado é
conferido contra a contagem real voo a voo: 8 voos, 0 divergências.

Um defeito foi encontrado e corrigido na execução: o `MESSAGE_TEXT` do `SIGNAL` aceita no
máximo 128 caracteres, e uma das mensagens tinha 131. O MySQL não trunca — aborta com
1648, e a recusa chega ao cliente sem explicação e com o código trocado. As duas mensagens
foram reescritas para caber com folga (64 e 58 caracteres com os ids do banco de exemplo),
e o `LEFT(..., 128)` ficou apenas como guarda para ids longos: não é ele que faz as
mensagens caberem.

```bash
mysql -u root -p < ../aula10-integridade/sql_integridade.sql
mysql -u root -p --force < triggers.sql
```

## Aula 16 — Locking, deadlocks e MVCC

Controle de concorrência em reserva de assentos, no banco separado
`aeroporto_concorrencia`: o esquema sugerido pelo professor, adaptado de PostgreSQL para
MySQL. O banco é outro porque no modelo individual o assento é uma coluna de texto dentro
de `passagem`, e não existe linha de assento para bloquear.

O `sp_reservar_assento` defende a reserva em quatro camadas: `SELECT ... FOR UPDATE`,
revalidação após o bloqueio, `UPDATE` condicional com `ROW_COUNT()` e a `UNIQUE` de uma
coluna gerada — substituta do índice único parcial do PostgreSQL, que o MySQL não tem.
Só a última vale para um cliente que ignore o procedimento.

Onze experimentos, cada um com **duas sessões simultâneas** e o passo a passo publicado
comando por comando, para ser reproduzido à mão em duas abas do MySQL Workbench:

| # | Cenário | Resultado |
|---|---|---|
| A0 | Corrida sem restrição | **Duas reservas confirmadas para o mesmo assento**, sem erro em nenhum passo |
| A1 | Disputa pelo procedimento | A perdedora esperou 2,015 s e foi recusada na revalidação (1644) |
| A2 | Só a `UNIQUE`, sem procedimento | Duplicidade barrada (1062); cancelar a reserva reabriu a vaga |
| A3 | Assentos diferentes, ao mesmo tempo | As duas com sucesso e **sem espera** (0,016 s cada) |
| B | Duração da espera | 1,000 s e 3,000 s para retenções de 1,0 s e 3,0 s (+0,000 s) |
| C | Espera esgotada | 1205 em 2,109 s com limite de 2 s, e a transação **sobreviveu** |
| D1 | Deadlock, ordem invertida | 1213 em 0,015 s, transação da vítima desfeita **inteira** |
| D2 | Ordem crescente de `id` | **Nenhum deadlock**: S2 esperou 0,500 s e as duas confirmaram |
| E | MVCC em `REPEATABLE READ` | Mesma transação: `SELECT` simples `DISPONIVEL`, `FOR UPDATE` `RESERVADO` |
| E′ | MVCC em `READ COMMITTED` | O `SELECT` simples já devolveu `RESERVADO` |
| F | Escopo do bloqueio | `WHERE` sem índice travou 3 linhas em vez de 1; em `READ COMMITTED` as travas que não casam são liberadas |

O A0 abre a série de propósito: sem a `UNIQUE`, as duas sessões leem `DISPONIVEL` com
`SELECT` comum e as duas confirmam o mesmo assento, **sem um único erro**. É o desfecho
contra o qual as quatro camadas existem, e sem ele o teste que mostra a `UNIQUE` recusando
não prova que ela é necessária.

O D1 e o D2 são o mesmo cenário com a ordem de aquisição trocada, e são a prova da
resposta sobre prevenção de deadlock: em ordem invertida há 1213 imediato; em ordem
crescente de `id` o ciclo não pode se formar e as duas transações terminam.

O F trata de **escopo de bloqueio**, não de correção. Sem índice utilizável o `FOR UPDATE`
trava todas as linhas varridas, mas a reserva continua saindo certa — verificado nos
quatro cenários. O que se degrada é concorrência: reservas de assentos independentes
passam a se bloquear, aumentando espera, risco de 1205 e chance de deadlock. O custo é
maior em `REPEATABLE READ`, onde as travas da varredura são retidas até o fim da
transação; em `READ COMMITTED` o InnoDB libera as travas das linhas que não casam com o
`WHERE` depois de avaliá-las.

```bash
mysql -u root -p < concorrencia.sql
```

## Ambiente

Python 3.12, sem dependências externas.
MySQL 8.x para as Aulas 08, 09, 10, 14, 15 e 16, com o script da Aula 08 testado também
em MariaDB 10.11. A Aula 14 foi medida em MySQL 8.0.46 e depende de
performance_schema ligado. As Aulas 15 e 16 foram executadas em MySQL 8.0.46 em contêiner
Docker (`mysql:8.0`); a Aula 16 exige InnoDB, e nada nela funciona sob MyISAM.
