-- Aula 22 - usuario da aplicacao com privilegios minimos.
-- Rodar como root depois do migration_soft_delete.sql.
--
-- Diferenca para a Aula 21: a aplicacao perdeu o privilegio DELETE. Com soft
-- delete nenhuma tela apaga linha; se algum codigo tentar um DELETE, o banco
-- recusa (erro 1142). Na auditoria a aplicacao so insere e le, entao a trilha
-- nao pode ser alterada nem apagada por ela.
-- As triggers da Aula 15 rodam com os privilegios de quem as criou (root),
-- por isso continuam gravando em log_alteracao_voo.
-- Troque a senha e use a mesma no .env.

CREATE USER IF NOT EXISTS 'aeroporto_app'@'localhost' IDENTIFIED BY 'troque_esta_senha';

-- Remove o GRANT da Aula 21 (SELECT, INSERT, UPDATE, DELETE no banco todo).
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'aeroporto_app'@'localhost';

GRANT SELECT, INSERT, UPDATE ON aeroporto.voo             TO 'aeroporto_app'@'localhost';
GRANT SELECT, INSERT         ON aeroporto.auditoria       TO 'aeroporto_app'@'localhost';
GRANT SELECT                 ON aeroporto.rota            TO 'aeroporto_app'@'localhost';
GRANT SELECT                 ON aeroporto.aeronave        TO 'aeroporto_app'@'localhost';
GRANT SELECT                 ON aeroporto.modelo_aeronave TO 'aeroporto_app'@'localhost';
GRANT SELECT                 ON aeroporto.passagem        TO 'aeroporto_app'@'localhost';
GRANT SELECT                 ON aeroporto.usuario         TO 'aeroporto_app'@'localhost';
