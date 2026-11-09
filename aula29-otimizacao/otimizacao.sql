-- =============================================================================
-- Aula 29 - Otimizacao de consultas: lendo o plano de execucao com EXPLAIN
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco: lab_otimizacao (separado do aeroporto, como o enunciado pede)
--
--   mysql -u root -p -t < otimizacao.sql
--
-- O script roda a atividade inteira em ordem, da Parte 0 ao desafio da
-- Parte 4. Os resultados medidos e as respostas estao no README.md.
-- Precisa de MySQL 8.0.18 ou superior por causa do EXPLAIN ANALYZE.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Parte 0 - Preparacao (script do professor, sem alteracao)
-- -----------------------------------------------------------------------------
DROP DATABASE IF EXISTS lab_otimizacao;
CREATE DATABASE lab_otimizacao;
USE lab_otimizacao;

CREATE TABLE cliente (
  id     INT PRIMARY KEY,
  nome   VARCHAR(60) NOT NULL,
  cpf    VARCHAR(11) NOT NULL,
  cidade VARCHAR(30) NOT NULL
);

CREATE TABLE locacao (
  id             INT PRIMARY KEY,
  id_cliente     INT NOT NULL,
  id_veiculo     INT NOT NULL,
  data_retirada  DATE NOT NULL,
  valor          DECIMAL(8,2) NOT NULL,
  status         VARCHAR(10) NOT NULL
);

SET SESSION cte_max_recursion_depth = 1000000;

INSERT INTO cliente (id, nome, cpf, cidade)
WITH RECURSIVE seq AS (
  SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 50000
)
SELECT n,
       CONCAT('Cliente ', n),
       LPAD(n, 11, '0'),
       ELT(1 + n % 5, 'Brasilia', 'Goiania', 'Anapolis', 'Taguatinga', 'Gama')
FROM seq;

INSERT INTO locacao (id, id_cliente, id_veiculo, data_retirada, valor, status)
WITH RECURSIVE seq AS (
  SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 500000
)
SELECT n,
       1 + (n * 7919) % 50000,
       1 + (n * 31) % 200,
       DATE_ADD('2023-01-01', INTERVAL n % 1095 DAY),
       100 + n % 400,
       CASE WHEN n % 50 = 0 THEN 'cancelada'
            WHEN n % 4  = 0 THEN 'aberta'
            ELSE 'concluida' END
FROM seq;

ANALYZE TABLE cliente, locacao;

SELECT (SELECT COUNT(*) FROM cliente) AS clientes,
       (SELECT COUNT(*) FROM locacao) AS locacoes;

SHOW INDEX FROM locacao;   -- deve aparecer apenas PRIMARY

-- -----------------------------------------------------------------------------
-- Parte 1 - Diagnostico sem indices
-- -----------------------------------------------------------------------------
-- Q1
EXPLAIN SELECT * FROM locacao WHERE id_cliente = 4242;

-- Q2
EXPLAIN
SELECT c.nome, l.data_retirada, l.valor
FROM cliente c
JOIN locacao l ON l.id_cliente = c.id
WHERE c.cpf = '00000004242';

EXPLAIN ANALYZE SELECT * FROM locacao WHERE id_cliente = 4242;

-- Extra: tempo real da Q2 sem indice, para comparar com a Parte 2
EXPLAIN ANALYZE
SELECT c.nome, l.data_retirada, l.valor
FROM cliente c
JOIN locacao l ON l.id_cliente = c.id
WHERE c.cpf = '00000004242';

-- -----------------------------------------------------------------------------
-- Parte 2 - Criando indices e comparando
-- -----------------------------------------------------------------------------
CREATE INDEX idx_loc_cliente ON locacao(id_cliente);
CREATE INDEX idx_cli_cpf     ON cliente(cpf);
ANALYZE TABLE cliente, locacao;

EXPLAIN SELECT * FROM locacao WHERE id_cliente = 4242;

EXPLAIN
SELECT c.nome, l.data_retirada, l.valor
FROM cliente c
JOIN locacao l ON l.id_cliente = c.id
WHERE c.cpf = '00000004242';

EXPLAIN ANALYZE SELECT * FROM locacao WHERE id_cliente = 4242;

EXPLAIN ANALYZE
SELECT c.nome, l.data_retirada, l.valor
FROM cliente c
JOIN locacao l ON l.id_cliente = c.id
WHERE c.cpf = '00000004242';

-- Seletividade
CREATE INDEX idx_loc_status ON locacao(status);
ANALYZE TABLE locacao;

EXPLAIN SELECT * FROM locacao WHERE status = 'cancelada';
EXPLAIN SELECT * FROM locacao WHERE status = 'concluida';

-- Extra: tempo real dos dois filtros com o indice e sem ele
EXPLAIN ANALYZE SELECT * FROM locacao WHERE status = 'cancelada';
EXPLAIN ANALYZE SELECT * FROM locacao IGNORE INDEX (idx_loc_status)
WHERE status = 'cancelada';
EXPLAIN ANALYZE SELECT * FROM locacao WHERE status = 'concluida';
EXPLAIN ANALYZE SELECT * FROM locacao IGNORE INDEX (idx_loc_status)
WHERE status = 'concluida';

-- Extra: parcela real de cada status
SELECT status, COUNT(*) AS linhas,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM locacao), 1) AS pct
FROM locacao GROUP BY status;

-- -----------------------------------------------------------------------------
-- Parte 3 - Indices que o MySQL ignora
-- -----------------------------------------------------------------------------
CREATE INDEX idx_loc_data ON locacao(data_retirada);
CREATE INDEX idx_cli_nome ON cliente(nome);
ANALYZE TABLE cliente, locacao;

-- 3A antes: funcao na coluna
EXPLAIN SELECT * FROM locacao
WHERE DATE_FORMAT(data_retirada, '%Y-%m') = '2025-06';
-- 3A depois: faixa de datas, coluna sem funcao
EXPLAIN SELECT * FROM locacao
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';
-- Conferencia: as duas versoes devolvem o mesmo numero de linhas
SELECT
  (SELECT COUNT(*) FROM locacao
    WHERE DATE_FORMAT(data_retirada, '%Y-%m') = '2025-06') AS antes,
  (SELECT COUNT(*) FROM locacao
    WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01') AS depois;

-- 3B antes: curinga no inicio
EXPLAIN SELECT * FROM cliente WHERE nome LIKE '%123';
-- 3B depois: prefixo fixo
EXPLAIN SELECT * FROM cliente WHERE nome LIKE 'Cliente 123%';

-- 3C antes: VARCHAR comparado com numero
EXPLAIN SELECT * FROM cliente WHERE cpf = 4242;
SHOW WARNINGS;   -- mostra a consulta como o otimizador reescreveu
-- 3C depois: comparado com texto (o cpf e gravado com LPAD de 11 posicoes)
EXPLAIN SELECT * FROM cliente WHERE cpf = '00000004242';

-- -----------------------------------------------------------------------------
-- Parte 4 - Indice composto
-- -----------------------------------------------------------------------------
CREATE INDEX idx_loc_cli_data ON locacao(id_cliente, data_retirada);
ANALYZE TABLE locacao;

-- (a) filtra pelas duas colunas
EXPLAIN SELECT * FROM locacao
WHERE id_cliente = 4242 AND data_retirada >= '2025-01-01';

-- (b) filtra so pela segunda coluna do indice composto
EXPLAIN SELECT * FROM locacao
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';

-- Desafio: indice simples de data invisivel
ALTER TABLE locacao ALTER INDEX idx_loc_data INVISIBLE;
EXPLAIN SELECT * FROM locacao
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';
-- Extra: forcando o composto, para ver o que ele faria
EXPLAIN SELECT * FROM locacao FORCE INDEX (idx_loc_cli_data)
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';

-- Extra: consulta coberta pelo composto (so colunas do indice). Aqui o
-- MySQL consegue usar o composto mesmo sem a primeira coluna no filtro.
EXPLAIN SELECT id_cliente, data_retirada FROM locacao
WHERE data_retirada >= '2025-06-01' AND data_retirada < '2025-07-01';

-- volte ao normal
ALTER TABLE locacao ALTER INDEX idx_loc_data VISIBLE;

-- -----------------------------------------------------------------------------
-- Parte 5 - Custo dos indices na escrita (extra, sustenta a resposta 3)
-- -----------------------------------------------------------------------------
-- Mesma carga de 500 mil linhas em duas copias: uma so com a PRIMARY e
-- outra com os quatro indices secundarios que ficaram em locacao.
CREATE TABLE locacao_so_pk LIKE locacao;
ALTER TABLE locacao_so_pk DROP INDEX idx_loc_cliente, DROP INDEX idx_loc_status,
  DROP INDEX idx_loc_data, DROP INDEX idx_loc_cli_data;
CREATE TABLE locacao_com_indices LIKE locacao;

SET @t = NOW(6);
INSERT INTO locacao_so_pk SELECT * FROM locacao;
SET @ms_so_pk = TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)) / 1000;

SET @t = NOW(6);
INSERT INTO locacao_com_indices SELECT * FROM locacao;
SET @ms_com_indices = TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)) / 1000;

SET @t = NOW(6);
UPDATE locacao_so_pk SET data_retirada = data_retirada + INTERVAL 1 DAY;
SET @ms_upd_so_pk = TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)) / 1000;

SET @t = NOW(6);
UPDATE locacao_com_indices SET data_retirada = data_retirada + INTERVAL 1 DAY;
SET @ms_upd_com_indices = TIMESTAMPDIFF(MICROSECOND, @t, NOW(6)) / 1000;

SELECT @ms_so_pk AS insert_so_pk_ms, @ms_com_indices AS insert_com_indices_ms,
       @ms_upd_so_pk AS update_so_pk_ms, @ms_upd_com_indices AS update_com_indices_ms;

DROP TABLE locacao_so_pk, locacao_com_indices;

-- Tamanho dos dados e dos indices depois de todos os CREATE INDEX
SELECT table_name,
       ROUND(data_length  / 1024 / 1024, 1) AS dados_mb,
       ROUND(index_length / 1024 / 1024, 1) AS indices_mb
FROM information_schema.tables
WHERE table_schema = 'lab_otimizacao';
