-- =============================================================================
-- Aula 33 - BI Aeroporto: schema dimensional
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco separado aeroporto_dw. O OLTP (aeroporto) nao e alterado.
-- Estrela com uma fato no grao do voo e tres dimensoes. A justificativa de
-- uma fato so esta em modelo_estrela.md.
-- =============================================================================

DROP DATABASE IF EXISTS aeroporto_dw;

CREATE DATABASE aeroporto_dw
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE aeroporto_dw;

-- sk_tempo no formato AAAAMMDD: chave substituta legivel e ja ordenada.
CREATE TABLE dim_tempo (
    sk_tempo   INT PRIMARY KEY,
    data       DATE        NOT NULL,
    ano        SMALLINT    NOT NULL,
    mes        TINYINT     NOT NULL,
    nome_mes   VARCHAR(15) NOT NULL,
    dia        TINYINT     NOT NULL,
    dia_semana VARCHAR(15) NOT NULL,

    CONSTRAINT uq_dim_tempo_data UNIQUE (data)
) ENGINE = InnoDB;

-- id_rota e a chave natural do OLTP, guardada para o ETL achar a sk.
CREATE TABLE dim_rota (
    sk_rota    INT AUTO_INCREMENT PRIMARY KEY,
    id_rota    INT         NOT NULL,
    numero_voo VARCHAR(10) NOT NULL,
    origem     CHAR(3)     NOT NULL,
    destino    CHAR(3)     NOT NULL,

    CONSTRAINT uq_dim_rota_id UNIQUE (id_rota)
) ENGINE = InnoDB;

-- modelo e fabricante desnormalizados aqui (no OLTP estao em modelo_aeronave).
-- companhia e a lacuna do painel 4: nao existe no OLTP e fica NULL ate existir.
CREATE TABLE dim_aeronave (
    sk_aeronave         INT AUTO_INCREMENT PRIMARY KEY,
    id_aeronave         INT         NOT NULL,
    prefixo             VARCHAR(10) NOT NULL,
    modelo              VARCHAR(50) NOT NULL,
    fabricante          VARCHAR(50) NOT NULL,
    capacidade_assentos INT         NOT NULL,
    companhia           VARCHAR(60) NULL,

    CONSTRAINT uq_dim_aeronave_id UNIQUE (id_aeronave)
) ENGINE = InnoDB;

-- Grao: uma linha por voo realizado ou programado (uma partida de uma rota).
-- id_voo e status sao dimensoes degeneradas (atributos do proprio voo).
-- capacidade_assentos repete a da aeronave para a ocupacao ser SUM/SUM na fato.
CREATE TABLE fato_voo (
    id_voo              INT PRIMARY KEY,
    sk_tempo            INT         NOT NULL,
    sk_rota             INT         NOT NULL,
    sk_aeronave         INT         NOT NULL,
    status              VARCHAR(20) NOT NULL,
    qtd_voos            TINYINT     NOT NULL DEFAULT 1,
    qtd_passageiros     INT         NOT NULL,
    capacidade_assentos INT         NOT NULL,

    CONSTRAINT fk_fato_voo_tempo
        FOREIGN KEY (sk_tempo) REFERENCES dim_tempo (sk_tempo),
    CONSTRAINT fk_fato_voo_rota
        FOREIGN KEY (sk_rota) REFERENCES dim_rota (sk_rota),
    CONSTRAINT fk_fato_voo_aeronave
        FOREIGN KEY (sk_aeronave) REFERENCES dim_aeronave (sk_aeronave)
) ENGINE = InnoDB;

SHOW TABLES;
