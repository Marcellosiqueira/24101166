-- Aula 30 - recria o banco de teste do zero. Depois dele o lab esta pronto
-- para php migrate.php up 001_baseline.
-- Rodar como root, de dentro da pasta aula30-migrations (os SOURCE usam
-- caminho relativo), depois de gerar o dump uma vez:
--   mysqldump -u root aeroporto > aeroporto_backup.sql
--   mysql -u root < reset_lab.sql

DROP DATABASE IF EXISTS aeroporto_lab;
CREATE DATABASE aeroporto_lab CHARACTER SET utf8mb4;
USE aeroporto_lab;

SOURCE aeroporto_backup.sql;
SOURCE banco/view_painel_voos.sql;
SOURCE banco/usuario_app.sql;

-- Conferencia: sem schema_migrations, com origem em rota e a view lendo origem.
SELECT COUNT(*) AS rotas FROM rota;
SELECT COUNT(*) AS tabela_schema_migrations
  FROM information_schema.tables
 WHERE table_schema = 'aeroporto_lab' AND table_name = 'schema_migrations';
SELECT numero_voo, origem, destino FROM vw_painel_voos LIMIT 1;
