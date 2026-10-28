-- Aula 25 - conta da aplicacao (criada na Aula 24) com privilegios minimos.
-- Rodar como root depois de migration_autenticacao.sql. Pode rodar de novo:
-- CREATE USER IF NOT EXISTS e GRANT nao duplicam nada.
--
-- Diferenca para a Aula 24: INSERT em rota. O cadastro de voo agora recebe o
-- codigo, a origem e o destino digitados; se o codigo ainda nao existe, a rota
-- e criada. Continua sem DELETE em nenhuma tabela e sem UPDATE em rota e
-- usuario: a aplicacao nao altera rota existente nem troca senha ou perfil.
-- Troque a senha e use a mesma no .env.

CREATE USER IF NOT EXISTS 'app_aeroporto'@'localhost' IDENTIFIED BY 'troque_esta_senha';

GRANT SELECT, INSERT, UPDATE ON aeroporto.voo             TO 'app_aeroporto'@'localhost';
GRANT SELECT, INSERT         ON aeroporto.auditoria       TO 'app_aeroporto'@'localhost';
GRANT SELECT, INSERT         ON aeroporto.rota            TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.aeronave        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.modelo_aeronave TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.passagem        TO 'app_aeroporto'@'localhost';
GRANT SELECT                 ON aeroporto.usuario         TO 'app_aeroporto'@'localhost';

SHOW GRANTS FOR 'app_aeroporto'@'localhost';
