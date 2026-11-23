-- =============================================================================
-- Aula 33 - BI Aeroporto: ETL do aeroporto (OLTP) para o aeroporto_dw
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Carga completa: esvazia o DW e recarrega. Dimensoes antes da fato, porque a
-- fato so recebe sk que ja existem nas dimensoes (FK).
-- Rodar depois de dw.sql.
-- =============================================================================

USE aeroporto_dw;

-- Nome do mes e do dia da semana em portugues.
SET lc_time_names = 'pt_BR';

-- 0. Limpeza, na ordem inversa da carga.
DELETE FROM fato_voo;
DELETE FROM dim_aeronave;
DELETE FROM dim_rota;
DELETE FROM dim_tempo;

-- 1. dim_tempo: um dia por data de partida existente. Voo com soft delete
--    (Aula 22) nao entra no DW.
INSERT INTO dim_tempo (sk_tempo, data, ano, mes, nome_mes, dia, dia_semana)
SELECT DISTINCT
       CAST(DATE_FORMAT(v.data_hora_partida, '%Y%m%d') AS UNSIGNED),
       DATE(v.data_hora_partida),
       YEAR(v.data_hora_partida),
       MONTH(v.data_hora_partida),
       MONTHNAME(v.data_hora_partida),
       DAY(v.data_hora_partida),
       DAYNAME(v.data_hora_partida)
  FROM aeroporto.voo v
 WHERE v.deleted_at IS NULL;

-- 2. dim_rota: copia direta. Na base principal a origem ainda esta em
--    rota.origem (a Aula 30 so mexeu no aeroporto_lab).
INSERT INTO dim_rota (id_rota, numero_voo, origem, destino)
SELECT r.id_rota, r.numero_voo, r.origem, r.destino
  FROM aeroporto.rota r;

-- 3. dim_aeronave: junta aeronave com modelo_aeronave (desnormaliza).
--    companhia fica NULL: o OLTP nao tem esse dado (lacuna).
INSERT INTO dim_aeronave (id_aeronave, prefixo, modelo, fabricante,
                          capacidade_assentos, companhia)
SELECT a.id_aeronave, a.prefixo, m.modelo, m.fabricante,
       a.capacidade_assentos, NULL
  FROM aeroporto.aeronave a
  JOIN aeroporto.modelo_aeronave m ON m.id_modelo = a.id_modelo;

-- 4. fato_voo: uma linha por voo. qtd_passageiros e contada em passagem, e
--    nao lida de voo.passagens_vendidas (contador da trigger da Aula 15), para
--    a fato depender so do registro de origem. LEFT JOIN para o voo sem
--    passagem entrar com 0, e o agrupamento por id_voo garante uma linha por
--    voo mesmo com varias passagens.
INSERT INTO fato_voo (id_voo, sk_tempo, sk_rota, sk_aeronave, status,
                      qtd_voos, qtd_passageiros, capacidade_assentos)
SELECT v.id_voo,
       t.sk_tempo,
       dr.sk_rota,
       da.sk_aeronave,
       v.status,
       1,
       COUNT(p.id_passagem),
       da.capacidade_assentos
  FROM aeroporto.voo v
  JOIN dim_tempo t     ON t.data         = DATE(v.data_hora_partida)
  JOIN dim_rota dr     ON dr.id_rota     = v.id_rota
  JOIN dim_aeronave da ON da.id_aeronave = v.id_aeronave
  LEFT JOIN aeroporto.passagem p ON p.id_voo = v.id_voo
 WHERE v.deleted_at IS NULL
 GROUP BY v.id_voo, t.sk_tempo, dr.sk_rota, da.sk_aeronave, v.status,
          da.capacidade_assentos;

-- 5. Conferencia contra o OLTP.
SELECT 'voos'        AS medida,
       (SELECT COUNT(*) FROM aeroporto.voo WHERE deleted_at IS NULL) AS oltp,
       (SELECT SUM(qtd_voos) FROM fato_voo)                          AS dw
UNION ALL
SELECT 'passageiros (passagens)',
       (SELECT COUNT(*) FROM aeroporto.passagem p
          JOIN aeroporto.voo v ON v.id_voo = p.id_voo
         WHERE v.deleted_at IS NULL),
       (SELECT SUM(qtd_passageiros) FROM fato_voo)
UNION ALL
SELECT 'rotas',     (SELECT COUNT(*) FROM aeroporto.rota),     (SELECT COUNT(*) FROM dim_rota)
UNION ALL
SELECT 'aeronaves', (SELECT COUNT(*) FROM aeroporto.aeronave), (SELECT COUNT(*) FROM dim_aeronave);
