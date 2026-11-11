-- 003_add_aeroporto_origem.sql
-- Expandir, num ALTER TABLE so (uma instrucao):
--   1. aeroporto_origem com o mesmo tipo de origem: codigo IATA CHAR(3), em
--      rota, que e onde origem mora desde a Aula 09.
--   2. origem passa a aceitar NULL, para o codigo poder parar de grava-la
--      antes da 004 (passo 3c no README).
--   3. as regras de origem ja valem para aeroporto_origem. A partir do passo
--      3c so a coluna nova e gravada, e as CHECK antigas, em origem, nao a
--      protegem. NULL passa nas duas, entao as linhas antigas nao atrapalham.
-- up
ALTER TABLE rota
    ADD COLUMN aeroporto_origem CHAR(3) NULL AFTER origem,
    MODIFY origem CHAR(3) NULL,
    ADD CONSTRAINT ck_rota_aeroporto_origem_destino
        CHECK (aeroporto_origem <> destino),
    ADD CONSTRAINT ck_rota_aeroporto_origem_iata
        CHECK (REGEXP_LIKE(aeroporto_origem, '^[A-Z]{3}$', 'c'));

-- down
-- origem volta a NOT NULL; falha se o codigo novo ja gravou rota sem origem.
ALTER TABLE rota
    DROP CHECK ck_rota_aeroporto_origem_destino,
    DROP CHECK ck_rota_aeroporto_origem_iata,
    DROP COLUMN aeroporto_origem,
    MODIFY origem CHAR(3) NOT NULL;
