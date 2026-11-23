-- =============================================================================
-- Aula 33 - BI Aeroporto: consultas dos cinco paineis
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Todas partem de fato_voo e usam so as dimensoes necessarias.
-- Como o grao e o voo, COUNT(*) conta voos sem duplicidade: cada voo e uma
-- linha. Passageiros vem de SUM(qtd_passageiros), ja contado uma vez por voo
-- no ETL. Nenhum JOIN abaixo multiplica linhas (todo JOIN e fato -> dimensao,
-- N:1), por isso COUNT(DISTINCT) nao e necessario aqui. Ele seria necessario
-- se a fato estivesse no grao da passagem (ver modelo_estrela.md).
-- Rodar depois de etl.sql.
-- =============================================================================

USE aeroporto_dw;

-- -----------------------------------------------------------------------------
-- Painel 1: destinos mais frequentes (ranking)
-- GROUP BY: d.destino
-- WHERE:    status <> 'Cancelado' (voo cancelado nao vai ao destino)
-- OLAP:     roll up de voo para destino, com slice em status
-- -----------------------------------------------------------------------------
SELECT   d.destino, COUNT(*) AS voos
FROM     fato_voo f
JOIN     dim_rota d ON d.sk_rota = f.sk_rota
WHERE    f.status <> 'Cancelado'
GROUP BY d.destino
ORDER BY voos DESC, d.destino
LIMIT    5;

-- -----------------------------------------------------------------------------
-- Painel 2: numero de passageiros por mes (evolucao)
-- GROUP BY: t.ano, t.mes, t.nome_mes
-- WHERE:    t.ano = 2026 (o filtro de ano do painel)
-- OLAP:     roll up de dia para mes, com slice no ano
-- Passageiro aqui e passageiro transportado (uma passagem), a medida usual de
-- movimento de aeroporto: quem voa duas vezes no mes conta duas.
-- -----------------------------------------------------------------------------
SELECT   t.ano, t.mes, t.nome_mes, SUM(f.qtd_passageiros) AS passageiros
FROM     fato_voo f
JOIN     dim_tempo t ON t.sk_tempo = f.sk_tempo
WHERE    t.ano = 2026
GROUP BY t.ano, t.mes, t.nome_mes
ORDER BY t.ano, t.mes;

-- -----------------------------------------------------------------------------
-- Painel 3: numero de voos (quanto?)
-- GROUP BY: nenhum (um numero so, o indicador do painel)
-- WHERE:    t.ano = 2026 AND t.mes = 9 (periodo escolhido no filtro)
-- OLAP:     slice no mes; roll up total
-- -----------------------------------------------------------------------------
SELECT   COUNT(*) AS voos
FROM     fato_voo f
JOIN     dim_tempo t ON t.sk_tempo = f.sk_tempo
WHERE    t.ano = 2026 AND t.mes = 9;

-- Mesmo indicador aberto por status (drill down).
SELECT   f.status, COUNT(*) AS voos
FROM     fato_voo f
JOIN     dim_tempo t ON t.sk_tempo = f.sk_tempo
WHERE    t.ano = 2026 AND t.mes = 9
GROUP BY f.status
ORDER BY voos DESC;

-- -----------------------------------------------------------------------------
-- Painel 4: companhia aerea mais atuante (ranking / participacao)
-- GROUP BY: a.companhia
-- WHERE:    status <> 'Cancelado'
-- OLAP:     roll up de voo para companhia, com slice em status
-- Lacuna: companhia nao existe no OLTP. A consulta assume a coluna em
-- dim_aeronave; hoje ela esta NULL e o resultado sai numa linha so.
-- A participacao usa SUM(COUNT(*)) OVER (), o total de voos do resultado.
-- -----------------------------------------------------------------------------
SELECT   COALESCE(a.companhia, '(sem dado)') AS companhia,
         COUNT(*) AS voos,
         ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS participacao_pct
FROM     fato_voo f
JOIN     dim_aeronave a ON a.sk_aeronave = f.sk_aeronave
WHERE    f.status <> 'Cancelado'
GROUP BY a.companhia
ORDER BY voos DESC
LIMIT    5;

-- -----------------------------------------------------------------------------
-- Painel 5 (livre): taxa de ocupacao por modelo de aeronave (ranking)
-- GROUP BY: a.modelo, a.fabricante
-- WHERE:    t.ano = 2026 AND t.mes = 9
-- OLAP:     roll up de aeronave para modelo; drill down possivel para prefixo
-- Ocupacao e nao aditiva: calcula SUM(passageiros) / SUM(capacidade) no grupo,
-- nunca a media das ocupacoes de cada voo.
-- -----------------------------------------------------------------------------
SELECT   a.modelo, a.fabricante,
         COUNT(*)                 AS voos,
         SUM(f.qtd_passageiros)   AS passageiros,
         SUM(f.capacidade_assentos) AS assentos,
         ROUND(100 * SUM(f.qtd_passageiros) / SUM(f.capacidade_assentos), 2)
                                  AS ocupacao_pct
FROM     fato_voo f
JOIN     dim_aeronave a ON a.sk_aeronave = f.sk_aeronave
JOIN     dim_tempo t    ON t.sk_tempo    = f.sk_tempo
WHERE    t.ano = 2026 AND t.mes = 9
GROUP BY a.modelo, a.fabricante
ORDER BY ocupacao_pct DESC
LIMIT    5;
