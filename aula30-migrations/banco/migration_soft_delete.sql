-- Aula 22 - Soft delete de voos.
-- Rodar como root, depois do aula10-integridade/sql_integridade.sql
-- (e, se usado, do aula15-triggers/triggers.sql).

USE aeroporto;

-- -----------------------------------------------------------------------------
-- 1. Coluna deleted_at
-- -----------------------------------------------------------------------------
-- NULL = voo ativo. Preenchida = voo excluido, com a data e hora da exclusao.
ALTER TABLE voo
    ADD COLUMN deleted_at DATETIME NULL DEFAULT NULL;

-- Toda listagem filtra por deleted_at, entao a coluna ganha indice.
CREATE INDEX idx_voo_deleted_at ON voo (deleted_at);

-- -----------------------------------------------------------------------------
-- 2. Indice unico que ignora os voos excluidos
-- -----------------------------------------------------------------------------
-- Desde a Aula 10, uq_voo_rota_partida impede duas linhas com a mesma rota e
-- a mesma partida. Com soft delete, o voo excluido continua na tabela e
-- bloquearia o cadastro de um voo novo igual.
--
-- A coluna gerada "ativo" vale 1 para voo ativo e NULL para excluido. O indice
-- unico passa a ser (id_rota, data_hora_partida, ativo). Como o MySQL nao
-- compara NULL com NULL num indice unico, os excluidos nao colidem entre si
-- nem com o ativo; entre ativos a regra continua valendo.
ALTER TABLE voo
    ADD COLUMN ativo TINYINT
        AS (IF(deleted_at IS NULL, 1, NULL)) STORED;

-- O indice novo e criado antes de remover o antigo porque fk_voo_rota precisa
-- de um indice que comece por id_rota.
ALTER TABLE voo
    ADD CONSTRAINT uq_voo_rota_partida_ativo
        UNIQUE (id_rota, data_hora_partida, ativo);

ALTER TABLE voo
    DROP INDEX uq_voo_rota_partida;

-- -----------------------------------------------------------------------------
-- 3. Usuarios do sistema
-- -----------------------------------------------------------------------------
-- O projeto nao tem autenticacao. Para a auditoria registrar quem excluiu, o
-- operador escolhe o proprio nome ao entrar no sistema (sem senha).
CREATE TABLE usuario (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    nome       VARCHAR(100) NOT NULL,
    CONSTRAINT uq_usuario_nome UNIQUE (nome)
) ENGINE = InnoDB;

INSERT INTO usuario (nome) VALUES
    ('Ana Ribeiro'),
    ('Bruno Teixeira'),
    ('Carla Mendes');

-- -----------------------------------------------------------------------------
-- 4. Auditoria
-- -----------------------------------------------------------------------------
-- Estrutura sugerida no enunciado, com chave estrangeira para usuario.
-- A aplicacao so pode inserir e ler aqui (ver usuario_app.sql): linha de
-- auditoria nao e editada nem apagada pela aplicacao.
CREATE TABLE auditoria (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    tabela      VARCHAR(50) NOT NULL,
    registro_id INT         NOT NULL,
    acao        VARCHAR(20) NOT NULL,
    usuario_id  INT         NOT NULL,
    dados_antes JSON        NULL,
    criado_em   DATETIME    NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_auditoria_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT,

    INDEX idx_auditoria_registro (tabela, registro_id)
) ENGINE = InnoDB;
