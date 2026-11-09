# Aula 29: otimização de consultas com EXPLAIN

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

A atividade pede rodar consultas sobre uma base de 50 mil clientes e 500 mil locações,
ler o plano com `EXPLAIN`, criar índices e verificar pelo plano se eles foram usados ou
ignorados. O banco é o `lab_otimizacao`, separado do `aeroporto`, com o script de carga
do professor sem alteração.

| Arquivo | Conteúdo |
|---|---|
| `otimizacao.sql` | Parte 0 a Parte 4 em ordem, mais os testes extras marcados como `Extra` |
| `saida_execucao.txt` | Saída completa da execução que gerou os números deste documento |
| `README.md` | Tabelas preenchidas e respostas |

## Como executar

No Laragon, abrir o terminal do MySQL e rodar o script inteiro de uma vez:

```bash
mysql -u root -p -t < otimizacao.sql
```

O script apaga e recria o `lab_otimizacao`, então pode ser rodado quantas vezes for
preciso. A carga leva poucos segundos; o teste de escrita do final leva uns 20 segundos.
Não mexe no banco `aeroporto` das outras aulas.

**Ambiente de medição.** MySQL 8.0.46 (Ubuntu), `EXPLAIN` no formato tradicional e
`EXPLAIN ANALYZE` no formato árvore. Os tempos são da segunda execução do script, com o
buffer pool já aquecido; a primeira deu valores na mesma faixa. O Laragon usa MySQL
8.4.3, então tempos e estimativas de `rows` podem variar um pouco. O `type` e o `key`
devem se repetir, com uma ressalva na seletividade, explicada na Parte 2.

## Parte 0: preparação

| Conferência | Resultado |
|---|---|
| `COUNT(*)` de cliente | 50000 |
| `COUNT(*)` de locacao | 500000 |
| `SHOW INDEX FROM locacao` | só `PRIMARY` (id) |

## Parte 1: diagnóstico sem índices

| Consulta | Tabela | `type` | `key` | `rows` | Observações (`Extra`) |
|---|---|---|---|---|---|
| Q1 | locacao | ALL | NULL | 498636 | Using where |
| Q2 | locacao | ALL | NULL | 498636 | NULL |
| Q2 | cliente | eq_ref | PRIMARY | 1 | Using where |

Tempo real da Q1 (`actual time` do `EXPLAIN ANALYZE`): **148 ms**, lendo 500000 linhas
para devolver 10.

Na Q2 o MySQL não começou por `cliente`, como a ordem da tabela do enunciado sugere.
Sem índice em `cpf`, achar o cliente exigiria um full scan de `cliente`, e mesmo assim
não haveria como chegar às locações dele sem varrer `locacao`. O otimizador preferiu
varrer `locacao` uma vez e, para cada linha, buscar o cliente pela chave primária
(`eq_ref`), testando o `cpf` depois. O `EXPLAIN ANALYZE` (extra) mostra o custo disso:
**667 ms**, com 500000 buscas pela `PRIMARY` de `cliente` (`loops=500000`).

**Por que o MySQL não teve alternativa a ler a tabela inteira?** Porque não existia
índice em `locacao.id_cliente` nem em `cliente.cpf`. A única estrutura ordenada era a
`PRIMARY` em `id`, que não ajuda a filtrar por outra coluna. Sem índice, o banco não
tem como saber em que páginas estão as linhas do cliente 4242 e precisa testar a
condição linha a linha (`type = ALL`).

## Parte 2: criando índices e comparando

| Consulta | Tabela | `type` | `key` | `rows` |
|---|---|---|---|---|
| Q1 | locacao | ref | idx_loc_cliente | 10 |
| Q2 | cliente | ref | idx_cli_cpf | 1 |
| Q2 | locacao | ref | idx_loc_cliente | 9 |

Tempo real da Q1 agora: **0,072 ms** (antes 148 ms). A Q2 caiu de 667 ms para
**0,071 ms**. Com os dois índices, a ordem do join inverteu: o MySQL acha o cliente pelo
`cpf` (1 linha) e só então busca as 10 locações dele.

### Seletividade na prática

| Filtro | Parcela real da tabela | `type` | `key` | `rows` estimado |
|---|---|---|---|---|
| `status = 'cancelada'` | 2% (10000 linhas) | ref | idx_loc_status | 18332 |
| `status = 'concluida'` | 74% (370000 linhas) | ref | idx_loc_status | 249318 |

Neste ambiente o MySQL usou o índice nos dois casos, ao contrário do esperado. O
resultado foi conferido com `EXPLAIN ANALYZE`, com o índice e com `IGNORE INDEX`:

| Filtro | Com `idx_loc_status` | Com full scan (`IGNORE INDEX`) |
|---|---|---|
| `cancelada` | 20,7 ms | 166 ms |
| `concluida` | 802 ms | 171 ms |

Para `cancelada` o índice é 8 vezes mais rápido. Para `concluida` ele é 4,7 vezes **mais
lento** que ler a tabela inteira, e mesmo assim o otimizador escolheu o índice.

**O índice existe nos dois casos. Por que o resultado do plano é diferente?** Por causa
da seletividade. Um índice secundário guarda só o valor da coluna e a chave primária;
para cada entrada encontrada, o InnoDB precisa ir à tabela buscar a linha completa
(`SELECT *`), uma leitura fora de ordem por linha. Com 2% da tabela isso compensa. Com
74% são 370 mil idas à tabela, mais caras que ler as 500 mil linhas em sequência, e o
correto seria o full scan (`type = ALL`, `key = NULL`).

O que aconteceu aqui foi um erro de estimativa: o otimizador calculou 249318 linhas
(50%) em vez de 370000 (74%), e com essa conta o índice saiu mais barato (custo 26110
contra 50256 do full scan). O plano é escolhido pela estimativa, não pelo tempo real.
Se no Laragon o `concluida` aparecer como `ALL`, é o comportamento previsto pelo
enunciado; se aparecer como `ref`, é o mesmo erro de estimativa registrado acima.

## Parte 3: índices que o MySQL ignora

| Caso | `type` antes | `type` depois | Por que o índice não era usado? |
|---|---|---|---|
| 3A | ALL (498636 linhas) | range em idx_loc_data (24756 linhas estimadas) | `DATE_FORMAT` transforma a coluna antes da comparação. O índice está ordenado por `data_retirada`, não pelo resultado da função, então o banco precisa calcular a função em todas as linhas. |
| 3B | ALL (50196 linhas) | range em idx_cli_nome (111 linhas) | O índice B-tree é ordenado da esquerda para a direita. Com `%` no início não há prefixo fixo para posicionar a busca na árvore. |
| 3C | ALL (50196 linhas), com `idx_cli_cpf` em `possible_keys` | ref em idx_cli_cpf (1 linha) | Comparando `VARCHAR` com número, o MySQL converte o `cpf` de cada linha para número. Vários textos viram o mesmo número (`'4242'`, `'04242'`, `'00000004242'`), então a ordem do índice não serve. |

Consultas reescritas:

```sql
-- 3A: faixa de datas, sem funcao na coluna
SELECT * FROM locacao
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';

-- 3B: prefixo fixo
SELECT * FROM cliente WHERE nome LIKE 'Cliente 123%';

-- 3C: comparando com texto
SELECT * FROM cliente WHERE cpf = '00000004242';
```

Conferências feitas para garantir que a reescrita não mudou o resultado:

- 3A: as duas versões devolvem 13680 linhas.
- 3B: a reescrita não é equivalente à original e o enunciado não pede que seja.
  `LIKE '%123'` acha os nomes que terminam em 123 (50 clientes); `LIKE 'Cliente 123%'`
  acha os que começam com `Cliente 123` (111 clientes: 123, 1230 a 1239 e 12300 a
  12399). Busca por final de texto não tem como usar esse índice.
- 3C: as duas versões devolvem 1 linha. No texto, o `cpf` precisa vir com os zeros à
  esquerda, como o `LPAD` gravou; `cpf = '4242'` não acharia nada. O `EXPLAIN ANALYZE`
  da versão numérica leu as 50000 linhas em 22,7 ms.

Em 3A o `rows` estimado (24756) é maior que o real (13680), mas o plano já mostra o que
importa: `range` com `Using index condition` em vez de `ALL`.

## Parte 4: índice composto

| Consulta | `type` | `key` | `rows` |
|---|---|---|---|
| (a) `id_cliente = 4242 AND data_retirada >= '2025-01-01'` | range | idx_loc_cli_data | 3 |
| (b) só `data_retirada` em junho de 2025 | range | idx_loc_data | 24756 |

Na consulta (a), o MySQL escolheu **`idx_loc_cli_data`**, mesmo tendo `idx_loc_cliente`
e `idx_loc_data` disponíveis. O composto resolve as duas condições dentro do índice: vai
até `id_cliente = 4242` e, dentro dele, lê só as datas a partir de 2025 (3 linhas, contra
as 10 do cliente que o índice simples traria).

### Desafio

Com `idx_loc_data` invisível, a consulta (b) virou `type = ALL`, `key = NULL`, 498636
linhas. O composto não ajuda. Ele está ordenado primeiro por `id_cliente` e só depois
por `data_retirada`; as datas de junho estão espalhadas dentro de cada um dos 50 mil
clientes, e sem filtro na primeira coluna não há ponto de partida na árvore. É a regra
do prefixo à esquerda: um índice `(a, b)` serve para filtros em `a` ou em `a` e `b`, mas
não só em `b`.

Dois testes extras confirmam:

- Com `FORCE INDEX (idx_loc_cli_data)` o plano continua `ALL`: o MySQL não tem como
  montar um `range` com esse índice para essa condição.
- Pedindo só as colunas do índice (`SELECT id_cliente, data_retirada`), o plano muda
  para `type = index` com `Using index`. Ainda percorre as 498636 entradas, mas lê o
  índice inteiro em vez da tabela, que é menor. É uma varredura completa, não uma busca.

Depois do teste o índice voltou a `VISIBLE`.

## Parte 5: fechamento

**1. Qual consulta teve o maior ganho com o índice e como você percebeu no plano?**
A Q2. Sem índice era `ALL` em `locacao` com 500 mil buscas em `cliente` (667 ms); com
`idx_cli_cpf` e `idx_loc_cliente` virou dois `ref` com 1 e 9 linhas estimadas (0,071 ms),
cerca de 9 mil vezes mais rápido. A Q1 ganhou cerca de 2 mil vezes (148 ms para
0,072 ms). No plano, o sinal foi `type` passando de `ALL` para `ref`, `key` deixando de
ser `NULL` e `rows` caindo de 498636 para 10.

**2. Caso em que existia índice e ele não foi usado, e a razão.**
O 3C: `idx_cli_cpf` aparece em `possible_keys`, mas `key` fica `NULL` e o `type` é `ALL`,
porque comparar o `VARCHAR` com o número 4242 obriga o MySQL a converter o `cpf` de cada
linha. O mesmo vale para o 3A (função na coluna) e para o desafio da Parte 4 (filtro só
na segunda coluna do composto).

**3. Custo dos índices na escrita.**
Cada `INSERT` e cada `DELETE` precisam atualizar todos os índices da tabela, e cada
`UPDATE` atualiza os índices das colunas alteradas. Os índices também ocupam espaço:
no fim da atividade `locacao` tinha 24,5 MB de dados e 35,1 MB de índices. Medido neste
ambiente com 500 mil linhas (extra):

| Operação | Só `PRIMARY` | Com os 4 índices secundários |
|---|---|---|
| `INSERT ... SELECT` de 500 mil linhas | 2,5 s | 8,5 s |
| `UPDATE` de `data_retirada` em todas as linhas | 2,5 s | 9,3 s |

O `UPDATE` mexe em uma coluna que está em dois índices (`idx_loc_data` e
`idx_loc_cli_data`), por isso também ficou mais caro. Índice vale para coluna que aparece
em filtro ou join e tem boa seletividade; índice que ninguém usa só encarece a escrita.

## Fora do enunciado

- Medi o tempo real da Q2 nas Partes 1 e 2, não só da Q1, porque é na Q2 que a mudança
  de plano é maior.
- Na seletividade, comparei com `IGNORE INDEX` porque o plano deste ambiente contrariou
  o esperado e era preciso mostrar com tempo real qual escolha estava certa.
- Na Parte 3, conferi que cada reescrita devolve o mesmo resultado da original (ou
  registrei quando não devolve, no 3B).
- No desafio, testei `FORCE INDEX` e a consulta coberta pelo composto.
- Na Parte 5, medi o custo de escrita e o tamanho dos índices em vez de responder só
  na teoria.

## Checklist do enunciado

- [x] Parte 0: banco `lab_otimizacao` criado, 50000 clientes e 500000 locações, só `PRIMARY`
- [x] Parte 1: `EXPLAIN` de Q1 e Q2, `EXPLAIN ANALYZE` da Q1, tabela e pergunta
- [x] Parte 2: `idx_loc_cliente` e `idx_cli_cpf`, tabela e tempo da Q1 depois
- [x] Parte 2: seletividade com `idx_loc_status`, tabela e pergunta
- [x] Parte 3: 3A, 3B e 3C com reescrita confirmada no `EXPLAIN` e tabela
- [x] Parte 4: índice composto, consultas (a) e (b), índice escolhido
- [x] Desafio da Parte 4: índice invisível e explicação
- [x] Parte 5: três respostas
