-- =============================================================================
-- Aula 09 - Normalizacao de Banco de Dados
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco aeroporto apos a aplicacao das formas normais sobre o esquema da
-- Aula 08 (sql_aula_8.sql). A analise que justifica cada alteracao, e cada
-- nao-alteracao, esta em normalizacao.md.
--
-- Duas alteracoes em relacao a Aula 08:
--   3FN em aeronave -> extraida a tabela modelo_aeronave (modelo -> fabricante)
--   2FN em voo      -> extraida a tabela rota (numero_voo -> origem, destino)
--
-- Testado em MySQL 8.0.46. Rodar o arquivo inteiro de uma vez.
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
-- 2. Tabelas
-- -----------------------------------------------------------------------------
-- Ordem de criacao seguindo as dependencias: as duas tabelas novas
-- (modelo_aeronave e rota) entram antes de quem as referencia.

-- 2.1 MODELO_AERONAVE (nova, 3FN)
-- Resolve a dependencia transitiva modelo -> fabricante que existia em
-- aeronave. Um "737 MAX 8" e da Boeing independentemente da aeronave.
CREATE TABLE modelo_aeronave (
    id_modelo  INT AUTO_INCREMENT PRIMARY KEY,
    modelo     VARCHAR(50) NOT NULL,
    fabricante VARCHAR(50) NOT NULL,

    CONSTRAINT uq_modelo_aeronave_modelo UNIQUE (modelo)
) ENGINE = InnoDB;

-- 2.2 AERONAVE
-- capacidade_assentos PERMANECE aqui, e nao em modelo_aeronave: a mesma
-- aeronave pode ter configuracoes de cabine diferentes, entao a capacidade e
-- propriedade da aeronave fisica, nao do modelo. Ver normalizacao.md, secao 3FN.
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

-- 2.3 PASSAGEIRO (inalterada em relacao a Aula 08)
CREATE TABLE passageiro (
    id_passageiro   INT AUTO_INCREMENT PRIMARY KEY,
    cpf             CHAR(11)     NULL,
    nome            VARCHAR(120) NOT NULL,
    data_nascimento DATE         NULL,
    email           VARCHAR(120) NULL,
    telefone        VARCHAR(20)  NULL,

    CONSTRAINT uq_passageiro_cpf UNIQUE (cpf)
) ENGINE = InnoDB;

-- 2.4 ROTA (nova, 2FN)
-- Resolve a dependencia parcial numero_voo -> origem, destino em relacao a
-- chave candidata natural (numero_voo, data_hora_partida).
--
-- ck_rota_origem_destino e a antiga ck_voo_rota: a regra "origem diferente de
-- destino" acompanha os atributos que ela restringe. Se ficasse em voo, nao
-- teria mais o que restringir, porque origem e destino nao moram mais la.
CREATE TABLE rota (
    id_rota    INT AUTO_INCREMENT PRIMARY KEY,
    numero_voo VARCHAR(10) NOT NULL,
    origem     CHAR(3)     NOT NULL,
    destino    CHAR(3)     NOT NULL,

    CONSTRAINT uq_rota_numero_voo UNIQUE (numero_voo),
    CONSTRAINT ck_rota_origem_destino CHECK (origem <> destino)
) ENGINE = InnoDB;

-- 2.5 VOO
-- Guarda apenas o que varia por ocorrencia: data, aeronave escalada, portao e
-- status. O que e fixo do numero do voo migrou para rota.
--
-- uq_voo_rota_partida e a antiga uq_voo_numero_partida reescrita: como
-- numero_voo saiu da tabela, a unicidade passa a ser sobre (id_rota,
-- data_hora_partida). Como numero_voo e UNIQUE em rota, a regra preservada e
-- exatamente a mesma: o mesmo numero de voo nao pode partir duas vezes no
-- mesmo instante.
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
                                               'Aguardando', 'Cancelado'))
) ENGINE = InnoDB;

-- 2.6 PASSAGEM (inalterada em relacao a Aula 08)
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
-- 3. Estrutura criada
-- -----------------------------------------------------------------------------

SHOW TABLES;

DESCRIBE modelo_aeronave;
DESCRIBE aeronave;
DESCRIBE passageiro;
DESCRIBE rota;
DESCRIBE voo;
DESCRIBE passagem;


-- -----------------------------------------------------------------------------
-- 4. Insercao dos dados
-- -----------------------------------------------------------------------------
-- Os mesmos registros da Aula 08, redistribuidos no esquema normalizado.
-- Nenhum dado foi acrescentado, removido ou alterado: 6 aeronaves,
-- 8 passageiros, 8 voos e 12 passagens, como no original.

-- 4.1 Os 6 modelos distintos que estavam repetidos na tabela aeronave.
INSERT INTO modelo_aeronave (modelo, fabricante) VALUES
    ('A320neo',   'Airbus'),
    ('737 MAX 8', 'Boeing'),
    ('E195-E2',   'Embraer'),
    ('A321neo',   'Airbus'),
    ('737-800',   'Boeing'),
    ('E190',      'Embraer');

-- O ganho aparece aqui: 'Airbus', 'Boeing' e 'Embraer' eram repetidos a cada
-- aeronave. Corrigir a grafia de um fabricante agora e um UPDATE em uma linha.

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

-- 4.2 As 7 rotas distintas. Os 8 voos da Aula 08 usavam 7 numeros diferentes:
-- o 305 aparecia duas vezes, nos dias 01 e 02, com a mesma origem e o mesmo
-- destino. Essa repeticao e exatamente a redundancia que a tabela rota elimina.
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

-- Os id_voo gerados (1 a 8) sao os mesmos da Aula 08, na mesma ordem, o que
-- mantem validas as chaves estrangeiras das passagens abaixo.
-- O primeiro e o ultimo registro sao o voo 305 em dois dias: agora apontam
-- para a mesma rota, e o que difere e a data, a aeronave e o portao.

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
-- 5. Conferencia da migracao
-- -----------------------------------------------------------------------------
-- As contagens devem bater com as da Aula 08: nenhum registro perdido ou
-- duplicado na mudanca de esquema.

SELECT 'modelo_aeronave' AS tabela, COUNT(*) AS registros FROM modelo_aeronave
UNION ALL SELECT 'aeronave',   COUNT(*) FROM aeronave
UNION ALL SELECT 'passageiro', COUNT(*) FROM passageiro
UNION ALL SELECT 'rota',       COUNT(*) FROM rota
UNION ALL SELECT 'voo',        COUNT(*) FROM voo
UNION ALL SELECT 'passagem',   COUNT(*) FROM passagem;


-- -----------------------------------------------------------------------------
-- 6. Consultas
-- -----------------------------------------------------------------------------
-- As mesmas consultas da Aula 08, adaptadas ao esquema normalizado. Os
-- resultados sao identicos aos do banco anterior: a normalizacao mudou onde o
-- dado mora, nao o que o banco responde.
--
-- O custo da normalizacao aparece aqui: consultas que antes liam uma tabela
-- agora precisam de JOIN. E a troca classica, redundancia menor por juncao a
-- mais.

-- 6.1 Conteudo bruto de cada tabela
SELECT * FROM modelo_aeronave;
SELECT * FROM aeronave;
SELECT * FROM passageiro;
SELECT * FROM rota;
SELECT * FROM voo;
SELECT * FROM passagem;

-- 6.2 Painel de voos
-- Antes: JOIN com aeronave. Agora: mais dois JOINs, com rota e modelo_aeronave.
SELECT r.numero_voo,
       r.origem,
       r.destino,
       DATE_FORMAT(v.data_hora_partida, '%d/%m %H:%i') AS partida,
       v.portao,
       v.status,
       a.prefixo,
       m.modelo
FROM voo v
JOIN rota r            ON r.id_rota     = v.id_rota
JOIN aeronave a        ON a.id_aeronave = v.id_aeronave
JOIN modelo_aeronave m ON m.id_modelo   = a.id_modelo
ORDER BY v.data_hora_partida;

-- 6.3 Lista de embarque de um voo
-- O filtro por numero_voo agora acontece em rota, nao em voo.
SELECT r.numero_voo,
       p.nome,
       pg.assento,
       pg.classe,
       CASE WHEN pg.checkin_realizado THEN 'Sim' ELSE 'Nao' END AS checkin
FROM passagem pg
JOIN passageiro p ON p.id_passageiro = pg.id_passageiro
JOIN voo v        ON v.id_voo        = pg.id_voo
JOIN rota r       ON r.id_rota       = v.id_rota
WHERE r.numero_voo = '305'
  AND DATE(v.data_hora_partida) = '2026-09-01'
ORDER BY pg.assento;

-- 6.4 Ocupacao por voo
SELECT r.numero_voo,
       m.modelo,
       a.capacidade_assentos,
       COUNT(pg.id_passagem) AS passagens_vendidas,
       ROUND(COUNT(pg.id_passagem) / a.capacidade_assentos * 100, 1) AS ocupacao_pct
FROM voo v
JOIN rota r            ON r.id_rota     = v.id_rota
JOIN aeronave a        ON a.id_aeronave = v.id_aeronave
JOIN modelo_aeronave m ON m.id_modelo   = a.id_modelo
LEFT JOIN passagem pg  ON pg.id_voo     = v.id_voo
GROUP BY v.id_voo, r.numero_voo, m.modelo, a.capacidade_assentos
ORDER BY ocupacao_pct DESC;

-- capacidade_assentos vem de aeronave e modelo vem de modelo_aeronave: e a
-- separacao decidida na 3FN aparecendo na pratica.

-- 6.5 Passageiros com mais de um voo comprado
-- Nao mudou: passageiro e passagem nao foram alteradas.
SELECT p.nome,
       COUNT(pg.id_passagem) AS total_voos
FROM passageiro p
JOIN passagem pg ON pg.id_passageiro = p.id_passageiro
GROUP BY p.id_passageiro, p.nome
HAVING COUNT(pg.id_passagem) > 1
ORDER BY total_voos DESC, p.nome;

-- 6.6 Proximos voos a partir das 12:00 do dia 01
SELECT r.numero_voo, r.origem, r.destino,
       v.data_hora_partida, v.portao, v.status
FROM voo v
JOIN rota r ON r.id_rota = v.id_rota
WHERE v.data_hora_partida >= '2026-09-01 12:00:00'
ORDER BY v.data_hora_partida;

-- 6.7 Consulta nova, viabilizada pela tabela rota
-- Quantas ocorrencias cada rota teve. No esquema da Aula 08 isso exigiria
-- agrupar por (numero_voo, origem, destino) e confiar que a origem e o destino
-- estavam iguais em todas as linhas do mesmo numero. Aqui a rota e uma entidade
-- com identidade propria, entao o agrupamento e por chave.
SELECT r.numero_voo,
       CONCAT(r.origem, ' -> ', r.destino) AS trecho,
       COUNT(v.id_voo) AS ocorrencias
FROM rota r
LEFT JOIN voo v ON v.id_rota = r.id_rota
GROUP BY r.id_rota, r.numero_voo, r.origem, r.destino
ORDER BY ocorrencias DESC, r.numero_voo;
