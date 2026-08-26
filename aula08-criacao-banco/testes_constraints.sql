-- =============================================================================
-- Aula 08 - Verificacao das constraints
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Cada comando abaixo DEVE falhar. O objetivo e provar que as regras de negocio
-- do modelo estao no banco, e nao so na aplicacao.
--
-- Rodar com a flag --force para o cliente nao parar no primeiro erro:
--     mysql -u root -p --force aeroporto < testes_constraints.sql
--
-- Rodar depois de aeroporto.sql.
-- =============================================================================

USE aeroporto;

-- 1. Mesmo passageiro em dois assentos no mesmo voo.
--    Bloqueado por uq_passagem_passageiro_voo. Era o desafio da Aula 05.
INSERT INTO passagem (id_passageiro, id_voo, assento, localizador)
VALUES (1, 1, '20A', 'XXX001');

-- 2. Dois passageiros no mesmo assento do mesmo voo.
--    Bloqueado por uq_passagem_voo_assento.
INSERT INTO passagem (id_passageiro, id_voo, assento, localizador)
VALUES (5, 1, '12A', 'XXX002');

-- 3. Passagem para um voo que nao existe.
--    Bloqueado pela chave estrangeira fk_passagem_voo.
INSERT INTO passagem (id_passageiro, id_voo, assento, localizador)
VALUES (1, 999, '10A', 'XXX003');

-- 4. Voo com aeronave inexistente.
--    Bloqueado pela chave estrangeira fk_voo_aeronave.
INSERT INTO voo (numero_voo, id_aeronave, origem, destino, data_hora_partida, status)
VALUES ('999', 77, 'BSB', 'GRU', '2026-09-05 09:00:00', 'Confirmado');

-- 5. Status fora do dominio previsto.
--    Bloqueado por ck_voo_status.
INSERT INTO voo (numero_voo, id_aeronave, origem, destino, data_hora_partida, status)
VALUES ('888', 1, 'BSB', 'GRU', '2026-09-05 10:00:00', 'embarcando');

-- 6. Voo com origem igual ao destino.
--    Bloqueado por ck_voo_rota.
INSERT INTO voo (numero_voo, id_aeronave, origem, destino, data_hora_partida, status)
VALUES ('777', 1, 'BSB', 'BSB', '2026-09-05 11:00:00', 'Confirmado');

-- 7. Mesmo numero de voo no mesmo horario.
--    Bloqueado por uq_voo_numero_partida.
INSERT INTO voo (numero_voo, id_aeronave, origem, destino, data_hora_partida, status)
VALUES ('305', 3, 'CGH', 'BSB', '2026-09-01 08:30:00', 'Confirmado');

-- 8. CPF duplicado.
--    Bloqueado por uq_passageiro_cpf.
INSERT INTO passageiro (cpf, nome) VALUES ('11122233344', 'Clone da Ana');

-- 9. Apagar uma aeronave que ainda tem voos.
--    Bloqueado pelo ON DELETE RESTRICT da fk_voo_aeronave.
DELETE FROM aeronave WHERE id_aeronave = 1;

-- 10. Aeronave com capacidade zero.
--     Bloqueado por ck_aeronave_capacidade.
INSERT INTO aeronave (prefixo, modelo, fabricante, capacidade_assentos)
VALUES ('PR-ZZZ', 'Planador', 'Nenhum', 0);


-- =============================================================================
-- Os comandos abaixo DEVEM funcionar. Servem de contraprova: as constraints
-- bloqueiam o que e invalido sem bloquear o que e valido.
-- =============================================================================

-- 11. Segundo passageiro estrangeiro, tambem sem CPF.
--     Varios NULL nao conflitam com a constraint UNIQUE, porque NULL nao e
--     igual a NULL.
INSERT INTO passageiro (cpf, nome) VALUES (NULL, 'Yuki Tanaka');

-- 12. Mesmo passageiro em outro voo. O N:N permite.
INSERT INTO passagem (id_passageiro, id_voo, assento, localizador)
VALUES (1, 2, '30A', 'XXX011');

-- 13. Mesmo assento, mas em voo diferente.
INSERT INTO passagem (id_passageiro, id_voo, assento, localizador)
VALUES (6, 2, '12A', 'XXX012');

-- Conferindo o que entrou nos tres ultimos comandos
SELECT 'Registros validos inseridos' AS verificacao;
SELECT nome FROM passageiro WHERE cpf IS NULL;
SELECT localizador, id_passageiro, id_voo, assento
FROM passagem
WHERE localizador LIKE 'XXX%';
