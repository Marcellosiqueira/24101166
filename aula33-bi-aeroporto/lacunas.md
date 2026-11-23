# Lacunas do modelo OLTP

Dados que os painéis precisariam e que o banco `aeroporto` não tem. O esquema da Aula 10
não foi alterado; a lacuna fica registrada e o DW está pronto para receber o dado.

## Companhia aérea (painel 4)

Não existe tabela nem coluna de companhia.

Proposta no OLTP: tabela `companhia (id_companhia, codigo_iata CHAR(2), nome)` e FK
`aeronave.id_companhia`. A aeronave pertence a uma companhia, e o voo herda a companhia
pela aeronave escalada. Se o projeto precisar de aeronave arrendada ou voo em
codeshare, a FK passa para `voo`.

No DW: a coluna `dim_aeronave.companhia` já existe e o ETL carrega `NULL`. Com a FK no
OLTP, o ETL passa a fazer `JOIN aeroporto.companhia` e a consulta do painel 4 não muda.
Hoje ela devolve uma linha `(sem dado)` com os 8 voos.

Observação: o `numero_voo` do banco começa com `LA`, que é um código de companhia IATA.
Daria para extrair a companhia com `LEFT(numero_voo, 2)`, mas é uma convenção de texto
sem constraint que a garanta, e todas as rotas têm o mesmo prefixo. Não foi usado.

## Outras

| Lacuna | Efeito no BI |
|---|---|
| Aeroporto só como código IATA (`origem`, `destino`) | `dim_rota` não tem cidade, UF nem país; o painel 1 mostra `BSB`, não "Brasília" |
| Só horário previsto (`data_hora_partida`, `data_hora_chegada_prevista`) | não há partida real nem atraso; um painel de pontualidade não é possível |
| `status` sem valor de voo concluído | não dá para separar voo realizado de voo programado |
| Sem preço ou tarifa em `passagem` | nenhuma medida de receita |
| Base de exemplo com 8 voos em 2 dias de setembro de 2026 | o painel 2 tem um ponto só; a consulta está certa, os dados é que não têm meses diferentes |
| Aeronave `PT-TST` (id 7, capacidade 2) sem voo, criada pelo teste de triggers da Aula 15 | entra em `dim_aeronave` e não aparece em nenhum painel, porque não tem linha na fato |
