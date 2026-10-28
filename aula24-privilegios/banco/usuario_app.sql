-- Aula 24 - conta da aplicacao no SGBD com privilegios minimos.
-- Rodar como root depois de migration_sql_injection.sql.
--
-- Nome da conta como no enunciado: app_aeroporto. Ela sera usada nas proximas
-- aulas. Os privilegios sao os que o sistema de voos realmente usa, tabela por
-- tabela, sem DELETE em nenhuma: a exclusao de voo e soft delete (UPDATE).
-- As triggers da Aula 15 rodam com os privilegios de quem as criou (root), por
-- isso continuam gravando em log_alteracao_voo sem GRANT para a aplicacao.
-- Nao e preciso FLUSH PRIVILEGES depois de GRANT.
-- Troque a senha e use a mesma no .env.

CREATE USER IF NOT EXISTS 'app_aeroporto'@'localhost' IDENTIFIED BY 'troque_esta_senha';

GRANT SELECT, INSERT, UPDATE ON aeroporto.voo             TO 'app_aeroporto'@'localhost';
GRANT SELECT, INSERT         ON aeroporto.auditoria       TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.rota            TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.aeronave        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.modelo_aeronave TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.passagem        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.usuario         TO 'app_aeroporto'@'localhost';

SHOW GRANTS FOR 'app_aeroporto'@'localhost';
