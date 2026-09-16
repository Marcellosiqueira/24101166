# Aula 14 — Views e índices

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Aplicação da metodologia de views e índices ao banco `aeroporto`, no estado deixado pela
Aula 10: seis tabelas, as restrições de integridade e a trigger de capacidade.

| Arquivo | Conteúdo |
|---|---|
| `views_indices.sql` | As três views, o índice na tabela real e o laboratório de volume |
| `views_indices.md` | Diagnóstico, formulários, medições e conclusões |

```bash
mysql -u root -p < ../aula10-integridade/sql_integridade.sql
mysql -u root -p < views_indices.sql
```

O `views_indices.sql` foi executado duas vezes seguidas sobre o banco recém-criado, e as
duas execuções terminaram sem erro. A única diferença entre as duas saídas é uma estimativa
de linhas do `EXPLAIN` (seção 3.8).

**Ambiente de medição.** MySQL 8.0.46 em contêiner Docker (`mysql:8.0`) no Windows 11,
`performance_schema = ON`, buffer pool de 128 MB. **Todo número deste documento veio de
execução nesse ambiente.** O que não foi medido está marcado como não medido.

---

## 1. Etapa 1 — Diagnóstico

### 1.1 Consultas que o projeto já usa

As cinco primeiras estão no `aula08-criacao-banco/aeroporto.sql` e foram adaptadas ao
esquema de seis tabelas em `aula09-normalizacao/sql_normalizado.sql`, seção 6. A sexta é o
filtro por status do painel de voos da Aula 04 (`aula04-sgbd-arquivo/demo.py`, linha 33),
que ainda não tinha sido levado para o banco.

| # | Consulta | WHERE | JOIN | ORDER BY / GROUP BY |
|---|---|---|---|---|
| C1 | Painel de voos | — | `voo.id_rota = rota.id_rota`; `voo.id_aeronave = aeronave.id_aeronave`; `aeronave.id_modelo = modelo_aeronave.id_modelo` | `ORDER BY voo.data_hora_partida` |
| C2 | Lista de embarque de um voo | `rota.numero_voo = '305'`; `DATE(voo.data_hora_partida) = '2026-09-01'` | `passagem.id_passageiro = passageiro.id_passageiro`; `passagem.id_voo = voo.id_voo`; `voo.id_rota = rota.id_rota` | `ORDER BY passagem.assento` |
| C3 | Ocupação por voo | — | as três de C1, mais `LEFT JOIN passagem ON passagem.id_voo = voo.id_voo` | `GROUP BY voo.id_voo, …`; `ORDER BY ocupacao_pct` |
| C4 | Passageiros com mais de um voo | `HAVING COUNT(…) > 1` | `passagem.id_passageiro = passageiro.id_passageiro` | `GROUP BY passageiro.id_passageiro, nome`; `ORDER BY total_voos, nome` |
| C5 | Próximos voos a partir de um horário | `voo.data_hora_partida >= '2026-09-01 12:00:00'` | `voo.id_rota = rota.id_rota` | `ORDER BY voo.data_hora_partida` |
| C6 | Voos em um status | `voo.status = 'Embarque'` | — | — |

Além das leituras, o projeto **escreve** em `voo.status` como parte da operação normal. A
Aula 10 define que cancelar um voo é mudar o `status` para `'Cancelado'`, e não apagar o
registro (`integridade.md`, seção 2 e contraprova C09). O ciclo de vida de um voo passa por
`Aguardando`, `Confirmado` e `Embarque`, e cada passagem é um `UPDATE` nessa coluna. Isso
pesa na decisão da Etapa 3.

### 1.2 Índices que já existem

Conferido em `information_schema.statistics` no banco recém-criado:

| Tabela | Índice | Colunas | Origem |
|---|---|---|---|
| todas as seis | `PRIMARY` | a chave substituta | `PRIMARY KEY` |
| `aeronave` | `fk_aeronave_modelo` | `id_modelo` | criado automaticamente pela FK |
| `voo` | `fk_voo_aeronave` | `id_aeronave` | criado automaticamente pela FK |
| `aeronave` | `uq_aeronave_prefixo` | `prefixo` | `UNIQUE` |
| `modelo_aeronave` | `uq_modelo_aeronave_modelo` | `modelo` | `UNIQUE` |
| `passageiro` | `uq_passageiro_cpf` | `cpf` | `UNIQUE` |
| `rota` | `uq_rota_numero_voo` | `numero_voo` | `UNIQUE` |
| `voo` | `uq_voo_rota_partida` | `id_rota, data_hora_partida` | `UNIQUE` |
| `passagem` | `uq_passagem_localizador` | `localizador` | `UNIQUE` |
| `passagem` | `uq_passagem_passageiro_voo` | `id_passageiro, id_voo` | `UNIQUE` |
| `passagem` | `uq_passagem_voo_assento` | `id_voo, assento` | `UNIQUE` |

Os únicos índices **não únicos** são os dois criados pelas FKs. As outras três chaves
estrangeiras (`fk_voo_rota`, `fk_passagem_passageiro`, `fk_passagem_voo`) não ganharam
índice próprio porque a coluna já é a primeira de um `UNIQUE` composto, e o MySQL reaproveita
esse índice.

### 1.3 O que o diagnóstico aponta

**Os JOINs já estão cobertos.** Todo `JOIN` de C1 a C5 usa uma chave primária de um lado e,
do outro, uma coluna que é o prefixo de algum índice. Não há índice a acrescentar para
junção.

**C6 é a única consulta com filtro sem índice que a sirva.** `voo.status` não aparece em
nenhum índice. É o candidato da Etapa 3, `idx_voo_status`.

Dois pontos entram como observação, fora do escopo desta entrega:

- Em C2, `DATE(voo.data_hora_partida) = …` aplica função sobre a coluna, o que impede o uso
  de índice nela. Escrito como faixa (`>= '2026-09-01' AND < '2026-09-02'`), o filtro poderia
  aproveitar `uq_voo_rota_partida`, cuja segunda coluna é justamente a data. Não foi testado
  aqui.
- C5 filtra e C1 ordena por `data_hora_partida`, e nenhum índice começa por essa coluna. É o
  próximo candidato natural. Não foi testado aqui.

---

## 2. Etapa 2 — Views

### 2.1 `vw_painel_voos`

| Campo | Preenchimento |
|---|---|
| **Nome** | `vw_painel_voos` |
| **Tabelas de origem** | `voo`, `rota`, `aeronave`, `modelo_aeronave` |
| **Tipo** | View com `JOIN` (três junções internas) |
| **Atualizável?** | **Não**, por decisão: declarada com `ALGORITHM = TEMPTABLE`. Ver abaixo |
| **Problema que resolve** | A normalização da Aula 09 espalhou o painel por quatro tabelas. A view devolve o painel numa leitura só, sem repetir três `JOIN` em cada consulta |
| **Esboço do SELECT** | `SELECT r.numero_voo, r.origem, r.destino, v.data_hora_partida, v.portao, v.status, a.prefixo, m.modelo FROM voo v JOIN rota r … JOIN aeronave a … JOIN modelo_aeronave m …` |

**Por que não é atualizável — e por que isso precisou ser uma escolha.** A resposta
intuitiva seria "porque tem `JOIN`", mas ela não vale para o MySQL. Antes de escrever a view,
a mesma consulta foi criada com o algoritmo padrão, numa view de sonda, e testada em
transações desfeitas com `ROLLBACK`:

| Operação na view com algoritmo padrão | Resultado no MySQL 8.0.46 |
|---|---|
| `information_schema.views.IS_UPDATABLE` | **`YES`** |
| `UPDATE … SET portao = '99'` num voo | **aceito**, 1 linha alterada em `voo` |
| `INSERT … (numero_voo, origem, destino)` | **aceito**, criou uma linha em `rota` |
| `UPDATE … SET modelo = '…'` pedido para **um** voo, o 305 de 01/09 | **aceito**, e renomeou o modelo **dos voos 305 e 630**, que usam a mesma aeronave |
| `UPDATE` com colunas de duas tabelas | `ERROR 1393 (HY000): Can not modify more than one base table through a join view` |
| `DELETE` | `ERROR 1395 (HY000): Can not delete from join view` |

O MySQL aceita `UPDATE` e `INSERT` numa view com `INNER JOIN` desde que o comando atinja uma
única tabela. A quarta linha mostra o risco: quem olha uma linha do painel e corrige o modelo
daquele voo altera, sem perceber, `modelo_aeronave` — e com ela todos os voos da mesma
aeronave. **Um painel é leitura, e a escrita pertence às tabelas de origem.**

`ALGORITHM = TEMPTABLE` faz o MySQL materializar o resultado, e uma view materializada não
é atualizável por definição:

```
UPDATE vw_painel_voos SET portao = '99' WHERE numero_voo = '420';
ERROR 1288 (HY000): The target table vw_painel_voos of the UPDATE is not updatable

DELETE FROM vw_painel_voos WHERE numero_voo = '420';
ERROR 1288 (HY000): The target table vw_painel_voos of the DELETE is not updatable
```

**Custo verificado.** A materialização poderia impedir o uso de índice num filtro externo.
Não impede: o `EXPLAIN` mostra o MySQL 8 empurrando o `WHERE` para dentro da view, e com
`idx_voo_status` criado o filtro já usa o índice.

```
EXPLAIN FORMAT=TREE SELECT * FROM vw_painel_voos WHERE status = 'Embarque';

-> Table scan on vw_painel_voos  (cost=5.1..6.79 rows=3)
    -> Materialize  (cost=4.25..4.25 rows=3)
        -> Nested loop inner join  (cost=3.95 rows=3)
            ...
                    -> Index lookup on v using idx_voo_status (status='Embarque')
```

### 2.2 `vw_ocupacao_voo`

| Campo | Preenchimento |
|---|---|
| **Nome** | `vw_ocupacao_voo` |
| **Tabelas de origem** | `voo`, `rota`, `aeronave`, `passagem` |
| **Tipo** | View com agregação (`COUNT`, `GROUP BY`) e `LEFT JOIN` |
| **Atualizável?** | **Não.** Uma linha da view resume várias linhas de `passagem`; não existe linha de tabela à qual um `UPDATE` corresponda. Confirmado: `ERROR 1288 (HY000): The target table vw_ocupacao_voo of the UPDATE is not updatable` |
| **Problema que resolve** | Ocupação de cada voo sem reescrever a agregação: passagens vendidas, capacidade, assentos livres e percentual |
| **Esboço do SELECT** | `SELECT v.id_voo, r.numero_voo, …, COUNT(pg.id_passagem) AS passagens_vendidas, a.capacidade_assentos - COUNT(pg.id_passagem) AS assentos_livres, ROUND(100 * COUNT(pg.id_passagem) / NULLIF(a.capacidade_assentos, 0), 1) AS ocupacao_pct FROM voo v JOIN rota r … JOIN aeronave a … LEFT JOIN passagem pg … GROUP BY …` |

**`LEFT JOIN` e `COUNT(pg.id_passagem)`.** Com `JOIN` simples, um voo sem passagem vendida
some do resultado. Com `LEFT JOIN`, ele aparece com uma linha de colunas nulas vindas de
`passagem`, e `COUNT(pg.id_passagem)` conta essa linha como zero — `COUNT(*)` contaria um.
Nos dados reais o caso existe: **o voo 305 de 02/09 não tem nenhuma passagem** e aparece na
view com `passagens_vendidas = 0` e `ocupacao_pct = 0.0`.

**Divisão por zero.** `ck_aeronave_capacidade` já impede capacidade zero, então a divisão
não acontece com os dados atuais. O `NULLIF(a.capacidade_assentos, 0)` fica mesmo assim: a
view não deve depender de uma restrição de outra tabela para funcionar. Se a regra for
afrouxada, o percentual vira `NULL` em vez de erro.

### 2.3 `vw_passagens_pendentes_checkin`

| Campo | Preenchimento |
|---|---|
| **Nome** | `vw_passagens_pendentes_checkin` |
| **Tabelas de origem** | `passagem` |
| **Tipo** | View simples, com filtro e `WITH CHECK OPTION` |
| **Atualizável?** | **Sim.** Uma tabela, sem agregação, sem `DISTINCT`, com a chave primária `id_passagem` no `SELECT` e todas as colunas como referência direta. O dicionário registra `IS_UPDATABLE = YES` e `CHECK_OPTION = CASCADED` |
| **Problema que resolve** | Lista de passagens sem check-in, para o balcão acompanhar e corrigir, sem que uma correção feita pela view tire a passagem da lista por engano |
| **Esboço do SELECT** | `SELECT id_passagem, id_passageiro, id_voo, assento, localizador, classe, checkin_realizado FROM passagem WHERE checkin_realizado = FALSE WITH CHECK OPTION` |

**O que a cláusula faz**, executado em transação com `ROLLBACK`:

```sql
-- Passa: a passagem continua pendente depois da alteração.
UPDATE vw_passagens_pendentes_checkin SET assento = '01C' WHERE id_passagem = 3;
-- 1 linha afetada

-- Bloqueado: a linha sairia do filtro da view.
UPDATE vw_passagens_pendentes_checkin SET checkin_realizado = TRUE WHERE id_passagem = 3;
-- ERROR 1369 (HY000): CHECK OPTION failed 'aeroporto.vw_passagens_pendentes_checkin'
```

Na view de sonda criada antes desta, um `INSERT` de passagem já com check-in foi recusado com
o mesmo erro 1369.

**Consequência de projeto.** O check-in não se faz por esta view — ele é justamente a
operação que tira a passagem do filtro. A view serve para listar e corrigir passagens
pendentes; marcar o check-in é escrita direta em `passagem`. Isso é intencional: sem a
cláusula, um `UPDATE` pela view faria a linha desaparecer da própria view, sem aviso.

### 2.4 Conteúdo das três views

Saída de `SELECT *` após a execução do `views_indices.sql`. Nenhuma volta vazia.

`vw_painel_voos` — 8 linhas:

```
numero_voo  origem  destino  data_hora_partida    portao  status      prefixo  modelo
305         GRU     BSB      2026-09-01 08:30:00  12      Embarque    PR-XAA   A320neo
630         BSB     REC      2026-09-01 13:10:00  18      Confirmado  PR-XAA   A320neo
420         BSB     GIG      2026-09-01 09:15:00  08      Confirmado  PR-XBB   737 MAX 8
305         GRU     BSB      2026-09-02 08:30:00  11      Aguardando  PR-XBB   737 MAX 8
711         BSB     GRU      2026-09-01 10:40:00  23      Embarque    PT-YCC   E195-E2
125         BSB     SSA      2026-09-01 11:20:00  15      Confirmado  PR-XDD   A321neo
308         CGH     BSB      2026-09-01 12:00:00  07      Aguardando  PS-YEE   737-800
512         BSB     CNF      2026-09-01 12:30:00  04      Embarque    PT-ZFF   E190
```

`vw_ocupacao_voo` — 8 linhas:

```
id_voo  numero_voo  data_hora_partida    prefixo  capacidade  vendidas  livres  ocupacao_pct
1       305         2026-09-01 08:30:00  PR-XAA   180         3         177     1.7
7       630         2026-09-01 13:10:00  PR-XAA   180         1         179     0.6
2       420         2026-09-01 09:15:00  PR-XBB   186         2         184     1.1
8       305         2026-09-02 08:30:00  PR-XBB   186         0         186     0.0
3       711         2026-09-01 10:40:00  PT-YCC   136         2         134     1.5
4       125         2026-09-01 11:20:00  PR-XDD   220         2         218     0.9
5       308         2026-09-01 12:00:00  PS-YEE   189         1         188     0.5
6       512         2026-09-01 12:30:00  PT-ZFF   106         1         105     0.9
```

`vw_passagens_pendentes_checkin` — 6 linhas, as passagens com `checkin_realizado = 0`:

```
id_passagem  id_passageiro  id_voo  assento  localizador  classe     checkin_realizado
3            3              1       01A      ABC125       Executiva  0
5            5              2       14D      DEF202       Economica  0
6            1              3       22F      GHI301       Economica  0
9            8              4       18B      JKL402       Economica  0
10           2              5       09C      MNO501       Executiva  0
12           8              7       07D      STU701       Economica  0
```

As views não têm `ORDER BY`; a ordem acima é a que o MySQL devolveu. Quem consome a view
ordena.

---

## 3. Etapa 3 — Índice medido com `performance_schema`

### 3.1 Método

Para cada cenário, nesta ordem:

1. `EXPLAIN` da consulta, sem o índice.
2. `TRUNCATE` de `events_statements_summary_by_digest` e de
   `table_io_waits_summary_by_index_usage`.
3. A consulta executada **30 vezes** na mesma sessão.
4. Leitura dos dois resumos.
5. `CREATE INDEX` e `ANALYZE TABLE`.
6. `EXPLAIN` com o índice.
7. Passos 2 a 4 de novo.

A leitura do resumo de comandos:

```sql
SELECT COUNT_STAR,
       ROUND(AVG_TIMER_WAIT / 1000000000, 4) AS media_ms,
       SUM_ROWS_EXAMINED, SUM_NO_INDEX_USED
  FROM performance_schema.events_statements_summary_by_digest
 WHERE SCHEMA_NAME = 'aeroporto'
   AND DIGEST_TEXT LIKE 'SELECT %FROM `voo` WHERE STATUS = ?%'
   AND DIGEST_TEXT NOT LIKE '%performance_schema%';
```

Três cuidados nesse filtro:

- `AVG_TIMER_WAIT` está em picossegundos; dividir por 10⁹ dá milissegundos.
- O `NOT LIKE '%performance_schema%'` exclui a própria consulta de diagnóstico do resultado.
- **No `DIGEST_TEXT` o MySQL escreve `status` como palavra-chave: `STATUS`, sem crases.** A
  primeira versão do filtro usava `` `status` `` entre crases e não encontrou nada. Todos os
  números abaixo vêm da versão corrigida, executada do zero.

O tempo de uma consulta sobre 8 linhas é ruído. Por isso cada cenário foi executado **em três
rodadas independentes de 30 execuções**, e as linhas examinadas são lidas junto com o tempo.
O tempo médio das tabelas de resultado é a média das três rodadas.

### 3.2 Formulário do índice

| Campo | Preenchimento |
|---|---|
| **Nome** | `idx_voo_status` |
| **Tabela / coluna** | `voo (status)` |
| **Tipo** | B-tree, não único |
| **Consulta beneficiada** | C6: `SELECT id_voo, id_rota, portao, data_hora_partida FROM voo WHERE status = ?` |
| **Justificativa** | É a única consulta do diagnóstico com filtro sem índice que a sirva |
| **Riscos já conhecidos antes de medir** | Baixa cardinalidade (4 valores possíveis, 3 presentes nos dados); coluna atualizada várias vezes na vida de cada voo |

No laboratório, o índice equivalente é `idx_voo_teste_status ON voo_teste (status)`.

### 3.3 Cenário 1 — tabela `voo` real, 8 linhas

Consulta: `WHERE status = 'Embarque'`, que devolve 3 das 8 linhas (37,5%).

**`EXPLAIN` antes e depois:**

```
antes   type ALL  key NULL            rows 8  filtered 12.50  Using where
depois  type ref  key idx_voo_status  rows 3  filtered 100.00
```

**O otimizador usou o índice.** O roteiro da aula previa que, com 8 linhas, ele manteria
`type: ALL`. Não foi o que aconteceu no MySQL 8.0.46: depois do `CREATE INDEX` e do
`ANALYZE TABLE`, o plano passou a `ref`. Nada foi forçado — não há `FORCE INDEX` em nenhum
comando deste trabalho. O resultado está registrado como saiu.

O uso é real, não só planejado. `table_io_waits_summary_by_index_usage`, nas 30 execuções:

| Fase | Leituras sem índice | Leituras via `idx_voo_status` |
|---|---|---|
| antes | 240 (8 × 30) | — |
| depois | nenhuma registrada | 90 (3 × 30) |

**Tempo e linhas examinadas**, `events_statements_summary_by_digest`:

| Rodada | Média antes (ms) | Média depois (ms) | Examinadas por execução |
|---|---|---|---|
| 1 | 0,0565 | 0,0909 | 8 → 3 |
| 2 | 0,0852 | 0,0861 | 8 → 3 |
| 3 | 0,0788 | 0,0879 | 8 → 3 |
| **média** | **0,0735** | **0,0883** | |

`SUM_NO_INDEX_USED` foi de 30 para 0 em todas as rodadas.

**Leitura.** As linhas examinadas caíram de 8 para 3, de forma estável. O tempo não caiu: nas
três rodadas ficou um pouco maior com o índice. Mas a própria medição *sem* índice variou de
0,0565 a 0,0852 ms entre rodadas, uma faixa do mesmo tamanho da diferença antes/depois. Não há
ganho; se há perda, é de centésimos de milissegundo.

O conceito da aula — **evitar índice em tabela pequena** — se confirma, mas por um caminho
diferente do previsto: não porque o otimizador ignora o índice, e sim porque ele o usa sem que
isso produza benefício. As 8 linhas cabem numa única página; percorrer a página inteira custa o
mesmo que descer o índice e buscar três linhas pela chave primária.

### 3.4 Cenário 2 — `voo_teste`, 200 mil linhas, distribuição uniforme

`voo_teste` tem as mesmas colunas de `voo`, só a chave primária, sem FK e sem índice
secundário. As 200 mil linhas foram geradas por `WITH RECURSIVE`, com o status distribuído por
`n % 4`:

| status | linhas | % |
|---|---|---|
| Cancelado | 50.000 | 25,00 |
| Confirmado | 50.000 | 25,00 |
| Aguardando | 50.000 | 25,00 |
| Embarque | 50.000 | 25,00 |

Consulta: `WHERE status = 'Cancelado'`, 50 mil linhas.

**`EXPLAIN`:**

```
antes   type ALL  key NULL                  rows 199440  filtered 10.00  Using where
depois  type ref  key idx_voo_teste_status  rows 98518   filtered 100.00
```

O roteiro previa que, com 25% por valor, o otimizador preferiria a varredura mesmo com o
índice disponível. **Não preferiu: escolheu o índice.** A estimativa foi de 98.518 linhas
para 50 mil reais.

**Uso real do índice:**

| Fase | Leituras sem índice | Leituras via `idx_voo_teste_status` |
|---|---|---|
| antes | 6.000.000 (200.000 × 30) | — |
| depois | nenhuma registrada | 1.500.000 (50.000 × 30) |

**Tempo:**

| Rodada | Média antes (ms) | Média depois (ms) | Examinadas por execução |
|---|---|---|---|
| 1 | 35,08 | 42,32 | 200.000 → 50.000 |
| 2 | 34,03 | 40,91 | 200.000 → 50.000 |
| 3 | 35,05 | 43,05 | 200.000 → 50.000 |
| **média** | **34,72** | **42,09** | |

**O índice deixou a consulta cerca de 21% mais lenta, nas três rodadas**, mesmo examinando
quatro vezes menos linhas. O mínimo também piorou (33,2 → 36,4 ms na rodada 1), então não é um
pico isolado puxando a média.

**Por quê.** A consulta pede colunas que não estão no índice. Para cada uma das 50 mil entradas
de `idx_voo_teste_status`, o InnoDB faz uma busca separada no índice clusterizado para buscar
`id_rota`, `portao` e `data_hora_partida`. A varredura completa percorre as mesmas páginas em
sequência, sem essas buscas. Com um quarto da tabela selecionado, 50 mil buscas custam mais que
ler 200 mil linhas em ordem.

**`linhas examinadas` não é o mesmo que custo.** Este cenário é o contraexemplo: a métrica
caiu 75% e o tempo subiu 21%.

### 3.5 Cenário 3 — `voo_teste`, 200 mil linhas, distribuição desigual

Mesma tabela, com a distribuição realista pedida — `'Cancelado'` raro:

| status | linhas | % |
|---|---|---|
| Cancelado | 1.000 | 0,50 |
| Embarque | 40.000 | 20,00 |
| Aguardando | 60.000 | 30,00 |
| Confirmado | 99.000 | 49,50 |

Consulta: `WHERE status = 'Cancelado'`, mil linhas.

**`EXPLAIN`:**

```
antes   type ALL  key NULL                  rows 199650  filtered 10.00  Using where
depois  type ref  key idx_voo_teste_status  rows 1000    filtered 100.00
```

Aqui a estimativa bateu exatamente com o real.

**Uso real do índice:**

| Fase | Leituras sem índice | Leituras via `idx_voo_teste_status` |
|---|---|---|
| antes | 6.000.000 | — |
| depois | nenhuma registrada | 30.000 (1.000 × 30) |

**Tempo:**

| Rodada | Média antes (ms) | Média depois (ms) | Examinadas por execução |
|---|---|---|---|
| 1 | 29,35 | 2,11 | 200.000 → 1.000 |
| 2 | 26,94 | 2,11 | 200.000 → 1.000 |
| 3 | 26,68 | 1,90 | 200.000 → 1.000 |
| **média** | **27,66** | **2,04** | |

**Ganho de cerca de 13,5 vezes**, com 200 vezes menos linhas examinadas. O ganho aparece na
seletividade: mil buscas pontuais custam muito menos que percorrer 200 mil linhas.

Em cada rodada houve execuções bem mais lentas que a média (máximo de 13,7 ms na rodada 1),
enquanto o mínimo ficou perto de 1 ms. O ganho se sustenta tanto na média quanto no mínimo.

**Por que a distribuição foi escolhida assim.** A comparação entre os cenários 2 e 3 é o
argumento: mesma tabela, mesmo tamanho, mesma consulta, mesmo índice. Só muda quantas linhas
o valor filtrado seleciona — 25% ou 0,5% — e o resultado vai de 21% mais lento a 13,5 vezes
mais rápido. **O tamanho da tabela é condição necessária para o índice valer, mas não é
suficiente: o que decide é a seletividade.**

### 3.6 Complemento — o valor comum na tabela desigual

O cenário 3 mostra o índice ajudando o valor raro. Faltava saber o que ele faz com os valores
comuns da mesma tabela, que também são consultados. Mesma tabela desigual, consulta
`WHERE status = 'Confirmado'`, com 99 mil linhas (49,5%):

```
antes   type ALL  key NULL                  rows 199650  filtered 10.00  Using where
depois  type ref  key idx_voo_teste_status  rows 99825   filtered 100.00
```

| Rodada | Média antes (ms) | Média depois (ms) | Examinadas por execução |
|---|---|---|---|
| 1 | 42,09 | 84,69 | 200.000 → 99.000 |
| 2 | 41,79 | *595,17 — ver nota* | 200.000 → 99.000 |
| 3 | 40,88 | 85,00 | 200.000 → 99.000 |
| **média** | **41,59** | **84,85** (rodadas 1 e 3) | |

**O otimizador escolheu o índice também para metade da tabela, e a consulta ficou cerca de
duas vezes mais lenta.**

*Nota sobre a rodada 2:* uma das 30 execuções levou 15.452 ms. O mínimo da rodada foi 75,98 ms,
em linha com as outras duas. A média da rodada está contaminada por esse travamento e foi
excluída da média final. O fenômeno está descrito na seção 3.8.

**Isso muda a pergunta de "vale manter".** Na mesma tabela, o mesmo índice torna
`'Cancelado'` 13,5 vezes mais rápido e `'Confirmado'` 2 vezes mais lento. Não existe resposta
por índice isolado; a resposta depende de quais valores as consultas do sistema filtram e com
que frequência.

### 3.7 Custo de escrita

A conclusão pede o custo em `INSERT` e `UPDATE`. Ele foi medido na tabela desigual de 200 mil
linhas, em duas configurações:

- **sem índice:** a tabela só com a chave primária;
- **com índice:** `idx_voo_teste_status` criado **antes** da carga, para que cada inserção
  pague a manutenção.

Cada rodada recria a tabela, carrega as 200 mil linhas e executa:

```sql
UPDATE voo_teste
   SET status = IF(status = 'Aguardando', 'Embarque', status)
 WHERE id_voo <= 20000;
```

O `UPDATE` alcança 20 mil linhas e altera o status de 6 mil. O `EXPLAIN` mostra o mesmo plano
nas duas configurações (`range` pela `PRIMARY`), então a diferença de tempo é manutenção do
índice e não mudança de plano.

A primeira medição, de três rodadas por configuração, produziu uma média de `INSERT` distorcida
por uma execução de 3.617 ms. Por isso a medição foi refeita com **seis pares alternados**, sem
e com índice, zerando o `performance_schema` antes de cada carga para ler cada execução
separadamente:

| Par | `INSERT` sem (ms) | `INSERT` com (ms) | `UPDATE` sem (ms) | `UPDATE` com (ms) |
|---|---|---|---|---|
| 1 | 852,3 | 992,6 | 47,1 | 67,9 |
| 2 | 908,2 | 1.097,9 | 50,2 | 67,5 |
| 3 | 783,0 | 1.020,2 | 46,6 | 67,3 |
| 4 | 1.023,1 | 962,3 | 45,7 | 86,0 |
| 5 | *16.436,2* | 1.071,3 | 62,3 | 70,6 |
| 6 | 1.097,1 | 1.036,1 | 52,2 | 74,8 |
| **mediana** | **965,7** | **1.028,2** | **48,7** | **69,3** |

O `UPDATE` alterou 6.000 linhas em todas as execuções.

**`UPDATE` de status: cerca de 42% mais caro com o índice**, e mais caro em todos os seis pares.
Mudar o status de uma linha obriga o InnoDB a retirar a entrada do índice na faixa do valor
antigo e inserir outra na faixa do valor novo.

**`INSERT` em massa: sem conclusão firme.** A mediana subiu cerca de 6,5%, mas o índice só
perdeu em três dos cinco pares válidos, e o par 5 teve um travamento de 16,4 s na carga sem
índice. A diferença, se existe, é menor que a variação da medição.

Duas hipóteses explicam por que a inserção pesa menos que a atualização. **Nenhuma das duas foi
medida:**

- as chaves do índice são `(status, id_voo)`, e como `id_voo` só cresce, cada nova entrada vai
  para o fim da faixa do seu status — quatro pontos de inserção quase sequenciais;
- a geração das 200 mil linhas pela CTE recursiva ocupa boa parte do tempo da carga, e dilui o
  custo do índice.

### 3.8 Notas sobre a medição

**Travamentos isolados.** Duas execuções pararam por cerca de 15 s: uma carga de 200 mil linhas
(16.436 ms) e uma consulta (15.452 ms). As duas ficaram muito acima das execuções equivalentes
e não se repetiram. A causa não foi investigada; o ambiente é Docker Desktop no Windows. Os
dois valores estão reportados nas tabelas e não foram
usados nas conclusões — a medição de escrita usa mediana, e a rodada afetada da seção 3.6 foi
excluída de forma explícita.

**Estimativas amostradas.** O `rows` do `EXPLAIN` para a tabela de 200 mil linhas vem de
estatísticas que o InnoDB calcula por amostragem, e muda entre cargas idênticas: 199.440 e
199.650 sem índice; 98.518 e 97.218 no cenário uniforme com índice. É a única diferença entre as
duas execuções do `views_indices.sql`.

**Memória.** A tabela `voo_teste` ocupa 11,5 MB e o índice 4,5 MB, segundo
`mysql.innodb_index_stats`, contra 128 MB de buffer pool. Os tempos do laboratório medem trabalho
de CPU sobre dados em memória, não leitura de disco. Num banco maior que a memória, a diferença
entre varredura e busca por índice tende a ser outra, e isso **não foi medido**.

**O laboratório não fica no banco.** O `views_indices.sql` recria `voo_teste` nas duas
distribuições, mostra os `EXPLAIN` e apaga a tabela no fim, para não deixar dados sintéticos no
schema do projeto. As medições de tempo foram feitas por um roteiro externo com os mesmos
comandos, porque 30 repetições de uma consulta que devolve 50 mil linhas não cabem num arquivo
de entrega.

---

## 4. Etapa 4 — Registro de resultados

| Consulta testada | type antes | rows antes | Tempo médio antes (ms) | type depois | rows depois | Tempo médio depois (ms) | Conclusão |
|---|---|---|---|---|---|---|---|
| `voo`, 8 linhas, `status = 'Embarque'` (37,5%) | ALL | 8 | 0,0735 | ref | 3 | 0,0883 | Índice usado, sem ganho. Diferença dentro do ruído. Não vale manter neste volume |
| `voo_teste`, 200 mil, uniforme, `status = 'Cancelado'` (25%) | ALL | 199.440 | 34,72 | ref | 98.518 | 42,09 | Índice usado e **21% mais lento**. Seletividade baixa demais |
| `voo_teste`, 200 mil, desigual, `status = 'Cancelado'` (0,5%) | ALL | 199.650 | 27,66 | ref | 1.000 | 2,04 | **Cerca de 13,5× mais rápido.** É o caso em que o índice vale |
| `voo_teste`, 200 mil, desigual, `status = 'Confirmado'` (49,5%) | ALL | 199.650 | 41,59 | ref | 99.825 | 84,85 | Índice usado e **2× mais lento**. O mesmo índice do caso anterior |

`rows` é a estimativa do otimizador. As linhas efetivamente examinadas, lidas no
`performance_schema`, foram 8 → 3, 200.000 → 50.000, 200.000 → 1.000 e 200.000 → 99.000.

### O índice ajudou?

**Na tabela real, não.** As linhas examinadas caíram de 8 para 3, mas o tempo não melhorou nas
três rodadas.

**Com volume, depende do valor filtrado.** Ajudou muito quando o valor era raro (0,5%, cerca de
13,5 vezes mais rápido) e atrapalhou quando era comum (25%, 21% mais lento; 49,5%, duas vezes
mais lento).

### Por que ajudou ou não?

Por **seletividade**, e não só por tamanho. O índice troca uma leitura sequencial da tabela por
uma busca na chave primária para cada linha encontrada. Essa troca compensa quando são poucas
linhas e deixa de compensar quando é uma fração grande da tabela.

Na tabela de 8 linhas não há o que economizar: tudo cabe numa página.

O fato que o roteiro não previa é que **o MySQL 8.0.46 escolheu o índice em todos os casos**, até
quando ele piorava o resultado. O otimizador decide por um modelo de custo estimado, e nos
cenários 2 e 4 esse modelo avaliou o índice como a opção mais barata. A medição mostrou o
contrário. É também
por isso que `linhas examinadas` sozinha engana: ela caiu em todos os cenários, inclusive nos
dois em que o tempo piorou.

### Vale manter, considerando o custo em INSERT e UPDATE?

O custo de escrita medido: **`UPDATE` de status cerca de 42% mais caro** com o índice, em todos
os pares; `INSERT` em massa sem diferença conclusiva.

O `UPDATE` de status é o que pesa. Em `voo`, essa coluna não é estática: todo voo passa por
`Aguardando`, `Confirmado` e `Embarque`, e o cancelamento é um `UPDATE` de status por decisão
da Aula 10. O índice encarece exatamente a escrita mais frequente da tabela.

**Na tabela `voo` atual: não vale manter.** Não traz ganho de leitura e encarece a escrita mais
comum.

**Com volume, só vale se as consultas por status filtrarem valores raros**, como listar
cancelamentos. Se o painel consultar principalmente os status comuns — voos confirmados ou em
embarque —, o índice piora as leituras frequentes e as escritas ao mesmo tempo. Nesse caso, o
correto é não criar o índice, e não forçar a varredura com `IGNORE INDEX` em cada consulta.

### Decisão sobre `idx_voo_status`

O `views_indices.sql` cria o índice porque a atividade pede a criação e a medição. **A
recomendação desta análise é removê-lo no volume atual do projeto** e reavaliar quando `voo`
tiver histórico de milhares de voos e uma consulta real por status raro.

Duas alternativas ficam registradas como próximos passos. **Nenhuma foi testada:**

- um índice **cobridor**, `(status, id_rota, portao, data_hora_partida)`, contendo todas as
  colunas da consulta, dispensaria as buscas na chave primária que tornaram os valores comuns
  lentos;
- um índice começando por `data_hora_partida`, que serve às consultas C1 e C5, é provavelmente
  mais útil para o painel do que um índice em `status`.

---

## 5. Etapa 5. Compartilhamento com a turma

O roteiro pede dois pontos: uma view proposta e por quê, e um resultado de índice e o que
ele ensinou. Escolhi os dois casos em que o resultado contrariou o que eu esperava antes de
medir.

### 5.1 A view: `vw_painel_voos`

Propus essa view porque o painel de voos é a consulta que o projeto repete desde a Aula 08:
juntar `voo`, `rota`, `aeronave` e `modelo_aeronave` para mostrar número do voo, origem,
destino, horário, portão, status e o modelo da aeronave. São quatro tabelas para responder a
pergunta mais banal do sistema.

O que eu não esperava: **essa view aceitava escrita.** O `information_schema.VIEWS` devolvia
`IS_UPDATABLE = YES`, porque o MySQL 8 permite `UPDATE` através de uma view com `JOIN` desde
que o comando altere uma única tabela de base.

O risco apareceu no teste. Um `UPDATE vw_painel_voos SET modelo = ...` pedido para o voo 305
alterou também o voo 630, porque os dois usam a mesma aeronave e, portanto, o mesmo registro
em `modelo_aeronave`. Quem escreve o comando pensa estar mexendo em uma linha da view e mexe
em uma linha de uma tabela que outras linhas da view compartilham.

A solução foi declarar a view com `ALGORITHM = TEMPTABLE`. O MySQL passa a materializar o
resultado numa tabela temporária, a view deixa de ser atualizável e qualquer escrita é
recusada com o erro 1288. Verifiquei depois, pelo `EXPLAIN`, que um filtro por `status` na
view continua usando `idx_voo_status`, ou seja, a proteção não custou o índice.

### 5.2 O resultado de índice: o mesmo índice, dois desempenhos opostos

O caso que mais ensinou não foi o índice ajudar ou não ajudar. Foi o mesmo índice, na mesma
tabela, com a mesma distribuição de dados, fazer as duas coisas conforme o valor filtrado.

| Consulta na `voo_teste` desigual, 200 mil linhas | Sem índice | Com `idx_voo_teste_status` | Efeito |
|---|---|---|---|
| `status = 'Cancelado'` (0,5% das linhas) | 27,66 ms | 2,04 ms | cerca de 13,5 vezes mais rápido |
| `status = 'Confirmado'` (49,5% das linhas) | 41,59 ms | 84,85 ms | 2 vezes mais lento |

Três lições que eu levo daqui.

**A decisão é por seletividade, não por tamanho de tabela.** A regra que eu tinha na cabeça,
"índice não ajuda em tabela pequena", está certa mas é secundária. As duas linhas acima vêm
da mesma tabela de 200 mil linhas. O que separou o ganho do prejuízo foi a fração de linhas
que o filtro devolve.

**O otimizador escolheu o índice inclusive quando ele piorava.** Nos quatro cenários medidos o
`EXPLAIN` mostrou `type: ref`, mesmo nos dois em que o tempo aumentou. A decisão dele é por
custo estimado, e o modelo errou. Isso derruba a ideia de que ver o índice no plano de
execução é prova de que ele ajudou.

**Linhas examinadas caindo não significa consulta mais rápida.** A métrica caiu nos quatro
cenários, inclusive nos dois que ficaram mais lentos. Cada linha encontrada pelo índice ainda
exige uma busca na chave primária para trazer as colunas que não estão nele, e é esse custo
que o número de linhas examinadas não mostra.

### 5.3 O que eu levo para a discussão

Duas perguntas que eu queria ouvir de quem modelou o aeroporto de outro jeito:

1. Quem colocou índice em coluna de status ou de situação mediu o tempo, ou parou no `EXPLAIN`?
   Pelo que medi aqui, o plano de execução sozinho teria me levado à conclusão errada em dois
   dos quatro cenários.
2. Quem tem view com `JOIN` no projeto testou escrita através dela? A propagação silenciosa que
   encontrei no `vw_painel_voos` vale para qualquer view que junte uma tabela de dimensão com
   uma tabela de fato, que é o formato mais comum de view de painel.
