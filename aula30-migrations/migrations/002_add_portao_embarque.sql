-- 002_add_portao_embarque.sql
-- No projeto a tabela e voo (singular). Ela ja tem portao desde a Aula 10;
-- portao_embarque e a coluna do exercicio e nenhum codigo usa.
-- up
ALTER TABLE voo ADD COLUMN portao_embarque VARCHAR(5) NULL;

-- down
ALTER TABLE voo DROP COLUMN portao_embarque;
