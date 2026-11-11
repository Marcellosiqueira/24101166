-- 004_drop_origem.sql
-- Contrair, num ALTER TABLE so (uma instrucao):
--   1. aeroporto_origem vira NOT NULL, como origem era. Se o backfill nao
--      rodou, o MySQL recusa (erro 1138, testado) e nada e removido.
--   2. as CHECK antigas saem. Sem isso o DROP COLUMN falha (erro 3959:
--      coluna usada em CHECK). As equivalentes em aeroporto_origem ja foram
--      criadas na 003.
--   3. origem sai.
-- up
ALTER TABLE rota
    MODIFY aeroporto_origem CHAR(3) NOT NULL,
    DROP CHECK ck_rota_origem_destino,
    DROP CHECK ck_rota_origem_iata,
    DROP COLUMN origem;

-- down
-- Volta a estrutura de antes da 004: origem NULL (os valores nao voltam), as
-- CHECK antigas de volta em origem e aeroporto_origem aceitando NULL.
ALTER TABLE rota
    ADD COLUMN origem CHAR(3) NULL AFTER numero_voo,
    MODIFY aeroporto_origem CHAR(3) NULL,
    ADD CONSTRAINT ck_rota_origem_destino CHECK (origem <> destino),
    ADD CONSTRAINT ck_rota_origem_iata
        CHECK (REGEXP_LIKE(origem, '^[A-Z]{3}$', 'c'));
