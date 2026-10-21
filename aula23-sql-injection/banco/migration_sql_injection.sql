-- Aula 23 - SQL Injection.
-- Rodar como root depois do aula22-soft-delete/banco/migration_soft_delete.sql.
--
-- O enunciado ataca uma tabela usuarios com email e senha_hash. No projeto a
-- tabela se chama usuario (Aula 22) e so tinha nome. Aqui ela ganha as duas
-- colunas, com dados de teste, para o payload 4 ter o que vazar.
-- Os hashes sao bcrypt gerados com password_hash() do PHP. Senhas de teste:
-- ana2026, bruno2026 e carla2026.

USE aeroporto;

ALTER TABLE usuario
    ADD COLUMN email      VARCHAR(150) NULL,
    ADD COLUMN senha_hash VARCHAR(255) NULL,
    ADD CONSTRAINT uq_usuario_email UNIQUE (email);

UPDATE usuario SET email = 'ana.ribeiro@aeroporto.test',
                   senha_hash = '$2y$10$bakg5W0Cm0KLtFX3qZuagOrRanV830raScK.Dv3GDHxVdCuQd/jQO'
 WHERE nome = 'Ana Ribeiro';
UPDATE usuario SET email = 'bruno.teixeira@aeroporto.test',
                   senha_hash = '$2y$10$BhvQ67y2KGhTU2jkmXTWr.aL7sMeFFAFcLtDKGZpgTlr6rsDMHo6G'
 WHERE nome = 'Bruno Teixeira';
UPDATE usuario SET email = 'carla.mendes@aeroporto.test',
                   senha_hash = '$2y$10$dbZ63yC598Dc9yqGajxFj.xGAXEoBlxvqms8liOlov3yWprQDsugm'
 WHERE nome = 'Carla Mendes';
