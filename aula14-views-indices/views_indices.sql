-- =============================================================================
-- Aula 14 - Views e Indices
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Aplicado sobre o banco criado por aula10-integridade/sql_integridade.sql.
-- A analise, os formularios e as medicoes estao em views_indices.md.
--
-- Re-executavel: as views usam CREATE OR REPLACE, o indice e removido antes de
-- ser recriado se ja existir, e a tabela de laboratorio usa DROP IF EXISTS.
--
-- Ordem de execucao:
--   mysql -u root -p < ../aula10-integridade/sql_integridade.sql
--   mysql -u root -p < views_indices.sql
--
-- Testado em MySQL 8.0.46.
-- =============================================================================

USE aeroporto;


-- -----------------------------------------------------------------------------
-- 1. vw_painel_voos - view com JOIN
-- -----------------------------------------------------------------------------
-- Junta as quatro tabelas que a normalizacao da Aula 09 separou, devolvendo o
-- painel de voos numa leitura so.
--
-- ALGORITHM = TEMPTABLE torna a view NAO atualizavel. Sem ele, o MySQL a
-- classificaria como atualizavel (IS_UPDATABLE = YES), porque aceita UPDATE e
-- INSERT em view com INNER JOIN desde que o comando atinja uma unica tabela.
-- Isso foi verificado antes de escrever esta view, e o efeito e perigoso num
-- painel: um UPDATE ... SET modelo = ... pedido para um voo alteraria
-- modelo_aeronave e renomearia o modelo de TODOS os voos daquela aeronave.
-- Painel e leitura; a escrita vai para as tabelas de origem.
--
-- O custo do TEMPTABLE e materializar o resultado. O EXPLAIN mostra que o MySQL
-- 8 ainda empurra um WHERE externo para dentro da materializacao: um filtro por
-- status e aplicado direto em voo, onde um indice pode ser usado.
--
-- Tentativa de escrita:
--   UPDATE vw_painel_voos SET portao = '99' WHERE numero_voo = '420';
--   ERROR 1288 (HY000): The target table vw_painel_voos of the UPDATE is not updatable

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


-- -----------------------------------------------------------------------------
-- 2. vw_ocupacao_voo - view com agregacao
-- -----------------------------------------------------------------------------
-- Uma linha por voo: passagens vendidas, capacidade, assentos livres e
-- percentual de ocupacao.
--
-- LEFT JOIN em passagem: um voo sem nenhuma passagem vendida precisa aparecer
-- com zero. Com JOIN simples ele sumiria do resultado. COUNT(pg.id_passagem), e
-- nao COUNT(*), para que a linha nula gerada pelo LEFT JOIN conte zero.
--
-- NULLIF no divisor: ck_aeronave_capacidade ja impede capacidade zero, entao a
-- divisao por zero nao acontece com os dados atuais. O NULLIF fica porque a
-- view nao deve depender de uma constraint de outra tabela para nao quebrar:
-- se a regra for afrouxada um dia, o percentual vira NULL em vez de erro.
--
-- Nao e atualizavel: GROUP BY e funcao de agregacao impedem que uma linha da
-- view corresponda a uma linha de tabela.

CREATE OR REPLACE VIEW vw_ocupacao_voo AS
SELECT v.id_voo,
       r.numero_voo,
       v.data_hora_partida,
       a.prefixo,
       a.capacidade_assentos,
       COUNT(pg.id_passagem)                         AS passagens_vendidas,
       a.capacidade_assentos - COUNT(pg.id_passagem) AS assentos_livres,
       ROUND(100 * COUNT(pg.id_passagem)
                 / NULLIF(a.capacidade_assentos, 0), 1) AS ocupacao_pct
  FROM voo v
  JOIN rota r           ON r.id_rota     = v.id_rota
  JOIN aeronave a       ON a.id_aeronave = v.id_aeronave
  LEFT JOIN passagem pg ON pg.id_voo     = v.id_voo
 GROUP BY v.id_voo, r.numero_voo, v.data_hora_partida,
          a.prefixo, a.capacidade_assentos;


-- -----------------------------------------------------------------------------
-- 3. vw_passagens_pendentes_checkin - view simples, atualizavel, com CHECK OPTION
-- -----------------------------------------------------------------------------
-- Passagens que ainda nao fizeram check-in. Uma tabela so, sem agregacao, sem
-- DISTINCT, com a chave primaria id_passagem no SELECT e todas as colunas como
-- referencia direta: o MySQL a trata como atualizavel.
--
-- WITH CHECK OPTION impede que uma escrita feita pela view produza uma linha
-- que a propria view nao mostraria. O MySQL registra a clausula como CASCADED.
--
-- Demonstracao, executada no MySQL 8.0.46 dentro de transacao com ROLLBACK:
--
--   -- PASSA: a passagem continua pendente depois da alteracao.
--   UPDATE vw_passagens_pendentes_checkin SET assento = '01C' WHERE id_passagem = 3;
--   -- Query OK, 1 row affected
--
--   -- BLOQUEADO: a linha sairia do filtro checkin_realizado = FALSE.
--   UPDATE vw_passagens_pendentes_checkin SET checkin_realizado = TRUE WHERE id_passagem = 3;
--   -- ERROR 1369 (HY000): CHECK OPTION failed 'aeroporto.vw_passagens_pendentes_checkin'
--
-- Consequencia de projeto: o check-in em si nao se faz por esta view. Ela serve
-- para listar e corrigir passagens pendentes; marcar o check-in e escrita na
-- tabela passagem.

CREATE OR REPLACE VIEW vw_passagens_pendentes_checkin AS
SELECT id_passagem,
       id_passageiro,
       id_voo,
       assento,
       localizador,
       classe,
       checkin_realizado
  FROM passagem
 WHERE checkin_realizado = FALSE
WITH CHECK OPTION;

SELECT table_name, is_updatable, check_option
  FROM information_schema.views
 WHERE table_schema = 'aeroporto'
 ORDER BY table_name;


-- -----------------------------------------------------------------------------
-- 4. idx_voo_status - indice na tabela real
-- -----------------------------------------------------------------------------
-- Consulta alvo: voos filtrados por status, o painel "voos em embarque" da
-- Aula 04 levado para o banco.
--
-- O MySQL 8.0 nao tem DROP INDEX IF EXISTS. O bloco abaixo consulta o
-- dicionario e so remove o indice se ele existir, para o arquivo poder rodar
-- mais de uma vez e o EXPLAIN "antes" ser sempre de fato sem o indice.

SET @existe := (SELECT COUNT(*) FROM information_schema.statistics
                 WHERE table_schema = 'aeroporto'
                   AND table_name   = 'voo'
                   AND index_name   = 'idx_voo_status');
SET @sql := IF(@existe > 0, 'DROP INDEX idx_voo_status ON voo', 'DO 0');
PREPARE s FROM @sql;
EXECUTE s;
DEALLOCATE PREPARE s;

-- EXPLAIN antes
EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo WHERE status = 'Embarque';

CREATE INDEX idx_voo_status ON voo (status);
ANALYZE TABLE voo;

-- EXPLAIN depois
EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo WHERE status = 'Embarque';

-- Resultado registrado em views_indices.md: com 8 linhas o otimizador passou a
-- usar o indice (type ref), mas sem ganho de tempo mensuravel.


-- -----------------------------------------------------------------------------
-- 5. Laboratorio de volume - voo_teste
-- -----------------------------------------------------------------------------
-- Mesma estrutura de voo, sem FK e sem indice secundario, com 200 mil linhas
-- geradas por WITH RECURSIVE. Duas distribuicoes de status, para mostrar que o
-- ganho depende da seletividade e nao so do tamanho da tabela:
--
--   5.1 uniforme  cada status com 25% das linhas
--   5.2 desigual  'Cancelado' com 0,5%, o caso realista
--
-- A consulta filtra 'Cancelado' nos dois casos. As medicoes de tempo
-- (performance_schema, 30 execucoes por fase) estao em views_indices.md, com o
-- procedimento usado.
--
-- cte_max_recursion_depth vale 1000 por padrao; a CTE precisa de 200 mil
-- niveis.

SET SESSION cte_max_recursion_depth = 200000;

-- 5.1 Distribuicao uniforme ---------------------------------------------------

DROP TABLE IF EXISTS voo_teste;

CREATE TABLE voo_teste (
    id_voo                     INT AUTO_INCREMENT PRIMARY KEY,
    id_rota                    INT         NOT NULL,
    id_aeronave                INT         NOT NULL,
    data_hora_partida          DATETIME    NOT NULL,
    data_hora_chegada_prevista DATETIME    NULL,
    portao                     VARCHAR(5)  NULL,
    status                     VARCHAR(20) NOT NULL DEFAULT 'Aguardando',

    CONSTRAINT ck_voo_teste_status CHECK (status IN ('Embarque', 'Confirmado',
                                                     'Aguardando', 'Cancelado'))
) ENGINE = InnoDB;

INSERT INTO voo_teste (id_rota, id_aeronave, data_hora_partida,
                       data_hora_chegada_prevista, portao, status)
WITH RECURSIVE seq (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 200000
)
SELECT (n % 7) + 1,
       (n % 6) + 1,
       TIMESTAMP('2026-01-01 00:00:00') + INTERVAL n MINUTE,
       TIMESTAMP('2026-01-01 00:00:00') + INTERVAL (n + 100) MINUTE,
       LPAD((n % 30) + 1, 2, '0'),
       CASE n % 4
           WHEN 0 THEN 'Cancelado'
           WHEN 1 THEN 'Confirmado'
           WHEN 2 THEN 'Aguardando'
           ELSE        'Embarque'
       END
  FROM seq;

ANALYZE TABLE voo_teste;

SELECT status, COUNT(*) AS linhas,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM voo_teste), 2) AS pct
  FROM voo_teste GROUP BY status ORDER BY linhas;

EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo_teste WHERE status = 'Cancelado';

CREATE INDEX idx_voo_teste_status ON voo_teste (status);
ANALYZE TABLE voo_teste;

EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo_teste WHERE status = 'Cancelado';

-- 5.2 Distribuicao desigual ---------------------------------------------------

DROP TABLE IF EXISTS voo_teste;

CREATE TABLE voo_teste (
    id_voo                     INT AUTO_INCREMENT PRIMARY KEY,
    id_rota                    INT         NOT NULL,
    id_aeronave                INT         NOT NULL,
    data_hora_partida          DATETIME    NOT NULL,
    data_hora_chegada_prevista DATETIME    NULL,
    portao                     VARCHAR(5)  NULL,
    status                     VARCHAR(20) NOT NULL DEFAULT 'Aguardando',

    CONSTRAINT ck_voo_teste_status CHECK (status IN ('Embarque', 'Confirmado',
                                                     'Aguardando', 'Cancelado'))
) ENGINE = InnoDB;

INSERT INTO voo_teste (id_rota, id_aeronave, data_hora_partida,
                       data_hora_chegada_prevista, portao, status)
WITH RECURSIVE seq (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 200000
)
SELECT (n % 7) + 1,
       (n % 6) + 1,
       TIMESTAMP('2026-01-01 00:00:00') + INTERVAL n MINUTE,
       TIMESTAMP('2026-01-01 00:00:00') + INTERVAL (n + 100) MINUTE,
       LPAD((n % 30) + 1, 2, '0'),
       CASE
           WHEN n % 200 = 0 THEN 'Cancelado'
           WHEN n % 10  < 5 THEN 'Confirmado'
           WHEN n % 10  < 8 THEN 'Aguardando'
           ELSE                  'Embarque'
       END
  FROM seq;

ANALYZE TABLE voo_teste;

SELECT status, COUNT(*) AS linhas,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM voo_teste), 2) AS pct
  FROM voo_teste GROUP BY status ORDER BY linhas;

EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo_teste WHERE status = 'Cancelado';

CREATE INDEX idx_voo_teste_status ON voo_teste (status);
ANALYZE TABLE voo_teste;

EXPLAIN SELECT id_voo, id_rota, portao, data_hora_partida
          FROM voo_teste WHERE status = 'Cancelado';

-- 5.3 Limpeza ----------------------------------------------------------------
-- voo_teste e tabela de laboratorio com dados sinteticos; nao fica no schema do
-- projeto. Para repetir as medicoes, rode de novo a secao 5.2 sem esta linha.

DROP TABLE IF EXISTS voo_teste;


-- -----------------------------------------------------------------------------
-- 6. Como a medicao foi feita (referencia, nao executado aqui)
-- -----------------------------------------------------------------------------
-- Para cada fase (antes e depois do indice):
--
--   TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;
--   TRUNCATE TABLE performance_schema.table_io_waits_summary_by_index_usage;
--
--   -- a consulta testada, 30 vezes, na mesma sessao
--   SELECT id_voo, id_rota, portao, data_hora_partida FROM voo WHERE status = 'Embarque';
--
--   SELECT COUNT_STAR,
--          ROUND(AVG_TIMER_WAIT / 1000000000, 4) AS media_ms,
--          SUM_ROWS_EXAMINED, SUM_NO_INDEX_USED
--     FROM performance_schema.events_statements_summary_by_digest
--    WHERE SCHEMA_NAME = 'aeroporto'
--      AND DIGEST_TEXT LIKE 'SELECT %FROM `voo` WHERE STATUS = ?%'
--      AND DIGEST_TEXT NOT LIKE '%performance_schema%';
--
--   SELECT INDEX_NAME, COUNT_READ, COUNT_FETCH
--     FROM performance_schema.table_io_waits_summary_by_index_usage
--    WHERE OBJECT_SCHEMA = 'aeroporto' AND OBJECT_NAME = 'voo';
--
-- No DIGEST_TEXT o MySQL escreve status como palavra-chave, STATUS, sem crases.
-- Um filtro com `status` entre crases nao encontra nada.


-- -----------------------------------------------------------------------------
-- 7. Conferencia
-- -----------------------------------------------------------------------------

SHOW INDEX FROM voo;

SELECT * FROM vw_painel_voos;
SELECT * FROM vw_ocupacao_voo;
SELECT * FROM vw_passagens_pendentes_checkin;
