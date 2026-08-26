-- =============================================================================
-- Aula 08 - Criacao de Banco de Dados
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Implementacao em MySQL do modelo logico desenhado na Aula 05.
-- Entidades: PASSAGEIRO, VOO, AERONAVE e a tabela associativa PASSAGEM.
--
-- Testado em MariaDB 10.11 e compativel com MySQL 8.x (versao do Laragon).
-- Rodar o arquivo inteiro de uma vez: ele cria o banco, as tabelas, insere os
-- dados e executa as consultas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Banco de dados
-- -----------------------------------------------------------------------------

DROP DATABASE IF EXISTS aeroporto;

CREATE DATABASE aeroporto
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE aeroporto;

-- utf8mb4 e nao utf8: no MySQL, "utf8" e um apelido para utf8mb3, que usa no
-- maximo 3 bytes por caractere e nao cobre emoji nem parte dos acentos. O
-- utf8mb4 e o UTF-8 completo.
-- A collation utf8mb4_unicode_ci funciona tanto em MySQL quanto em MariaDB.
-- A utf8mb4_0900_ai_ci, padrao do MySQL 8, nao existe no MariaDB.


-- -----------------------------------------------------------------------------
-- 2. Tabelas
-- -----------------------------------------------------------------------------
-- A ordem importa: uma tabela so pode referenciar outra que ja existe.
-- AERONAVE e PASSAGEIRO nao dependem de ninguem, VOO depende de AERONAVE e
-- PASSAGEM depende das duas.

CREATE TABLE aeronave (
    id_aeronave         INT AUTO_INCREMENT PRIMARY KEY,
    prefixo             VARCHAR(10)  NOT NULL,
    modelo              VARCHAR(50)  NOT NULL,
    fabricante          VARCHAR(50)  NOT NULL,
    capacidade_assentos INT          NOT NULL,

    CONSTRAINT uq_aeronave_prefixo UNIQUE (prefixo),
    CONSTRAINT ck_aeronave_capacidade CHECK (capacidade_assentos > 0)
) ENGINE = InnoDB;

CREATE TABLE passageiro (
    id_passageiro   INT AUTO_INCREMENT PRIMARY KEY,
    cpf             CHAR(11)     NULL,
    nome            VARCHAR(120) NOT NULL,
    data_nascimento DATE         NULL,
    email           VARCHAR(120) NULL,
    telefone        VARCHAR(20)  NULL,

    CONSTRAINT uq_passageiro_cpf UNIQUE (cpf)
) ENGINE = InnoDB;

-- cpf aceita NULL de proposito: passageiro estrangeiro nao tem CPF. A constraint
-- UNIQUE continua valendo, porque no padrao SQL varios NULL nao conflitam entre
-- si (NULL nao e igual a NULL). Foi por isso que a chave primaria ficou sendo a
-- chave substituta id_passageiro, e nao o CPF.

CREATE TABLE voo (
    id_voo                     INT AUTO_INCREMENT PRIMARY KEY,
    numero_voo                 VARCHAR(10) NOT NULL,
    id_aeronave                INT         NOT NULL,
    origem                     CHAR(3)     NOT NULL,
    destino                    CHAR(3)     NOT NULL,
    data_hora_partida          DATETIME    NOT NULL,
    data_hora_chegada_prevista DATETIME    NULL,
    portao                     VARCHAR(5)  NULL,
    status                     VARCHAR(20) NOT NULL DEFAULT 'Aguardando',

    CONSTRAINT fk_voo_aeronave
        FOREIGN KEY (id_aeronave) REFERENCES aeronave (id_aeronave)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_voo_numero_partida UNIQUE (numero_voo, data_hora_partida),
    CONSTRAINT ck_voo_rota   CHECK (origem <> destino),
    CONSTRAINT ck_voo_status CHECK (status IN ('Embarque', 'Confirmado',
                                               'Aguardando', 'Cancelado'))
) ENGINE = InnoDB;

-- numero_voo sozinho nao e chave: o voo 305 acontece todo dia. A chave natural
-- e o par numero mais data de partida.
-- portao e VARCHAR e nao INT porque tem zero a esquerda (08, 01) e e
-- identificador, nao quantidade.
-- ON DELETE RESTRICT impede apagar uma aeronave que ainda tem voos.

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

    CONSTRAINT uq_passagem_localizador   UNIQUE (localizador),
    CONSTRAINT uq_passagem_passageiro_voo UNIQUE (id_passageiro, id_voo),
    CONSTRAINT uq_passagem_voo_assento    UNIQUE (id_voo, assento),
    CONSTRAINT ck_passagem_classe CHECK (classe IN ('Economica', 'Executiva',
                                                    'Primeira'))
) ENGINE = InnoDB;

-- PASSAGEM resolve o N:N entre PASSAGEIRO e VOO e e onde mora o assento.
-- uq_passagem_passageiro_voo impede o mesmo passageiro em dois assentos no
-- mesmo voo, que era o desafio da Aula 05.
-- uq_passagem_voo_assento impede dois passageiros no mesmo assento.


-- -----------------------------------------------------------------------------
-- 3. Estrutura criada
-- -----------------------------------------------------------------------------

SHOW TABLES;

DESCRIBE aeronave;
DESCRIBE passageiro;
DESCRIBE voo;
DESCRIBE passagem;


-- -----------------------------------------------------------------------------
-- 4. Insercao dos dados
-- -----------------------------------------------------------------------------
-- Mesma ordem das tabelas: quem e referenciado entra primeiro.

INSERT INTO aeronave (prefixo, modelo, fabricante, capacidade_assentos) VALUES
    ('PR-XAA', 'A320neo',     'Airbus',   180),
    ('PR-XBB', '737 MAX 8',   'Boeing',   186),
    ('PT-YCC', 'E195-E2',     'Embraer',  136),
    ('PR-XDD', 'A321neo',     'Airbus',   220),
    ('PS-YEE', '737-800',     'Boeing',   189),
    ('PT-ZFF', 'E190',        'Embraer',  106);

INSERT INTO passageiro (cpf, nome, data_nascimento, email, telefone) VALUES
    ('11122233344', 'Ana Souza',          '1991-04-12', 'ana.souza@email.com',   '61999990001'),
    ('22233344455', 'Bruno Carvalho',     '1985-11-30', 'bruno.c@email.com',     '61999990002'),
    ('33344455566', 'Carla Menezes',      '1998-02-08', 'carla.m@email.com',     '61999990003'),
    ('44455566677', 'Diego Fontes',       '1979-07-21', 'diego.f@email.com',     '61999990004'),
    ('55566677788', 'Elisa Prado',        '2001-09-03', 'elisa.p@email.com',     '61999990005'),
    ('66677788899', 'Fabio Rezende',      '1993-12-17', 'fabio.r@email.com',     '61999990006'),
    ('77788899900', 'Gabriela Lins',      '1988-05-25', 'gabriela.l@email.com',  '61999990007'),
    (NULL,          'Henrik Johansson',   '1990-01-14', 'henrik.j@email.com',    '46701234567');

-- O ultimo passageiro e estrangeiro e entra com cpf NULL, exercitando a decisao
-- de modelagem tomada na Aula 05.

INSERT INTO voo (numero_voo, id_aeronave, origem, destino,
                 data_hora_partida, data_hora_chegada_prevista, portao, status) VALUES
    ('305', 1, 'GRU', 'BSB', '2026-09-01 08:30:00', '2026-09-01 10:10:00', '12', 'Embarque'),
    ('420', 2, 'BSB', 'GIG', '2026-09-01 09:15:00', '2026-09-01 11:00:00', '08', 'Confirmado'),
    ('711', 3, 'BSB', 'GRU', '2026-09-01 10:40:00', '2026-09-01 12:20:00', '23', 'Embarque'),
    ('125', 4, 'BSB', 'SSA', '2026-09-01 11:20:00', '2026-09-01 13:05:00', '15', 'Confirmado'),
    ('308', 5, 'CGH', 'BSB', '2026-09-01 12:00:00', '2026-09-01 13:40:00', '07', 'Aguardando'),
    ('512', 6, 'BSB', 'CNF', '2026-09-01 12:30:00', '2026-09-01 14:00:00', '04', 'Embarque'),
    ('630', 1, 'BSB', 'REC', '2026-09-01 13:10:00', '2026-09-01 15:40:00', '18', 'Confirmado'),
    ('305', 2, 'GRU', 'BSB', '2026-09-02 08:30:00', '2026-09-02 10:10:00', '11', 'Aguardando');

-- Os dois ultimos registros sao o voo 305 em dois dias diferentes. E o que a
-- constraint uq_voo_numero_partida permite: o numero se repete, o par com a
-- data nao.

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

-- A passageira 1 aparece nos voos 1 e 3, e o passageiro 8 nos voos 4 e 7:
-- e o lado N:N funcionando.


-- -----------------------------------------------------------------------------
-- 5. Consultas
-- -----------------------------------------------------------------------------

-- 5.1 Conteudo bruto de cada tabela
SELECT * FROM aeronave;
SELECT * FROM passageiro;
SELECT * FROM voo;
SELECT * FROM passagem;

-- 5.2 Painel de voos: junta VOO com AERONAVE pela chave estrangeira
SELECT v.numero_voo,
       v.origem,
       v.destino,
       DATE_FORMAT(v.data_hora_partida, '%d/%m %H:%i') AS partida,
       v.portao,
       v.status,
       a.prefixo,
       a.modelo
FROM voo v
JOIN aeronave a ON a.id_aeronave = v.id_aeronave
ORDER BY v.data_hora_partida;

-- 5.3 Lista de embarque de um voo: os tres JOINs atravessando a associativa
SELECT v.numero_voo,
       p.nome,
       pg.assento,
       pg.classe,
       CASE WHEN pg.checkin_realizado THEN 'Sim' ELSE 'Nao' END AS checkin
FROM passagem pg
JOIN passageiro p ON p.id_passageiro = pg.id_passageiro
JOIN voo v        ON v.id_voo        = pg.id_voo
WHERE v.numero_voo = '305'
  AND DATE(v.data_hora_partida) = '2026-09-01'
ORDER BY pg.assento;

-- 5.4 Ocupacao por voo, comparando passagens vendidas com a capacidade
SELECT v.numero_voo,
       a.modelo,
       a.capacidade_assentos,
       COUNT(pg.id_passagem) AS passagens_vendidas,
       ROUND(COUNT(pg.id_passagem) / a.capacidade_assentos * 100, 1) AS ocupacao_pct
FROM voo v
JOIN aeronave a       ON a.id_aeronave = v.id_aeronave
LEFT JOIN passagem pg ON pg.id_voo     = v.id_voo
GROUP BY v.id_voo, v.numero_voo, a.modelo, a.capacidade_assentos
ORDER BY ocupacao_pct DESC;

-- LEFT JOIN e nao JOIN: um voo sem nenhuma passagem vendida precisa aparecer
-- com zero. Com JOIN simples ele sumiria do resultado.

-- 5.5 Passageiros com mais de um voo comprado
SELECT p.nome,
       COUNT(pg.id_passagem) AS total_voos
FROM passageiro p
JOIN passagem pg ON pg.id_passageiro = p.id_passageiro
GROUP BY p.id_passageiro, p.nome
HAVING COUNT(pg.id_passagem) > 1
ORDER BY total_voos DESC, p.nome;

-- WHERE filtra linha, HAVING filtra grupo. Como a condicao e sobre o COUNT,
-- que so existe depois do agrupamento, tem que ser HAVING.

-- 5.6 Proximos voos a partir das 12:00 do dia 01
SELECT numero_voo, origem, destino, data_hora_partida, portao, status
FROM voo
WHERE data_hora_partida >= '2026-09-01 12:00:00'
ORDER BY data_hora_partida;
