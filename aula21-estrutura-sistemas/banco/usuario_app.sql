-- Aula 21 - usuario da aplicacao com privilegios minimos.
-- Rodar como root depois do aula10-integridade/sql_integridade.sql.
-- A aplicacao so le e grava linhas: nao cria tabela, nao apaga banco,
-- nao concede permissao. Se a aplicacao for comprometida, o estrago fica
-- limitado a isso. Troque a senha e use a mesma no .env.

CREATE USER IF NOT EXISTS 'aeroporto_app'@'localhost' IDENTIFIED BY 'troque_esta_senha';
GRANT SELECT, INSERT, UPDATE, DELETE ON aeroporto.* TO 'aeroporto_app'@'localhost';
