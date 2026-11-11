-- Aula 30 - conta da aplicacao com privilegios minimos no banco de teste
-- aeroporto_lab. Rodar como root depois de criar o aeroporto_lab. Pode rodar
-- de novo: CREATE USER IF NOT EXISTS e GRANT nao duplicam nada.
--
-- Mesmos privilegios da Aula 25, agora em aeroporto_lab. Todos sao por tabela,
-- nenhum por coluna, entao aeroporto_origem fica coberta sem GRANT novo: o
-- INSERT em rota vale para a coluna nova, e nada cita rota.origem. A conta
-- continua sem ALTER: quem roda as migrations e o backfill e a conta
-- MIGRATE_USER do .env.
-- Troque a senha e use a mesma no .env.

CREATE USER IF NOT EXISTS 'app_aeroporto'@'localhost' IDENTIFIED BY 'troque_esta_senha';

GRANT SELECT, INSERT, UPDATE ON aeroporto_lab.voo             TO 'app_aeroporto'@'localhost';
GRANT SELECT, INSERT         ON aeroporto_lab.auditoria       TO 'app_aeroporto'@'localhost';
GRANT SELECT, INSERT         ON aeroporto_lab.rota            TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto_lab.aeronave        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto_lab.modelo_aeronave TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto_lab.passagem        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto_lab.usuario         TO 'app_aeroporto'@'localhost';

SHOW GRANTS FOR 'app_aeroporto'@'localhost';
