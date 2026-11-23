# Aula 33: BI do aeroporto

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

A atividade pede cinco painéis para a direção do aeroporto (destinos mais frequentes,
passageiros por mês, número de voos, companhia mais atuante e um painel livre) a partir
do sistema OLTP: modelo estrela com grão, medidas e dimensões, uma ficha por painel, a
estrutura das cinco consultas, o resumo do ETL, um wireframe e a lista de lacunas do
OLTP.

Além do que o enunciado pede no papel, o modelo foi criado no MySQL num banco separado,
`aeroporto_dw`, carregado a partir do `aeroporto` e consultado de verdade.

| Arquivo | Conteúdo |
|---|---|
| [`modelo_estrela.md`](modelo_estrela.md) | grão, medidas classificadas, dimensões, estrela em Mermaid, resposta sobre uma fato só |
| [`fichas_paineis.md`](fichas_paineis.md) | as cinco fichas no formato do enunciado |
| [`lacunas.md`](lacunas.md) | companhia aérea e outras lacunas do OLTP |
| [`banco/dw.sql`](banco/dw.sql) | cria o `aeroporto_dw` com `dim_tempo`, `dim_rota`, `dim_aeronave` e `fato_voo` |
| [`banco/etl.sql`](banco/etl.sql) | carga do `aeroporto` para o `aeroporto_dw` e conferência de contagens |
| [`banco/consultas_paineis.sql`](banco/consultas_paineis.sql) | as cinco consultas, com `GROUP BY`, `WHERE` e operação OLAP comentados |
| [`wireframe.svg`](wireframe.svg) | wireframe do painel 5 |

## Resumo do ETL

- **Extract:** `voo` (sem soft delete), `rota`, `aeronave` com `modelo_aeronave` e a contagem de `passagem` por voo, todos do banco `aeroporto`.
- **Transform:** data de partida vira `dim_tempo` (ano, mês, nome do mês e dia da semana em português); modelo e fabricante são desnormalizados em `dim_aeronave`; passagens são contadas por voo, com 0 para voo sem passagem; chaves substitutas `sk_*` no lugar dos ids.
- **Load:** `dim_tempo`, `dim_rota` e `dim_aeronave` primeiro, depois `fato_voo`, que só aceita `sk` existentes (FK).

## Wireframe

O enunciado pede o wireframe desenhado à mão. O `wireframe.svg` é a versão digital do
mesmo desenho, com valores ilustrativos no lugar dos resultados do painel 5: a base de
teste tem 12 passagens para 1.383 assentos, e a ocupação real (0,87%) pareceria erro de
cálculo num painel. Para a entrega em aula ele precisa ser refeito à mão.

## Como executar no Laragon

Pré-requisito: o banco `aeroporto` das aulas anteriores (Aula 10 em diante). Os scripts
não alteram o `aeroporto`. No terminal do Laragon, dentro de
`C:\laragon\www\24101166\aula33-bi-aeroporto\banco`:

```bash
mysql -u root -t --default-character-set=utf8mb4 < dw.sql
mysql -u root -t --default-character-set=utf8mb4 < etl.sql
mysql -u root -t --default-character-set=utf8mb4 < consultas_paineis.sql
```

O `dw.sql` apaga e recria o `aeroporto_dw`. O `etl.sql` esvazia e recarrega, então pode
ser rodado de novo depois de qualquer mudança no `aeroporto`. Sem
`--default-character-set=utf8mb4` o terminal do Windows mostra `terça` com o `ç` trocado;
o dado gravado está certo (`HEX` = `746572C3A761`).

## Decisões fora do enunciado

- **Banco `aeroporto_dw` separado.** O DW não altera o OLTP nem as pastas das aulas
  já entregues. O ETL lê do `aeroporto` por nome
  qualificado (`aeroporto.voo`).
- **Uma fato no grão do voo, sem `fato_passagem`.** Atende aos cinco painéis sem
  duplicidade. No grão da passagem, `COUNT(*)` contaria 12 voos e `COUNT(DISTINCT
  id_voo)` contaria 7, porque o voo 8 não tem passagem. A justificativa completa e o
  teste estão em `modelo_estrela.md`.
- **Sem `dim_passageiro`.** Nenhum painel usa atributo do passageiro. Passageiros do
  painel 2 são passageiros transportados (passagens), não pessoas distintas.
- **`rota.origem`, não `aeroporto_origem`.** A Aula 30 fez a troca só no `aeroporto_lab`.
  No `aeroporto` a coluna continua `origem` (`DESCRIBE rota` conferido).
- **Voo com `deleted_at` não entra.** O soft delete da Aula 22 marca voo excluído; um
  voo excluído não deve aparecer nos painéis. Hoje nenhum voo está excluído.
- **`qtd_passageiros` contada em `passagem`.** Não usa o contador
  `voo.passagens_vendidas` da trigger da Aula 15, para a fato depender do registro de
  origem. Os dois dão 12 hoje.
- **`capacidade_assentos` repetida na fato.** Deixa a ocupação como SUM/SUM só sobre a
  fato, sem depender de a dimensão não ter mudado.
- **`sk_tempo` no formato AAAAMMDD.** Chave substituta inteira, legível e já ordenada.
  As demais `sk` são `AUTO_INCREMENT`.
- **Companhia como coluna `NULL` em `dim_aeronave`.** A consulta do painel 4 roda hoje
  e devolve `(sem dado)`; quando o OLTP tiver a companhia, só o ETL muda.
- **Painel 5: taxa de ocupação por modelo de aeronave.**

## Teste

MySQL 8.4.3 do Laragon, `root` sem senha, banco `aeroporto` no estado atual do meu
Laragon. Saídas copiadas da execução dos três scripts.

### Conferência do ETL contra o OLTP

Saída do final do `etl.sql`:

```
+-------------------------+------+------+
| medida                  | oltp | dw   |
+-------------------------+------+------+
| voos                    |    8 |    8 |
| passageiros (passagens) |   12 |   12 |
| rotas                   |    7 |    7 |
| aeronaves               |    7 |    7 |
+-------------------------+------+------+
```

| Teste | Resultado |
|---|---|
| `dw.sql` | 4 tabelas: `dim_aeronave`, `dim_rota`, `dim_tempo`, `fato_voo` |
| `SELECT COUNT(*) FROM aeroporto.voo` x `SUM(qtd_voos)` da fato | 8 x 8 |
| `SELECT COUNT(*) FROM aeroporto.passagem` x `SUM(qtd_passageiros)` | 12 x 12 |
| `SUM(passagens_vendidas)` de `aeroporto.voo` | 12, igual à fato |
| `etl.sql` rodado de novo | mesmas contagens; `fato_voo` com 8 linhas, `dim_tempo` com 2 |
| Voo 8 (sem passagem) na fato | presente, `qtd_passageiros` 0 |
| `INSERT` na fato com `sk_tempo` 20991231 inexistente | erro 1452 em `fk_fato_voo_tempo` |
| `dim_tempo` | `20260901 setembro terça`, `20260902 setembro quarta` |
| No OLTP: `COUNT(*)` e `COUNT(DISTINCT id_voo)` de `voo JOIN passagem` | 12 e 7 (por isso a fato é no grão do voo) |

### Saída das consultas

Painel 1: destinos mais frequentes. Há 7 destinos; `LIMIT 5` corta `SSA`, empatado com 1
voo (desempate por nome).

```
+---------+------+
| destino | voos |
+---------+------+
| BSB     |    3 |
| CNF     |    1 |
| GIG     |    1 |
| GRU     |    1 |
| REC     |    1 |
+---------+------+
```

Painel 2: passageiros por mês. Um ponto só porque a base tem voos apenas em setembro de
2026 (lacuna de dados, não de consulta).

```
+------+-----+----------+-------------+
| ano  | mes | nome_mes | passageiros |
+------+-----+----------+-------------+
| 2026 |   9 | setembro |          12 |
+------+-----+----------+-------------+
```

Painel 3: número de voos, total e drill down por status.

```
+------+
| voos |
+------+
|    8 |
+------+
+------------+------+
| status     | voos |
+------------+------+
| Embarque   |    3 |
| Confirmado |    3 |
| Aguardando |    2 |
+------------+------+
```

Painel 4: companhia mais atuante. Sem o dado no OLTP, todos os voos caem em `(sem dado)`.

```
+------------+------+------------------+
| companhia  | voos | participacao_pct |
+------------+------+------------------+
| (sem dado) |    8 |            100.0 |
+------------+------+------------------+
```

Painel 5: ocupação por modelo. O `737-800` (1 passageiro em 189 lugares, 0,53%) é o
sexto e fica fora do `LIMIT 5`. A ocupação geral é 12 / 1383 = 0,87%.

```
+-----------+------------+------+-------------+----------+--------------+
| modelo    | fabricante | voos | passageiros | assentos | ocupacao_pct |
+-----------+------------+------+-------------+----------+--------------+
| E195-E2   | Embraer    |    1 |           2 |      136 |         1.47 |
| A320neo   | Airbus     |    2 |           4 |      360 |         1.11 |
| E190      | Embraer    |    1 |           1 |      106 |         0.94 |
| A321neo   | Airbus     |    1 |           2 |      220 |         0.91 |
| 737 MAX 8 | Boeing     |    2 |           2 |      372 |         0.54 |
+-----------+------------+------+-------------+----------+--------------+
```

## Checklist do enunciado

- [x] O grão da fato está escrito em uma frase.
- [x] A dimensão tempo permite ver o painel por mês (`ano`, `mes`, `nome_mes`).
- [x] Toda consulta parte da fato e usa só as dimensões necessárias.
- [x] Todo atributo do `SELECT` sem agregação está no `GROUP BY`.
- [x] Rankings usam `ORDER BY ... DESC` e `LIMIT` (painéis 1, 4 e 5).
- [x] Contagem de voos e de passageiros foi pensada para não contar em duplicidade (grão do voo, teste acima).
- [x] O ETL carrega dimensões antes da fato.

Entregáveis:

- [x] Modelo estrela com grão, medidas e dimensões
- [x] Cinco fichas de painel
- [x] Estrutura das cinco consultas
- [x] Resumo do ETL e wireframe de um painel (digital; refazer à mão para a aula)
- [x] Lista de lacunas do modelo OLTP
