-- Aula 20 - Front + Back
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Cria o banco e a tabela alunos, com 6 registros. Os casos de nota 7,00 e
-- 6,99 estao ali de proposito: sao os dois lados exatos da regra de aprovacao
-- (nota >= 7) e mostram que o limite foi tratado corretamente.

DROP DATABASE IF EXISTS aula20;
CREATE DATABASE aula20 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE aula20;

CREATE TABLE alunos (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    nota DECIMAL(4,2) NOT NULL,
    CONSTRAINT ck_alunos_nota CHECK (nota BETWEEN 0 AND 10)
) ENGINE = InnoDB;

INSERT INTO alunos (nome, nota) VALUES
    ('Ana Souza',       8.50),
    ('Bruno Lima',      6.00),
    ('Carlos Mendes',   7.00),
    ('Daniel Oliveira', 5.50),
    ('Eduarda Santos',  9.00),
    ('Fernanda Rocha',  6.99);

SELECT * FROM alunos;
