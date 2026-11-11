-- Aula 30 - vw_painel_voos da Aula 14 (aula14-views-indices/views_indices.sql),
-- igual a original, lendo r.origem. Estado de antes das migrations: a 003a
-- recria a view com aeroporto_origem. Rodar no banco de teste:
--   mysql -u root aeroporto_lab < banco/view_painel_voos.sql

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
