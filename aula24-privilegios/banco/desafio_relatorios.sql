-- Aula 24 - desafio: conta so de leitura para relatorios.
-- Rodar como root, por partes, testando entre elas com a conta relatorios
-- (os testes estao no RELATORIO.md).

-- Passo 1: leitura em todo o banco.
CREATE USER IF NOT EXISTS 'relatorios'@'localhost' IDENTIFIED BY 'troque_esta_senha';
GRANT SELECT ON aeroporto.* TO 'relatorios'@'localhost';

-- Passo 2: tira a leitura geral e libera so id e nome de passageiro.
-- No projeto a tabela e passageiro (singular) e a chave e id_passageiro.
REVOKE SELECT ON aeroporto.* FROM 'relatorios'@'localhost';
GRANT SELECT (id_passageiro, nome) ON aeroporto.passageiro TO 'relatorios'@'localhost';

-- Passo 4 (alternativa): uma view so com as colunas permitidas, e SELECT nela.
-- A view roda com os privilegios de quem a criou (SQL SECURITY DEFINER, o
-- padrao), entao a conta le a view sem ter privilegio na tabela.
CREATE OR REPLACE VIEW aeroporto.vw_passageiro_relatorio AS
    SELECT id_passageiro, nome FROM aeroporto.passageiro;
GRANT SELECT ON aeroporto.vw_passageiro_relatorio TO 'relatorios'@'localhost';

-- Limpeza (opcional), como pede o enunciado:
-- DROP USER 'relatorios'@'localhost';
-- DROP VIEW aeroporto.vw_passageiro_relatorio;
