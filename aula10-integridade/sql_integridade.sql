-- =============================================================================
-- Aula 10 - Restricao de Integridade
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco aeroporto com as regras de integridade implementadas. Parte do esquema
-- normalizado da Aula 09 (seis tabelas), nao do esquema de quatro tabelas da
-- Aula 08.
--
-- Arquivo autocontido: recria o banco do zero, com as restricoes, a trigger e
-- os dados de exemplo. A analise que justifica cada regra, e as regras que
-- foram deliberadamente NAO implementadas, estao em integridade.md.
--
-- Regras acrescentadas em relacao a Aula 09:
--   ck_voo_chegada_apos_partida   chegada prevista posterior a partida
--   ck_rota_origem_iata           origem no formato IATA (3 letras maiusculas)
--   ck_rota_destino_iata          destino no formato IATA
--   trg_passagem_capacidade_*     passagens vendidas <= capacidade da aeronave
--
-- Testado em MySQL 8.0.46.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Banco de dados
-- -----------------------------------------------------------------------------

DROP DATABASE IF EXISTS aeroporto;

CREATE DATABASE aeroporto
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE aeroporto;


-- -----------------------------------------------------------------------------
-- 2. Tabelas e restricoes
-- -----------------------------------------------------------------------------

-- 2.1 MODELO_AERONAVE
--
-- Entidade:      id_modelo, chave substituta.
-- Chave:         modelo e chave candidata natural (uq_modelo_aeronave_modelo).
-- Obrigatorios:  modelo e fabricante. Um modelo sem fabricante nao identifica
--                nada; era justamente a dependencia modelo -> fabricante que
--                motivou a extracao desta tabela na Aula 09.
CREATE TABLE modelo_aeronave (
    id_modelo  INT AUTO_INCREMENT PRIMARY KEY,
    modelo     VARCHAR(50) NOT NULL,
    fabricante VARCHAR(50) NOT NULL,

    CONSTRAINT uq_modelo_aeronave_modelo UNIQUE (modelo)
) ENGINE = InnoDB;


-- 2.2 AERONAVE
--
-- Referencial:   id_modelo -> modelo_aeronave. RESTRICT no DELETE porque
--                apagar um modelo com aeronaves na frota deixaria aeronaves
--                sem identificacao tecnica.
-- Dominio:       capacidade_assentos > 0. Aeronave que nao transporta ninguem
--                nao entra na frota de um sistema de venda de passagens.
CREATE TABLE aeronave (
    id_aeronave         INT AUTO_INCREMENT PRIMARY KEY,
    prefixo             VARCHAR(10) NOT NULL,
    id_modelo           INT         NOT NULL,
    capacidade_assentos INT         NOT NULL,

    CONSTRAINT fk_aeronave_modelo
        FOREIGN KEY (id_modelo) REFERENCES modelo_aeronave (id_modelo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_aeronave_prefixo UNIQUE (prefixo),
    CONSTRAINT ck_aeronave_capacidade CHECK (capacidade_assentos > 0)
) ENGINE = InnoDB;


-- 2.3 PASSAGEIRO
--
-- cpf aceita NULL de proposito: passageiro estrangeiro nao tem CPF. A decisao
-- e da Aula 05 e e o motivo de a chave primaria ser substituta. UNIQUE continua
-- valendo porque, no padrao SQL, varios NULL nao conflitam entre si.
-- email e telefone tambem aceitam NULL: sao canais de contato, nao identidade.
CREATE TABLE passageiro (
    id_passageiro   INT AUTO_INCREMENT PRIMARY KEY,
    cpf             CHAR(11)     NULL,
    nome            VARCHAR(120) NOT NULL,
    data_nascimento DATE         NULL,
    email           VARCHAR(120) NULL,
    telefone        VARCHAR(20)  NULL,

    CONSTRAINT uq_passageiro_cpf UNIQUE (cpf)
) ENGINE = InnoDB;


-- 2.4 ROTA
--
-- uq_rota_numero_voo NAO e decorativa: e ela que sustenta a equivalencia entre
-- uq_voo_rota_partida e a antiga uq_voo_numero_partida da Aula 08. Sem ela,
-- dois id_rota diferentes poderiam carregar o mesmo numero_voo, e o mesmo
-- numero poderia partir duas vezes no mesmo instante por rotas distintas.
--
-- ck_rota_origem_destino e a antiga ck_voo_rota, que migrou junto com os
-- atributos que restringe.
--
-- ck_rota_*_iata: codigo IATA de aeroporto tem exatamente 3 letras maiusculas.
-- O match type 'c' forca comparacao sensivel a caixa; sem ele a collation
-- utf8mb4_unicode_ci, que e case-insensitive, aceitaria 'bsb'.
CREATE TABLE rota (
    id_rota    INT AUTO_INCREMENT PRIMARY KEY,
    numero_voo VARCHAR(10) NOT NULL,
    origem     CHAR(3)     NOT NULL,
    destino    CHAR(3)     NOT NULL,

    CONSTRAINT uq_rota_numero_voo UNIQUE (numero_voo),
    CONSTRAINT ck_rota_origem_destino CHECK (origem <> destino),
    CONSTRAINT ck_rota_origem_iata
        CHECK (REGEXP_LIKE(origem, '^[A-Z]{3}$', 'c')),
    CONSTRAINT ck_rota_destino_iata
        CHECK (REGEXP_LIKE(destino, '^[A-Z]{3}$', 'c'))
) ENGINE = InnoDB;


-- 2.5 VOO
--
-- Referencial:   duas FKs, ambas RESTRICT no DELETE. Ver integridade.md,
--                secao 2.2, para o que CASCADE faria em cada caso.
-- Dominio:       status limitado a quatro valores; DEFAULT 'Aguardando', que e
--                o estado em que todo voo nasce.
-- Regra nova:    ck_voo_chegada_apos_partida. Chegada prevista anterior a
--                partida e viagem no tempo. A comparacao so vale quando a
--                chegada nao e NULL, e um CHECK com operando NULL avalia como
--                UNKNOWN, que o SQL aceita: voo sem previsao de chegada
--                continua podendo ser cadastrado.
CREATE TABLE voo (
    id_voo                     INT AUTO_INCREMENT PRIMARY KEY,
    id_rota                    INT         NOT NULL,
    id_aeronave                INT         NOT NULL,
    data_hora_partida          DATETIME    NOT NULL,
    data_hora_chegada_prevista DATETIME    NULL,
    portao                     VARCHAR(5)  NULL,
    status                     VARCHAR(20) NOT NULL DEFAULT 'Aguardando',

    CONSTRAINT fk_voo_rota
        FOREIGN KEY (id_rota) REFERENCES rota (id_rota)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_voo_aeronave
        FOREIGN KEY (id_aeronave) REFERENCES aeronave (id_aeronave)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_voo_rota_partida UNIQUE (id_rota, data_hora_partida),
    CONSTRAINT ck_voo_status CHECK (status IN ('Embarque', 'Confirmado',
                                               'Aguardando', 'Cancelado')),
    CONSTRAINT ck_voo_chegada_apos_partida
        CHECK (data_hora_chegada_prevista > data_hora_partida)
) ENGINE = InnoDB;


-- 2.6 PASSAGEM
--
-- Tres chaves candidatas alem da primaria, cada uma com um proposito distinto:
--   localizador             identificador que o passageiro usa
--   (id_passageiro, id_voo) mesmo passageiro nao ocupa dois assentos no voo
--   (id_voo, assento)       mesmo assento nao e vendido duas vezes
CREATE TABLE passagem (
    id_passagem       INT AUTO_INCREMENT PRIMARY KEY,
    id_passageiro     INT         NOT NULL,
    id_voo            INT         NOT NULL,
    assento           VARCHAR(4)  NOT NULL,
    localizador       CHAR(6)     NOT NULL,
    classe            VARCHAR(20) NOT NULL DEFAULT 'Economica',
    checkin_realizado BOOLEAN     NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_passagem_passageiro
        FOREIGN KEY (id_passageiro) REFERENCES passageiro (id_passageiro)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_passagem_voo
        FOREIGN KEY (id_voo) REFERENCES voo (id_voo)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_passagem_localizador    UNIQUE (localizador),
    CONSTRAINT uq_passagem_passageiro_voo UNIQUE (id_passageiro, id_voo),
    CONSTRAINT uq_passagem_voo_assento    UNIQUE (id_voo, assento),
    CONSTRAINT ck_passagem_classe CHECK (classe IN ('Economica', 'Executiva',
                                                    'Primeira'))
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 3. Regra que as restricoes declarativas nao alcancam
-- -----------------------------------------------------------------------------
-- RN: o numero de passagens vendidas para um voo nao pode exceder a capacidade
-- de assentos da aeronave escalada.
--
-- Por que nao e um CHECK: a regra precisa contar linhas de passagem e ler
-- capacidade_assentos de aeronave, atravessando voo. O CHECK do MySQL 8 nao
-- aceita subconsulta nem funcao de agregacao, entao a regra e inexpressavel
-- nele. Nao e limitacao de sintaxe deste projeto, e do recurso.
--
-- Por que trigger e nao validacao na aplicacao: a trigger e o unico recurso do
-- proprio SGBD que alcanca a regra. Fora dela, a garantia dependeria de todo
-- cliente lembrar de verificar, que e exatamente o que a Aula 08 argumentou
-- contra ao colocar as regras de negocio no banco.
--
-- Limitacao registrada: sob concorrencia alta, duas transacoes simultaneas
-- podem ler a mesma contagem antes de qualquer uma gravar, e as duas passarem.
-- A garantia completa exigiria bloqueio explicito na linha do voo. Para o
-- escopo desta disciplina a trigger e suficiente, mas a ressalva fica.

DELIMITER $$

CREATE TRIGGER trg_passagem_capacidade_insert
BEFORE INSERT ON passagem
FOR EACH ROW
BEGIN
    DECLARE v_capacidade INT;
    DECLARE v_vendidas   INT;

    SELECT a.capacidade_assentos
      INTO v_capacidade
      FROM voo v
      JOIN aeronave a ON a.id_aeronave = v.id_aeronave
     WHERE v.id_voo = NEW.id_voo;

    SELECT COUNT(*)
      INTO v_vendidas
      FROM passagem
     WHERE id_voo = NEW.id_voo;

    IF v_vendidas >= v_capacidade THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Capacidade da aeronave excedida para este voo';
    END IF;
END$$

-- A mesma regra no UPDATE: mover uma passagem para outro voo tambem pode
-- estourar a capacidade do voo de destino. Sem esta segunda trigger, a regra
-- seria contornavel por UPDATE.
CREATE TRIGGER trg_passagem_capacidade_update
BEFORE UPDATE ON passagem
FOR EACH ROW
BEGIN
    DECLARE v_capacidade INT;
    DECLARE v_vendidas   INT;

    IF NEW.id_voo <> OLD.id_voo THEN
        SELECT a.capacidade_assentos
          INTO v_capacidade
          FROM voo v
          JOIN aeronave a ON a.id_aeronave = v.id_aeronave
         WHERE v.id_voo = NEW.id_voo;

        SELECT COUNT(*)
          INTO v_vendidas
          FROM passagem
         WHERE id_voo = NEW.id_voo;

        IF v_vendidas >= v_capacidade THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Capacidade da aeronave excedida para este voo';
        END IF;
    END IF;
END$$

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 4. Estrutura criada
-- -----------------------------------------------------------------------------

SHOW TABLES;

DESCRIBE modelo_aeronave;
DESCRIBE aeronave;
DESCRIBE passageiro;
DESCRIBE rota;
DESCRIBE voo;
DESCRIBE passagem;

-- Conferencia das restricoes efetivamente criadas no dicionario do SGBD, e nao
-- apenas escritas neste arquivo.
SELECT constraint_name, constraint_type, table_name
  FROM information_schema.table_constraints
 WHERE constraint_schema = 'aeroporto'
 ORDER BY table_name, constraint_type, constraint_name;

SELECT constraint_name, check_clause
  FROM information_schema.check_constraints
 WHERE constraint_schema = 'aeroporto'
 ORDER BY constraint_name;

SELECT trigger_name, event_manipulation, action_timing, event_object_table
  FROM information_schema.triggers
 WHERE trigger_schema = 'aeroporto'
 ORDER BY trigger_name;


-- -----------------------------------------------------------------------------
-- 5. Dados de exemplo
-- -----------------------------------------------------------------------------
-- Os mesmos registros das Aulas 08 e 09. Que eles entrem sem nenhum erro e a
-- primeira contraprova do trabalho: as restricoes bloqueiam o que e invalido
-- sem bloquear a carga legitima do sistema.

INSERT INTO modelo_aeronave (modelo, fabricante) VALUES
    ('A320neo',   'Airbus'),
    ('737 MAX 8', 'Boeing'),
    ('E195-E2',   'Embraer'),
    ('A321neo',   'Airbus'),
    ('737-800',   'Boeing'),
    ('E190',      'Embraer');

INSERT INTO aeronave (prefixo, id_modelo, capacidade_assentos) VALUES
    ('PR-XAA', 1, 180),
    ('PR-XBB', 2, 186),
    ('PT-YCC', 3, 136),
    ('PR-XDD', 4, 220),
    ('PS-YEE', 5, 189),
    ('PT-ZFF', 6, 106);

INSERT INTO passageiro (cpf, nome, data_nascimento, email, telefone) VALUES
    ('11122233344', 'Ana Souza',          '1991-04-12', 'ana.souza@email.com',   '61999990001'),
    ('22233344455', 'Bruno Carvalho',     '1985-11-30', 'bruno.c@email.com',     '61999990002'),
    ('33344455566', 'Carla Menezes',      '1998-02-08', 'carla.m@email.com',     '61999990003'),
    ('44455566677', 'Diego Fontes',       '1979-07-21', 'diego.f@email.com',     '61999990004'),
    ('55566677788', 'Elisa Prado',        '2001-09-03', 'elisa.p@email.com',     '61999990005'),
    ('66677788899', 'Fabio Rezende',      '1993-12-17', 'fabio.r@email.com',     '61999990006'),
    ('77788899900', 'Gabriela Lins',      '1988-05-25', 'gabriela.l@email.com',  '61999990007'),
    (NULL,          'Henrik Johansson',   '1990-01-14', 'henrik.j@email.com',    '46701234567');

INSERT INTO rota (numero_voo, origem, destino) VALUES
    ('305', 'GRU', 'BSB'),
    ('420', 'BSB', 'GIG'),
    ('711', 'BSB', 'GRU'),
    ('125', 'BSB', 'SSA'),
    ('308', 'CGH', 'BSB'),
    ('512', 'BSB', 'CNF'),
    ('630', 'BSB', 'REC');

INSERT INTO voo (id_rota, id_aeronave, data_hora_partida,
                 data_hora_chegada_prevista, portao, status) VALUES
    (1, 1, '2026-09-01 08:30:00', '2026-09-01 10:10:00', '12', 'Embarque'),
    (2, 2, '2026-09-01 09:15:00', '2026-09-01 11:00:00', '08', 'Confirmado'),
    (3, 3, '2026-09-01 10:40:00', '2026-09-01 12:20:00', '23', 'Embarque'),
    (4, 4, '2026-09-01 11:20:00', '2026-09-01 13:05:00', '15', 'Confirmado'),
    (5, 5, '2026-09-01 12:00:00', '2026-09-01 13:40:00', '07', 'Aguardando'),
    (6, 6, '2026-09-01 12:30:00', '2026-09-01 14:00:00', '04', 'Embarque'),
    (7, 1, '2026-09-01 13:10:00', '2026-09-01 15:40:00', '18', 'Confirmado'),
    (1, 2, '2026-09-02 08:30:00', '2026-09-02 10:10:00', '11', 'Aguardando');

INSERT INTO passagem (id_passageiro, id_voo, assento, localizador, classe, checkin_realizado) VALUES
    (1, 1, '12A', 'ABC123', 'Economica', TRUE),
    (2, 1, '12B', 'ABC124', 'Economica', TRUE),
    (3, 1, '01A', 'ABC125', 'Executiva', FALSE),
    (4, 2, '14C', 'DEF201', 'Economica', TRUE),
    (5, 2, '14D', 'DEF202', 'Economica', FALSE),
    (1, 3, '22F', 'GHI301', 'Economica', FALSE),
    (6, 3, '22E', 'GHI302', 'Economica', TRUE),
    (7, 4, '03A', 'JKL401', 'Primeira',  TRUE),
    (8, 4, '18B', 'JKL402', 'Economica', FALSE),
    (2, 5, '09C', 'MNO501', 'Executiva', FALSE),
    (3, 6, '11A', 'PQR601', 'Economica', TRUE),
    (8, 7, '07D', 'STU701', 'Economica', FALSE);


-- -----------------------------------------------------------------------------
-- 6. Conferencia final
-- -----------------------------------------------------------------------------

SELECT 'modelo_aeronave' AS tabela, COUNT(*) AS registros FROM modelo_aeronave
UNION ALL SELECT 'aeronave',   COUNT(*) FROM aeronave
UNION ALL SELECT 'passageiro', COUNT(*) FROM passageiro
UNION ALL SELECT 'rota',       COUNT(*) FROM rota
UNION ALL SELECT 'voo',        COUNT(*) FROM voo
UNION ALL SELECT 'passagem',   COUNT(*) FROM passagem;

-- Os testes que provam que cada regra funciona estao documentados em
-- integridade.md, secao 5, com comando, resultado esperado e resultado obtido.
