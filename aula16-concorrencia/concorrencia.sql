-- =============================================================================
-- Aula 16 - Locking, Deadlocks e MVCC
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco: aeroporto_concorrencia
--
-- Esquema, dados de teste e procedimento de reserva. Os experimentos com duas
-- sessoes simultaneas, os resultados medidos e as respostas das perguntas
-- estao em concorrencia.md.
--
--   mysql -u root -p < concorrencia.sql
--
-- POR QUE UM BANCO SEPARADO, E NAO O aeroporto DAS OUTRAS AULAS
--
-- Este arquivo usa o esquema sugerido pelo professor (secao 5 do enunciado),
-- nao o modelo individual. O motivo esta explicado em detalhe em
-- concorrencia.md, secao 1, e em resumo e este: o exercicio inteiro gira em
-- torno de bloquear a LINHA de um assento e ler o seu status, e no modelo
-- individual o assento nao e uma entidade - e uma coluna de texto dentro de
-- passagem. Nao existe linha de assento para bloquear.
--
-- O banco e criado com outro nome para nao sobrescrever o aeroporto, que as
-- Aulas 08 a 15 constroem e do qual a Aula 15 depende.
--
-- ADAPTACOES DE POSTGRESQL PARA MYSQL 8 (o enunciado pede que sejam feitas)
--
--   BIGSERIAL            -> BIGINT AUTO_INCREMENT. Em MySQL o contador e
--                           propriedade da coluna, nao um objeto SEQUENCE
--                           separado.
--   TIMESTAMP            -> DATETIME em data_hora_saida e data_reserva. O
--                           TIMESTAMP do MySQL nao e o TIMESTAMP do
--                           PostgreSQL: tem faixa limitada (1970-2038) e
--                           converte para UTC e de volta conforme o fuso da
--                           sessao. DATETIME guarda o valor literal, que e o
--                           comportamento esperado aqui.
--   (sem clausula)       -> ENGINE = InnoDB explicito. E o padrao no MySQL 8,
--                           mas nada nesta aula funciona sem ele: MyISAM nao
--                           tem transacao, nem bloqueio de linha, nem MVCC, e
--                           FOR UPDATE seria aceito e ignorado.
--   indice unico parcial -> coluna gerada + UNIQUE. Ver secao 5 abaixo.
--   RETURNING            -> ROW_COUNT() depois do UPDATE. Ver secao 6.
--
--   Nivel de isolamento padrao: REPEATABLE READ no MySQL, READ COMMITTED no
--   PostgreSQL. Nao e uma adaptacao de sintaxe, e uma diferenca de
--   comportamento, e muda a analise do Experimento E (MVCC). Registrada aqui
--   e desenvolvida em concorrencia.md, secao 6.
--
-- Testado em MySQL 8.0.46 (contêiner Docker mysql:8.0).
-- =============================================================================

DROP DATABASE IF EXISTS aeroporto_concorrencia;

CREATE DATABASE aeroporto_concorrencia
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE aeroporto_concorrencia;


-- -----------------------------------------------------------------------------
-- 1. aeronaves
-- -----------------------------------------------------------------------------

CREATE TABLE aeronaves (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    fabricante          VARCHAR(100) NOT NULL,
    modelo              VARCHAR(100) NOT NULL,
    quantidade_assentos INT          NOT NULL,

    CONSTRAINT ck_aeronave_assentos CHECK (quantidade_assentos > 0)
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 2. voos
-- -----------------------------------------------------------------------------
-- CHECK de dominio em status acrescentado ao esquema do enunciado, que declara
-- a coluna apenas como VARCHAR com DEFAULT. Sem o CHECK, 'PROGRAMADOO' entra
-- no banco. E a mesma decisao da Aula 10: dominio controlado fica no SGBD.

CREATE TABLE voos (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    codigo          VARCHAR(20) NOT NULL UNIQUE,
    origem          VARCHAR(100) NOT NULL,
    destino         VARCHAR(100) NOT NULL,
    data_hora_saida DATETIME     NOT NULL,
    aeronave_id     BIGINT       NOT NULL,
    status          VARCHAR(30)  NOT NULL DEFAULT 'PROGRAMADO',

    CONSTRAINT fk_voo_aeronave
        FOREIGN KEY (aeronave_id) REFERENCES aeronaves (id),

    CONSTRAINT ck_voo_status
        CHECK (status IN ('PROGRAMADO', 'EMBARQUE', 'ENCERRADO', 'CANCELADO'))
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 3. passageiros
-- -----------------------------------------------------------------------------

CREATE TABLE passageiros (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    nome       VARCHAR(150) NOT NULL,
    documento  VARCHAR(30)  NOT NULL UNIQUE
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 4. assentos
-- -----------------------------------------------------------------------------
-- E a tabela central do exercicio: e a LINHA de assento que as duas sessoes
-- disputam, e e ela que FOR UPDATE bloqueia.
--
-- CHECK de dominio em status acrescentado, com os tres valores que o enunciado
-- lista na secao 3.4.
--
-- uq_assento_voo (voo_id, numero) vem do enunciado e e o equivalente exato da
-- UNIQUE (id_voo, assento) que o modelo individual tem desde a Aula 08.

CREATE TABLE assentos (
    id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    voo_id  BIGINT      NOT NULL,
    numero  VARCHAR(10) NOT NULL,
    classe  VARCHAR(30) NOT NULL DEFAULT 'ECONOMICA',
    status  VARCHAR(30) NOT NULL DEFAULT 'DISPONIVEL',

    CONSTRAINT fk_assento_voo
        FOREIGN KEY (voo_id) REFERENCES voos (id),

    CONSTRAINT uq_assento_voo UNIQUE (voo_id, numero),

    CONSTRAINT ck_assento_status
        CHECK (status IN ('DISPONIVEL', 'RESERVADO', 'BLOQUEADO'))
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 5. reservas
-- -----------------------------------------------------------------------------
-- ADAPTACAO: o indice unico parcial do enunciado (secao 13),
--
--     CREATE UNIQUE INDEX uq_reserva_assento_ativa
--     ON reservas (assento_id) WHERE status = 'CONFIRMADA';
--
-- nao existe no MySQL 8: a clausula WHERE em CREATE INDEX e especifica do
-- PostgreSQL. O MySQL nao tem indice parcial nem indice com predicado.
--
-- A substituicao e uma COLUNA GERADA que devolve assento_id quando a reserva
-- esta CONFIRMADA e NULL caso contrario, com UNIQUE sobre ela:
--
--     assento_ativo = IF(status = 'CONFIRMADA', assento_id, NULL)
--
-- Por que funciona: no padrao SQL, e no MySQL, um indice UNIQUE aceita varios
-- NULL sem conflito - dois NULL nao sao considerados iguais entre si. Entao as
-- reservas CANCELADAS, que viram NULL na coluna gerada, ficam todas fora da
-- restricao, e sobra exatamente uma reserva CONFIRMADA possivel por assento.
-- E o mesmo comportamento do NULL que a Aula 10 usou para permitir varios
-- passageiros estrangeiros sem CPF sob uma UNIQUE (cpf).
--
-- STORED e nao VIRTUAL: o valor e gravado, o que deixa o indice unico
-- independente de recalculo na leitura. A coluna e mantida pelo SGBD, nao pela
-- aplicacao: cancelar uma reserva (UPDATE status = 'CANCELADA') libera o
-- assento para uma nova reserva automaticamente.
--
-- Esta restricao e a ULTIMA barreira da estrategia em camadas: ela vale mesmo
-- para um cliente que nao use o procedimento, nao abra transacao e nao bloqueie
-- nada. O Experimento A2 mostra ela agindo sozinha, com erro 1062.

CREATE TABLE reservas (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    passageiro_id BIGINT      NOT NULL,
    assento_id    BIGINT      NOT NULL,
    data_reserva  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        VARCHAR(30) NOT NULL DEFAULT 'CONFIRMADA',

    assento_ativo BIGINT AS (IF(status = 'CONFIRMADA', assento_id, NULL)) STORED,

    CONSTRAINT fk_reserva_passageiro
        FOREIGN KEY (passageiro_id) REFERENCES passageiros (id),

    CONSTRAINT fk_reserva_assento
        FOREIGN KEY (assento_id) REFERENCES assentos (id),

    CONSTRAINT uq_reserva_assento_ativa UNIQUE (assento_ativo),

    CONSTRAINT ck_reserva_status
        CHECK (status IN ('CONFIRMADA', 'CANCELADA'))
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 6. sp_reservar_assento - procedimento de reserva
-- -----------------------------------------------------------------------------
-- Atende aos 12 itens da secao 21 do enunciado. O mapeamento item a item esta
-- comentado dentro do corpo.
--
-- ESTRATEGIA EM CAMADAS (detalhada em concorrencia.md, secao 3):
--   1. Bloqueio pessimista    SELECT ... FOR UPDATE serializa os concorrentes
--   2. Revalidacao pos-lock   o status e relido DEPOIS do bloqueio
--   3. UPDATE condicional     WHERE status = 'DISPONIVEL' + ROW_COUNT()
--   4. UNIQUE da coluna gerada  barreira final, vale fora do procedimento
--
-- ADAPTACAO: o RETURNING do PostgreSQL (secao 12 do enunciado) nao existe no
-- MySQL. O equivalente e ROW_COUNT(), que devolve quantas linhas o ultimo
-- comando alterou. ROW_COUNT() = 1 significa que o UPDATE condicional
-- encontrou o assento ainda DISPONIVEL; 0 significa que alguem chegou antes.
-- ROW_COUNT() precisa ser lido IMEDIATAMENTE apos o UPDATE, porque qualquer
-- outro comando no meio o sobrescreve - por isso a atribuicao a v_linhas e a
-- primeira instrucao depois do UPDATE.

DELIMITER $$

CREATE PROCEDURE sp_reservar_assento(
    IN p_passageiro_id BIGINT,   -- item 1: recebe o ID do passageiro
    IN p_voo_id        BIGINT,   -- item 2: recebe o ID do voo
    IN p_numero        VARCHAR(10)  -- item 3: recebe o numero do assento
)
BEGIN
    DECLARE v_assento_id BIGINT      DEFAULT NULL;
    DECLARE v_status     VARCHAR(30) DEFAULT NULL;
    DECLARE v_linhas     INT         DEFAULT 0;
    DECLARE v_msg        VARCHAR(255);

    -- Item 11: ROLLBACK quando houver erro.
    --
    -- EXIT HANDLER FOR SQLEXCEPTION pega QUALQUER erro do bloco: os SIGNAL
    -- lancados aqui dentro, a violacao da UNIQUE (1062), o deadlock (1213) e o
    -- estouro do tempo de espera por bloqueio (1205). O handler desfaz a
    -- transacao e RESIGNAL repassa o erro original ao cliente, com o codigo e a
    -- mensagem intactos. Sem o RESIGNAL, o procedimento engoliria a falha e o
    -- cliente acharia que a reserva deu certo - que e o pior desfecho possivel
    -- num sistema de reservas.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Item 6: utilize uma transacao.
    START TRANSACTION;

    -- Itens 4, 5 e 7: verifica se o assento existe, le o status e protege a
    -- linha contra atualizacoes concorrentes na MESMA instrucao.
    --
    -- FOR UPDATE adquire um bloqueio exclusivo sobre a linha do assento. A
    -- partir daqui, qualquer outra sessao que tente ler esta mesma linha com
    -- FOR UPDATE (ou altera-la) fica esperando ate esta transacao dar COMMIT ou
    -- ROLLBACK.
    --
    -- O WHERE NAO inclui "AND status = 'DISPONIVEL'", diferente do exemplo do
    -- enunciado. Com o filtro de status, um assento ja reservado nao retornaria
    -- linha, nao seria bloqueado, e o procedimento nao teria como distinguir
    -- "assento nao existe" de "assento existe e esta ocupado". Bloqueia-se a
    -- linha primeiro e decide-se depois - que e o proprio ponto da revalidacao.
    SELECT id, status
      INTO v_assento_id, v_status
      FROM assentos
     WHERE voo_id = p_voo_id
       AND numero = p_numero
     FOR UPDATE;

    -- ARMADILHA DO MySQL, e o motivo deste IF existir:
    -- SELECT ... INTO que nao encontra nenhuma linha NAO e erro no MySQL. Gera
    -- apenas o aviso 1329 (No data - zero rows fetched), as variaveis ficam
    -- como estavam e a execucao SEGUE NORMALMENTE. Em PL/pgSQL isso levantaria
    -- NO_DATA_FOUND e o EXIT HANDLER tomaria conta. Aqui nao: sem este teste, o
    -- procedimento continuaria com v_assento_id NULL, o UPDATE nao acharia
    -- nada e o INSERT falharia por FK - um erro confuso, muito depois da causa.
    -- Por isso v_assento_id nasce com DEFAULT NULL e e testado explicitamente.
    IF v_assento_id IS NULL THEN
        SET v_msg = CONCAT('Assento ', p_numero, ' nao existe no voo ', p_voo_id);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- Item 5: revalidacao DEPOIS do bloqueio.
    --
    -- Esta e a linha mais importante do procedimento sob concorrencia. Uma
    -- sessao que ficou esperando o bloqueio chega aqui APOS o COMMIT da
    -- concorrente, e o valor de v_status ja e o novo ('RESERVADO'), nao o que
    -- existia quando ela comecou a esperar. Isso vale porque, no MySQL, uma
    -- leitura bloqueante (FOR UPDATE) le a versao confirmada mais recente e nao
    -- o retrato da transacao - ponto demonstrado no Experimento E.
    IF v_status <> 'DISPONIVEL' THEN
        SET v_msg = CONCAT('Assento ', p_numero, ' do voo ', p_voo_id,
                           ' nao esta disponivel (status atual: ', v_status, ')');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- Item 8: atualiza o status do assento.
    --
    -- UPDATE CONDICIONAL: o "AND status = 'DISPONIVEL'" e redundante DEPOIS do
    -- FOR UPDATE, e esta aqui de proposito. Se um dia o FOR UPDATE for removido
    -- por engano, ou se este bloco for copiado para outro lugar sem ele, o
    -- UPDATE condicional sozinho ainda fecha a janela entre a leitura e a
    -- escrita: o UPDATE bloqueia a linha e rele a versao atual antes de aplicar
    -- o SET. Defesa em profundidade custa uma comparacao.
    UPDATE assentos
       SET status = 'RESERVADO'
     WHERE id = v_assento_id
       AND status = 'DISPONIVEL';

    SET v_linhas = ROW_COUNT();   -- substituto do RETURNING do PostgreSQL

    IF v_linhas <> 1 THEN
        SET v_msg = CONCAT('Assento ', p_numero, ' do voo ', p_voo_id,
                           ' foi ocupado por outra transacao');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- Item 9: insere a reserva.
    -- Item 12: a duplicidade e impedida em quatro camadas, e a ultima delas e a
    -- UNIQUE (assento_ativo) que este INSERT atravessa.
    INSERT INTO reservas (passageiro_id, assento_id, status)
    VALUES (p_passageiro_id, v_assento_id, 'CONFIRMADA');

    -- Item 10: confirma a transacao somente no fim, quando todas as etapas
    -- foram concluidas. Ate aqui, qualquer falha caiu no EXIT HANDLER e
    -- desfez tudo - inclusive o UPDATE do assento, que nao fica RESERVADO sem
    -- uma reserva correspondente.
    COMMIT;
END$$


-- -----------------------------------------------------------------------------
-- 7. sp_resetar_cenario - volta o banco ao estado inicial
-- -----------------------------------------------------------------------------
-- Cada experimento de concorrencia precisa comecar com os tres assentos
-- DISPONIVEL e nenhuma reserva. Chamar este procedimento entre os experimentos
-- torna o roteiro do concorrencia.md reproduzivel na ordem em que esta escrito.

CREATE PROCEDURE sp_resetar_cenario()
BEGIN
    DELETE FROM reservas;
    UPDATE assentos SET status = 'DISPONIVEL';
    ALTER TABLE reservas AUTO_INCREMENT = 1;
END$$

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 8. Dados de teste
-- -----------------------------------------------------------------------------
-- Os do enunciado (secao 6), mais dois passageiros para os experimentos que
-- precisam de quatro atores simultaneos.

INSERT INTO aeronaves (fabricante, modelo, quantidade_assentos)
VALUES ('Airbus', 'A320', 180);

INSERT INTO voos (codigo, origem, destino, data_hora_saida, aeronave_id)
VALUES ('AB1234', 'Brasília', 'São Paulo', '2026-10-10 10:00:00', 1);

INSERT INTO passageiros (nome, documento) VALUES
    ('Passageiro A', 'DOC001'),
    ('Passageiro B', 'DOC002'),
    ('Passageiro C', 'DOC003'),
    ('Passageiro D', 'DOC004');

INSERT INTO assentos (voo_id, numero, classe) VALUES
    (1, '10A', 'ECONOMICA'),
    (1, '10B', 'ECONOMICA'),
    (1, '10C', 'ECONOMICA');


-- -----------------------------------------------------------------------------
-- 9. Conferencia do ambiente
-- -----------------------------------------------------------------------------
-- Os experimentos dependem destes tres valores, e o md reporta todos eles.

SELECT @@version                    AS versao,
       @@transaction_isolation      AS isolamento_padrao,
       @@innodb_lock_wait_timeout    AS lock_wait_timeout_s,
       @@innodb_deadlock_detect      AS deteccao_de_deadlock;

SELECT id, voo_id, numero, classe, status FROM assentos ORDER BY id;

SHOW CREATE TABLE reservas;
