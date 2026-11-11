-- 003a_vw_painel_voos_aeroporto_origem.sql
-- A vw_painel_voos (Aula 14) le r.origem e ficaria invalida depois da 004.
-- Esta migration recria a view lendo aeroporto_origem. O nome 003a ordena
-- depois da 003 e antes da 004, tanto no sort() do up quanto no ORDER BY
-- version DESC do down. Rodar so depois do backfill.
-- up
CREATE OR REPLACE ALGORITHM = TEMPTABLE VIEW vw_painel_voos AS
SELECT r.numero_voo,
       r.aeroporto_origem AS origem,
       r.destino,
       v.data_hora_partida,
       v.portao,
       v.status,
       a.prefixo,
       m.modelo
  FROM voo v
  JOIN rota r            ON r.id_rota     = v.id_rota
  JOIN aeronave a        ON a.id_aeronave = v.id_aeronave
  JOIN modelo_aeronave m ON m.id_modelo   = a.id_modelo;

-- down
CREATE OR REPLACE ALGORITHM = TEMPTABLE VIEW vw_painel_voos AS
SELECT r.numero_voo,
       r.origem,
       r.destino,
       v.data_hora_partida,
       v.portao,
       v.status,
       a.prefixo,
       m.modelo
  FROM voo v
  JOIN rota r            ON r.id_rota     = v.id_rota
  JOIN aeronave a        ON a.id_aeronave = v.id_aeronave
  JOIN modelo_aeronave m ON m.id_modelo   = a.id_modelo;
