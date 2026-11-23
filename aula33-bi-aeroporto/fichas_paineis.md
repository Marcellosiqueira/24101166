# Fichas dos painéis

Todas as fichas usam a fato `fato_voo` (grão: um voo). As consultas estão em
[banco/consultas_paineis.sql](banco/consultas_paineis.sql).

## Painel 1

```
PAINEL: Destinos mais frequentes
Pergunta de negócio:   Para quais aeroportos saem mais voos daqui?
Indicador (medida):    quantidade de voos, COUNT(*) da fato
Dimensões usadas:      dim_rota (destino)
Filtros do painel:     status diferente de Cancelado; período (dim_tempo)
Gráfico sugerido:      barras horizontais ordenadas, top 5
Operação OLAP:         (x) roll up  ( ) drill down  (x) slice  ( ) dice  ( ) pivot
```

Roll up do voo para o destino; slice em status.

## Painel 2

```
PAINEL: Número de passageiros por mês
Pergunta de negócio:   Quantos passageiros o aeroporto transportou em cada mês?
Indicador (medida):    passageiros transportados, SUM(qtd_passageiros)
Dimensões usadas:      dim_tempo (ano, mes, nome_mes)
Filtros do painel:     ano
Gráfico sugerido:      linha, um ponto por mês
Operação OLAP:         (x) roll up  ( ) drill down  (x) slice  ( ) dice  ( ) pivot
```

Roll up de dia para mês; slice no ano. Drill down para dia é possível com `dim_tempo.dia`.

## Painel 3

```
PAINEL: Número de voos
Pergunta de negócio:   Quantos voos operamos no período?
Indicador (medida):    quantidade de voos, COUNT(*) da fato
Dimensões usadas:      dim_tempo (ano, mes); status (degenerada) no detalhe
Filtros do painel:     ano e mês
Gráfico sugerido:      cartão com o número grande; barras por status abaixo
Operação OLAP:         ( ) roll up  (x) drill down  (x) slice  ( ) dice  ( ) pivot
```

Slice no mês para o número total; drill down do total para status.

## Painel 4

```
PAINEL: Companhia aérea mais atuante
Pergunta de negócio:   Qual companhia opera mais voos aqui e com que participação?
Indicador (medida):    quantidade de voos e participação % no total
Dimensões usadas:      dim_aeronave (companhia)
Filtros do painel:     status diferente de Cancelado; período
Gráfico sugerido:      barras ordenadas com rótulo de %; rosca se forem poucas
Operação OLAP:         (x) roll up  ( ) drill down  (x) slice  ( ) dice  ( ) pivot
```

Lacuna: o OLTP não tem companhia. Ver [lacunas.md](lacunas.md).

## Painel 5 (livre)

```
PAINEL: Taxa de ocupação por modelo de aeronave
Pergunta de negócio:   Que modelos voam mais cheios e quais estão superdimensionados?
Indicador (medida):    ocupação % = SUM(qtd_passageiros) / SUM(capacidade_assentos)
Dimensões usadas:      dim_aeronave (modelo, fabricante), dim_tempo (ano, mes)
Filtros do painel:     ano e mês; fabricante
Gráfico sugerido:      barras ordenadas por ocupação, com voos e assentos no rótulo
Operação OLAP:         (x) roll up  (x) drill down  ( ) slice  (x) dice  ( ) pivot
```

Roll up de aeronave para modelo; drill down do modelo para o prefixo; dice com ano, mês
e fabricante ao mesmo tempo. A ocupação é não aditiva e por isso é SUM/SUM no grupo.
