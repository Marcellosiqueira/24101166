-- Aula 25 - Autenticacao e validacao.
-- Rodar como root depois de migration_sql_injection.sql.
--
-- O enunciado cria uma tabela usuarios (email, senha_hash, perfil). No projeto
-- a tabela e usuario (Aula 22) e ja ganhou email e senha_hash na Aula 23, com
-- hash bcrypt gerado por password_hash(). Falta o perfil.
-- Senhas de teste: ana2026, bruno2026 e carla2026.

USE aeroporto;

-- -----------------------------------------------------------------------------
-- 1. Usuario: perfil, e email e senha obrigatorios
-- -----------------------------------------------------------------------------
ALTER TABLE usuario
    MODIFY email      VARCHAR(150) NOT NULL,
    MODIFY senha_hash VARCHAR(255) NOT NULL,
    ADD COLUMN perfil VARCHAR(20)  NOT NULL DEFAULT 'operador',
    ADD CONSTRAINT ck_usuario_perfil CHECK (perfil IN ('operador', 'admin'));

-- Desafio: so admin exclui voo. Ana e a administradora de teste.
UPDATE usuario SET perfil = 'admin' WHERE email = 'ana.ribeiro@aeroporto.test';

-- -----------------------------------------------------------------------------
-- 2. Codigo do voo no formato pedido: duas letras e 3 ou 4 numeros
-- -----------------------------------------------------------------------------
-- O codigo fica em rota.numero_voo (Aula 09) e ate aqui era so o numero (305).
-- O prefixo LA e o do exemplo do enunciado. A aplicacao valida o formato antes
-- de gravar; a constraint e a ultima barreira para quem gravar por fora dela.
UPDATE rota SET numero_voo = CONCAT('LA', numero_voo)
 WHERE numero_voo NOT REGEXP '^[A-Z]{2}[0-9]{3,4}$';

ALTER TABLE rota
    ADD CONSTRAINT ck_rota_numero_voo
        CHECK (REGEXP_LIKE(numero_voo, '^[A-Z]{2}[0-9]{3,4}$', 'c'));
