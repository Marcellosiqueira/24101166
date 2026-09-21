-- =============================================================================
-- Aula 15 - Triggers
-- Disciplina de Banco de Dados - IDP
-- Marcello Azevedo Pinheiro Siqueira - 24101166
--
-- Banco: aeroporto
--
-- Este arquivo roda sobre o banco RECEM-CRIADO pela Aula 10. O
-- sql_integridade.sql derruba e recria o banco do zero, entao a ordem e:
--
--   mysql -u root -p < ../aula10-integridade/sql_integridade.sql
--   mysql -u root -p --force < triggers.sql
--
-- O --force e necessario porque a bateria de testes da secao 5 executa, de
-- proposito, comandos que o banco DEVE recusar. Sem ele o cliente aborta no
-- primeiro erro esperado e os testes seguintes nao rodam. Todo erro que
-- aparece na saida esta previsto e identificado por um marcador SELECT
-- imediatamente antes dele.
--
-- O esquema da Aula 10 NAO e repetido aqui. O professor pediu para nao
-- reaproveitar atividades anteriores dentro da entrega, e o banco ja existe
-- quando este arquivo comeca. Segue a descricao sintetica que o item 1 da
-- secao 5 do enunciado exige.
--
-- Tabelas do modelo individual (esquema normalizado da Aula 09, com as
-- restricoes da Aula 10):
--
--   modelo_aeronave  id_modelo PK, modelo (UNIQUE), fabricante.
--                    Existe porque modelo -> fabricante era dependencia
--                    transitiva em aeronave (3FN, Aula 09).
--
--   aeronave         id_aeronave PK, prefixo (UNIQUE), id_modelo FK ->
--                    modelo_aeronave, capacidade_assentos (> 0).
--                    A frota. capacidade_assentos e o teto de passagens de
--                    qualquer voo operado pela aeronave.
--
--   passageiro       id_passageiro PK, cpf (UNIQUE, aceita NULL para
--                    estrangeiro), nome, data_nascimento, email, telefone.
--
--   rota             id_rota PK, numero_voo (UNIQUE), origem e destino em
--                    codigo IATA de 3 letras maiusculas, origem <> destino.
--                    Existe porque numero_voo -> origem, destino era
--                    dependencia parcial em voo (2FN, Aula 09).
--
--   voo              id_voo PK, id_rota FK -> rota, id_aeronave FK ->
--                    aeronave, data_hora_partida, data_hora_chegada_prevista
--                    (posterior a partida), portao (aceita NULL: voo
--                    programado ainda nao tem portao), status em
--                    {Embarque, Confirmado, Aguardando, Cancelado}.
--                    UNIQUE (id_rota, data_hora_partida).
--                    Esta aula acrescenta a coluna passagens_vendidas.
--
--   passagem         id_passagem PK, id_passageiro FK, id_voo FK, assento,
--                    localizador (UNIQUE), classe em {Economica, Executiva,
--                    Primeira}, checkin_realizado.
--                    Associativa que resolve o N:N entre passageiro e voo.
--                    UNIQUE (id_passageiro, id_voo) e UNIQUE (id_voo,
--                    assento).
--
-- Objetos criados por este arquivo:
--
--   Desafio 1  trg_voo_capacidade_update        BEFORE UPDATE ON voo
--              trg_aeronave_capacidade_update   BEFORE UPDATE ON aeronave
--   Desafio 2  log_alteracao_voo                tabela de auditoria
--              trg_voo_auditoria_update         AFTER UPDATE ON voo
--   Desafio 3  voo.passagens_vendidas           coluna derivada
--              trg_passagem_vendidas_insert     AFTER INSERT ON passagem
--              trg_passagem_vendidas_delete     AFTER DELETE ON passagem
--              trg_passagem_vendidas_update     AFTER UPDATE ON passagem
--
-- Testado em MySQL 8.0.46 (contêiner Docker mysql:8.0).
-- =============================================================================

USE aeroporto;


-- =============================================================================
-- 1. DESAFIO 1 - Validacao de regra de negocio com BEFORE UPDATE
-- =============================================================================
--
-- REGRA: o numero de passagens vendidas para um voo nao pode exceder a
-- capacidade de assentos da aeronave escalada.
--
-- Esta regra ja existe no banco desde a Aula 10, em duas triggers sobre a
-- tabela passagem: trg_passagem_capacidade_insert e
-- trg_passagem_capacidade_update. Nao faz sentido reimplementa-las.
--
-- O que se faz aqui e fechar a LACUNA que elas deixam. As duas vigiam apenas a
-- tabela passagem, isto e, so reagem quando o NUMERADOR da regra (passagens
-- vendidas) aumenta. A regra, porem, tem dois lados, e o DENOMINADOR
-- (capacidade) mora em outra tabela. Existem duas portas dos fundos:
--
--   Porta 1 - UPDATE em voo trocando id_aeronave por uma aeronave cuja
--             capacidade e menor que o numero de passagens ja vendidas para
--             aquele voo. Nenhuma passagem foi criada; mesmo assim o voo passa
--             a ter mais passageiros do que assentos.
--
--   Porta 2 - UPDATE em aeronave reduzindo capacidade_assentos para um valor
--             abaixo das passagens ja vendidas em algum voo operado por ela.
--             De novo nenhuma passagem foi criada, e de novo o estado final
--             viola a regra - possivelmente em varios voos de uma vez.
--
-- As duas triggers abaixo fecham as duas portas. So com elas a regra de
-- capacidade da Aula 10 fica COMPLETA: o par insert/update sobre passagem
-- protege o numerador, e o par abaixo protege o denominador. Restricao que
-- vale de um lado e nao vale do outro e um buraco, do mesmo tipo que a Aula 10
-- fechou quando percebeu que a regra valia no INSERT e nao valia no UPDATE.
--
-- As duas sao BEFORE porque o enunciado pede validacao antes da persistencia:
-- o estado invalido nunca chega a existir na tabela, e a interrupcao e feita
-- com SIGNAL SQLSTATE '45000', que o cliente ve como erro 1644.


-- -----------------------------------------------------------------------------
-- O LIMITE DE 128 CARACTERES DO MESSAGE_TEXT
--
-- O MESSAGE_TEXT do SIGNAL aceita no maximo 128 caracteres, e passar disso NAO
-- trunca: o MySQL aborta com erro 1648 ("Data too long for condition item").
-- O efeito pratico e o pior possivel para uma recusa - o cliente recebe um
-- codigo que nao e o 1644 previsto e perde a explicacao do motivo. Foi o que
-- aconteceu na primeira execucao deste arquivo, com uma mensagem de 131
-- caracteres.
--
-- As duas mensagens abaixo foram reescritas para caber com folga: 64 e 58
-- caracteres com os ids do banco de exemplo, o que deixa mais de 60 de margem
-- para ids maiores. O LEFT(..., 128) permanece como GUARDA - nao e ele que faz
-- as mensagens caberem, e sim o texto curto. Ele existe para o caso extremo de
-- ids muito longos num banco de producao, onde e melhor uma mensagem cortada
-- do que um 1648 no lugar da recusa.


-- 1.1 trg_voo_capacidade_update - porta 1, troca de aeronave
-- -----------------------------------------------------------------------------
-- A verificacao so roda quando id_aeronave REALMENTE muda
-- (IF NEW.id_aeronave <> OLD.id_aeronave). Isso nao e economia de ciclos, e
-- requisito de corretude: o Desafio 3 faz a tabela passagem atualizar
-- voo.passagens_vendidas a cada venda, e esse UPDATE em voo dispara esta
-- trigger. Sem a guarda, toda venda de passagem executaria a contagem de
-- capacidade a toa e acoplaria dois mecanismos que nao tem relacao.
--
-- OLD e NEW sao usados juntos: OLD para detectar a troca, NEW para saber qual
-- aeronave sera validada.
--
-- POR QUE v_capacidade NAO TEM DEFAULT 0:
--
-- Se NEW.id_aeronave apontar para uma aeronave que nao existe, o
-- SELECT ... INTO nao acha linha nenhuma. No MySQL isso nao e erro: gera aviso
-- e deixa a variavel como estava. Com DEFAULT 0, v_capacidade valia 0, a
-- comparacao v_vendidas > 0 era verdadeira para qualquer voo com passagem
-- vendida, e a trigger recusava com 1644 dizendo "aeronave 9999 tem 0
-- assentos". A mensagem e falsa e o codigo e o errado: o problema nao esta na
-- capacidade, esta na chave estrangeira, e quem deve recusar e a
-- fk_voo_aeronave com o erro 1452.
--
-- Isso acontece porque a trigger BEFORE roda ANTES da verificacao de chave
-- estrangeira: ela sinaliza primeiro e o 1452 nunca chega ao cliente.
--
-- Com DEFAULT NULL e a guarda IS NOT NULL, a trigger nao opina sobre aeronave
-- que nao existe. Ela deixa passar, o InnoDB tenta gravar, a FK recusa e o
-- cliente recebe o 1452 correto. O teste T1.2b cobre esse caminho.

DROP TRIGGER IF EXISTS trg_voo_capacidade_update;

DELIMITER $$

CREATE TRIGGER trg_voo_capacidade_update
BEFORE UPDATE ON voo
FOR EACH ROW
BEGIN
    DECLARE v_capacidade INT DEFAULT NULL;
    DECLARE v_vendidas   INT DEFAULT 0;
    DECLARE v_msg        VARCHAR(255);

    IF NEW.id_aeronave <> OLD.id_aeronave THEN

        SELECT a.capacidade_assentos
          INTO v_capacidade
          FROM aeronave a
         WHERE a.id_aeronave = NEW.id_aeronave;

        SELECT COUNT(*)
          INTO v_vendidas
          FROM passagem p
         WHERE p.id_voo = OLD.id_voo;

        -- v_capacidade NULL significa aeronave inexistente: a recusa e da
        -- chave estrangeira (1452), nao desta trigger.
        IF v_capacidade IS NOT NULL AND v_vendidas > v_capacidade THEN
            SET v_msg = LEFT(CONCAT(
                'Troca recusada: voo ', OLD.id_voo, ' tem ', v_vendidas,
                ' passagens, aeronave ', NEW.id_aeronave, ' tem ',
                v_capacidade, ' assentos'), 128);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

    END IF;
END$$

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 1.2 trg_aeronave_capacidade_update - porta 2, reducao de capacidade
-- -----------------------------------------------------------------------------
-- Uma mesma aeronave opera varios voos (no banco de exemplo, a aeronave 1 opera
-- os voos 1 e 7). Reduzir a capacidade precisa ser comparado com o voo MAIS
-- CHEIO da aeronave, nao com um voo qualquer: basta um voo estourar para o
-- estado final ser invalido.
--
-- A verificacao so roda quando a capacidade DIMINUI. Aumentar capacidade nunca
-- viola a regra, e trocar o modelo ou o prefixo tambem nao.
--
-- SELECT ... INTO sem linhas, no MySQL, nao e erro: gera aviso e deixa as
-- variaveis como estavam. Por isso v_vendidas e v_voo nascem com DEFAULT, e
-- aeronave sem nenhuma passagem vendida cai no caminho do 0.

DROP TRIGGER IF EXISTS trg_aeronave_capacidade_update;

DELIMITER $$

CREATE TRIGGER trg_aeronave_capacidade_update
BEFORE UPDATE ON aeronave
FOR EACH ROW
BEGIN
    DECLARE v_vendidas INT DEFAULT 0;
    DECLARE v_voo      INT DEFAULT 0;
    DECLARE v_msg      VARCHAR(255);

    IF NEW.capacidade_assentos < OLD.capacidade_assentos THEN

        -- Voo mais cheio operado por esta aeronave.
        SELECT p.id_voo, COUNT(*)
          INTO v_voo, v_vendidas
          FROM passagem p
          JOIN voo v ON v.id_voo = p.id_voo
         WHERE v.id_aeronave = OLD.id_aeronave
         GROUP BY p.id_voo
         ORDER BY COUNT(*) DESC
         LIMIT 1;

        IF v_vendidas > NEW.capacidade_assentos THEN
            SET v_msg = LEFT(CONCAT(
                'Reducao recusada: voo ', v_voo, ' tem ', v_vendidas,
                ' passagens, capacidade nova ', NEW.capacidade_assentos), 128);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- 2. DESAFIO 2 - Auditoria com AFTER UPDATE em voo
-- =============================================================================
--
-- Voo e a entidade critica do modelo: e nela que a operacao do aeroporto
-- acontece no dia. As duas colunas que mudam durante a operacao sao status
-- (Aguardando -> Confirmado -> Embarque, ou Cancelado) e portao. Sao essas
-- duas que a auditoria monitora.
--
-- AFTER, e nao BEFORE, porque auditoria registra fato consumado. Se a gravacao
-- em voo falhar por qualquer restricao, o UPDATE nao acontece e a trigger AFTER
-- nao dispara - o log nao ganha uma linha sobre uma alteracao que nao existiu.


-- -----------------------------------------------------------------------------
-- 2.1 Tabela de auditoria
-- -----------------------------------------------------------------------------
-- Formato coluna-a-coluna (campo_alterado, valor_anterior, valor_posterior) em
-- vez de uma coluna por atributo auditado. Acrescentar um atributo ao
-- monitoramento passa a ser um IF a mais na trigger, e nao um ALTER TABLE.
--
-- Por que NAO existe FK de id_voo para voo, de proposito:
-- o objetivo da auditoria e sobreviver ao registro auditado. Com FK RESTRICT,
-- apagar um voo passaria a ser impossivel enquanto houvesse historico, o que
-- transformaria o log num bloqueio operacional. Com FK CASCADE, apagar o voo
-- apagaria junto exatamente as provas de como ele foi alterado - o pior
-- resultado possivel para uma trilha de auditoria, e o cenario em que ela mais
-- importa. Sem FK, id_voo e uma referencia historica: aponta para o voo que
-- existia no momento do evento, tenha ele sido apagado depois ou nao. E a
-- mesma razao pela qual nota fiscal guarda o nome do cliente em vez de so
-- apontar para o cadastro.
--
-- data_hora e TIMESTAMP DEFAULT CURRENT_TIMESTAMP: o carimbo e do SGBD, nao do
-- cliente. usuario recebe CURRENT_USER(), que e a conta autenticada pelo
-- servidor - tambem nao e informada pelo cliente. Auditoria cujo conteudo o
-- auditado escolhe nao serve para nada.

DROP TABLE IF EXISTS log_alteracao_voo;

CREATE TABLE log_alteracao_voo (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_voo          INT          NOT NULL,
    campo_alterado  VARCHAR(30)  NOT NULL,
    valor_anterior  VARCHAR(50)  NULL,
    valor_posterior VARCHAR(50)  NULL,
    data_hora       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario         VARCHAR(100) NOT NULL
) ENGINE = InnoDB;


-- -----------------------------------------------------------------------------
-- 2.2 trg_voo_auditoria_update
-- -----------------------------------------------------------------------------
-- Cada atributo monitorado tem seu proprio IF. Um UPDATE que mude status e
-- portao no mesmo comando gera DUAS linhas de log, uma por atributo, e nao uma
-- linha com dois campos misturados.
--
-- Grava-se apenas quando o valor REALMENTE mudou. UPDATE que reescreve o mesmo
-- valor e ruido operacional (formularios costumam reenviar o registro
-- inteiro); registra-lo encheria o log de linhas em que valor_anterior e
-- valor_posterior sao iguais, e uma trilha de auditoria so e util se toda linha
-- dela significar uma mudanca.
--
-- POR QUE portao USA <=> E status USA <>:
--
-- status e NOT NULL, entao OLD.status <> NEW.status e uma comparacao entre dois
-- valores conhecidos e se comporta como se espera.
--
-- portao aceita NULL - e a Aula 10 justifica: voo programado ainda nao tem
-- portao atribuido, e exigir portao impediria cadastrar o voo. Em SQL, qualquer
-- comparacao com NULL usando <> devolve NULL, nao TRUE nem FALSE, e IF trata
-- NULL como falso. Consequencia pratica: com OLD.portao <> NEW.portao, a
-- atribuicao do PRIMEIRO portao de um voo (NULL -> '22') nao seria registrada.
-- E justamente o evento mais comum da operacao de solo, e o que mais interessa
-- auditar, que passaria despercebido. A liberacao do portao ('11' -> NULL)
-- sumiria pelo mesmo motivo.
--
-- O operador <=> (NULL-safe equal) compara NULL como um valor comum:
-- NULL <=> NULL e verdadeiro, '11' <=> NULL e falso. Negando-o,
-- NOT (OLD.portao <=> NEW.portao) e verdadeiro exatamente quando houve
-- mudanca, inclusive nas transicoes que envolvem NULL. O teste T2.2 exercita
-- precisamente esse caso.

DROP TRIGGER IF EXISTS trg_voo_auditoria_update;

DELIMITER $$

CREATE TRIGGER trg_voo_auditoria_update
AFTER UPDATE ON voo
FOR EACH ROW
BEGIN

    IF OLD.status <> NEW.status THEN
        INSERT INTO log_alteracao_voo
            (id_voo, campo_alterado, valor_anterior, valor_posterior, usuario)
        VALUES
            (NEW.id_voo, 'status', OLD.status, NEW.status, CURRENT_USER());
    END IF;

    IF NOT (OLD.portao <=> NEW.portao) THEN
        INSERT INTO log_alteracao_voo
            (id_voo, campo_alterado, valor_anterior, valor_posterior, usuario)
        VALUES
            (NEW.id_voo, 'portao', OLD.portao, NEW.portao, CURRENT_USER());
    END IF;

END$$

DELIMITER ;


-- =============================================================================
-- 3. DESAFIO 3 - Sincronizacao com AFTER INSERT e AFTER DELETE
-- =============================================================================
--
-- Coluna derivada voo.passagens_vendidas, mantida pelo SGBD a cada venda,
-- devolucao ou remanejamento de passagem.
--
-- POR QUE ISSO CONTRADIZ A AULA 09, E POR QUE MESMO ASSIM ESTA AQUI:
--
-- A Aula 09 normalizou este banco ate a 5FN e removeu dependencias justamente
-- para que nenhum dado ficasse guardado em dois lugares. passagens_vendidas e
-- exatamente isso: COUNT(*) da tabela passagem materializado dentro de voo.
-- Pela 3FN estrita, a coluna nao deveria existir - e um valor calculavel.
--
-- E desnormalizacao CONTROLADA, e a palavra que importa e "controlada". O
-- ganho e leitura: ocupacao de voo e a consulta mais frequente do sistema
-- (painel de embarque, venda, check-in) e, sem a coluna, cada leitura precisa
-- agregar a tabela passagem, que e a maior do banco e a que mais cresce. Com a
-- coluna, a ocupacao de um voo e uma leitura de uma linha unica por chave
-- primaria.
--
-- O risco classico da desnormalizacao e a divergencia: o valor guardado e a
-- realidade se separam porque alguem esqueceu de atualizar. E aqui que a
-- trigger justifica a decisao. A manutencao nao depende de nenhum cliente
-- lembrar de nada: esta no SGBD, dispara para qualquer origem - aplicacao,
-- script, terminal mysql - e e o mesmo argumento que a Aula 08 usou para pôr
-- as regras de negocio no banco. Trocamos uma redundancia inevitavel por uma
-- garantia automatica. Sem a trigger, a coluna seria apenas um erro de
-- modelagem; com ela, e uma escolha de desempenho com a consistencia mantida
-- pelo proprio banco. O teste T3.4 confere o invariante para todos os voos.
--
-- POR QUE GUARDAR "VENDIDAS" E NAO "ASSENTOS DISPONIVEIS":
--
-- O enunciado sugere decrementar um saldo de assentos disponiveis. Aqui se
-- guarda o contador de vendidas, pelo seguinte motivo:
--
--   saldo = capacidade_assentos - vendidas
--
-- Guardar o saldo e guardar um valor que depende de DUAS tabelas. vendidas
-- depende so de passagem, e passagem e a unica tabela que as triggers deste
-- desafio vigiam. capacidade_assentos mora em aeronave e pode mudar sem que
-- nenhuma passagem seja tocada - exatamente os dois cenarios do Desafio 1:
-- trocar a aeronave do voo, ou alterar a capacidade da aeronave. Nos dois
-- casos, um saldo guardado ficaria errado na hora, calado, e para corrigi-lo
-- seria preciso uma terceira e uma quarta trigger recalculando o saldo de
-- todos os voos afetados.
--
-- Com o contador de vendidas isso nao acontece: trocar a aeronave nao muda
-- quantas passagens foram vendidas. O saldo continua disponivel a qualquer
-- momento, como conta de leitura:
--
--   SELECT a.capacidade_assentos - v.passagens_vendidas AS assentos_livres
--     FROM voo v JOIN aeronave a ON a.id_aeronave = v.id_aeronave;
--
-- A regra e guardar o dado mais estavel e derivar o resto na leitura.


-- -----------------------------------------------------------------------------
-- 3.1 Coluna derivada e carga do valor inicial
-- -----------------------------------------------------------------------------
-- CHECK (passagens_vendidas >= 0): contador de ocupacao negativo e estado
-- impossivel. Se algum dia uma trigger for alterada e passar a decrementar a
-- mais, o banco recusa em vez de guardar um absurdo silenciosamente.
--
-- O valor inicial vem da contagem REAL das passagens que ja existem. Comecar
-- com o DEFAULT 0 deixaria a coluna divergente desde o primeiro segundo: as
-- triggers so contam dali para a frente.

ALTER TABLE voo
    ADD COLUMN passagens_vendidas INT NOT NULL DEFAULT 0,
    ADD CONSTRAINT ck_voo_passagens_vendidas CHECK (passagens_vendidas >= 0);

UPDATE voo v
   SET v.passagens_vendidas = (SELECT COUNT(*)
                                 FROM passagem p
                                WHERE p.id_voo = v.id_voo);


-- -----------------------------------------------------------------------------
-- 3.2 AFTER INSERT - venda de passagem
-- -----------------------------------------------------------------------------
-- A alteracao secundaria usa a chave estrangeira contida em NEW (NEW.id_voo)
-- para delimitar a linha de voo a atualizar, como o requisito obrigatorio do
-- desafio exige.
--
-- Incremento relativo (passagens_vendidas + 1) e nao recontagem
-- (SET ... = SELECT COUNT(*) FROM passagem): recontar dentro de uma trigger
-- AFTER INSERT sobre passagem le a mesma tabela que o comando esta alterando, e
-- custa uma agregacao a cada venda. O incremento e O(1) e nao depende de reler
-- passagem.

DROP TRIGGER IF EXISTS trg_passagem_vendidas_insert;

DELIMITER $$

CREATE TRIGGER trg_passagem_vendidas_insert
AFTER INSERT ON passagem
FOR EACH ROW
BEGIN
    UPDATE voo
       SET passagens_vendidas = passagens_vendidas + 1
     WHERE id_voo = NEW.id_voo;
END$$

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 3.3 AFTER DELETE - devolucao ou cancelamento de passagem
-- -----------------------------------------------------------------------------
-- Simetrica a anterior, usando OLD.id_voo: em DELETE nao existe NEW.

DROP TRIGGER IF EXISTS trg_passagem_vendidas_delete;

DELIMITER $$

CREATE TRIGGER trg_passagem_vendidas_delete
AFTER DELETE ON passagem
FOR EACH ROW
BEGIN
    UPDATE voo
       SET passagens_vendidas = passagens_vendidas - 1
     WHERE id_voo = OLD.id_voo;
END$$

DELIMITER ;


-- -----------------------------------------------------------------------------
-- 3.4 AFTER UPDATE - remanejamento de passagem para outro voo
-- -----------------------------------------------------------------------------
-- O enunciado pede AFTER INSERT ou AFTER DELETE. Esta terceira trigger nao e
-- pedida, mas sem ela o contador DERIVA.
--
-- Remanejar um passageiro para outro voo e um UPDATE em passagem: nao ha
-- INSERT nem DELETE, nenhuma das duas triggers acima dispara, e mesmo assim um
-- voo perdeu um passageiro e outro ganhou. Os dois contadores ficariam errados
-- permanentemente, e nada no banco acusaria. E o mesmo raciocinio da Aula 10 ao
-- criar trg_passagem_capacidade_update: regra que vale no INSERT e nao vale no
-- UPDATE e uma regra contornavel.
--
-- A guarda IF NEW.id_voo <> OLD.id_voo e necessaria porque a maioria dos
-- UPDATE em passagem (check-in, troca de assento, mudanca de classe) nao move
-- o passageiro de voo e nao deve mexer em contador nenhum.

DROP TRIGGER IF EXISTS trg_passagem_vendidas_update;

DELIMITER $$

CREATE TRIGGER trg_passagem_vendidas_update
AFTER UPDATE ON passagem
FOR EACH ROW
BEGIN
    IF NEW.id_voo <> OLD.id_voo THEN

        UPDATE voo
           SET passagens_vendidas = passagens_vendidas - 1
         WHERE id_voo = OLD.id_voo;

        UPDATE voo
           SET passagens_vendidas = passagens_vendidas + 1
         WHERE id_voo = NEW.id_voo;

    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- 4. A CADEIA DE TRIGGERS
-- =============================================================================
--
-- Depois deste arquivo, um unico INSERT INTO passagem dispara quatro triggers,
-- em duas tabelas diferentes:
--
--   INSERT INTO passagem
--     |
--     +-- BEFORE INSERT ON passagem   trg_passagem_capacidade_insert (Aula 10)
--     |     le voo e aeronave, conta passagem, valida a capacidade
--     |
--     +-- (linha gravada em passagem)
--     |
--     +-- AFTER INSERT ON passagem    trg_passagem_vendidas_insert   (D3)
--           executa UPDATE voo SET passagens_vendidas = ... + 1
--             |
--             +-- BEFORE UPDATE ON voo  trg_voo_capacidade_update    (D1)
--             |     id_aeronave nao mudou -> a guarda corta, nada e verificado
--             |
--             +-- (linha gravada em voo)
--             |
--             +-- AFTER UPDATE ON voo   trg_voo_auditoria_update     (D2)
--                   status e portao nao mudaram -> nenhuma linha de log
--
-- Duas coisas precisavam ser verificadas nessa cadeia, e os testes da secao 5
-- verificam as duas:
--
-- 1. Erro 1442 ("Can't update table ... already used by statement"). O MySQL
--    proibe que uma trigger ALTERE a tabela que disparou o comando. A cadeia
--    respeita isso: a trigger sobre passagem altera voo, e as triggers sobre
--    voo nao alteram voo nem passagem - a de auditoria escreve em
--    log_alteracao_voo, que nenhuma trigger vigia, e a de capacidade so LE
--    passagem, o que e permitido (a propria trigger da Aula 10 ja fazia isso).
--    Nao ha ciclo. Se trg_voo_auditoria_update escrevesse de volta em voo, ou
--    se alguma trigger sobre voo tentasse recontar escrevendo em passagem, o
--    erro 1442 apareceria. Os testes T3.1 a T3.3 executam a cadeia inteira e
--    terminam sem ele.
--
-- 2. Disparo indevido das validacoes. As guardas IF do Desafio 1 e do Desafio 2
--    existem tambem para isso: sem elas, cada venda de passagem rodaria a
--    verificacao de capacidade e gravaria uma linha de auditoria falsa. O teste
--    T2.3 mostra que o log nao cresce quando nada muda de fato.


-- -----------------------------------------------------------------------------
-- 4.1 Objetos efetivamente criados
-- -----------------------------------------------------------------------------
-- Conferencia no dicionario do SGBD, e nao apenas no texto deste arquivo.

SELECT trigger_name, action_timing, event_manipulation, event_object_table
  FROM information_schema.triggers
 WHERE trigger_schema = 'aeroporto'
 ORDER BY event_object_table, action_timing, event_manipulation, trigger_name;

DESCRIBE log_alteracao_voo;
DESCRIBE voo;


-- =============================================================================
-- 5. BATERIA DE TESTES
-- =============================================================================
-- Segue a secao 4 do enunciado: para cada gatilho, um cenario invalido que deve
-- ser bloqueado e um cenario valido que deve passar.
--
-- Os erros 1644 que aparecem na saida sao ESPERADOS. Cada um vem precedido de
-- um marcador dizendo qual e e o que deveria acontecer.


-- -----------------------------------------------------------------------------
-- 5.0 Massa de teste
-- -----------------------------------------------------------------------------
-- Uma aeronave minuscula para tornar a violacao de capacidade demonstravel sem
-- inserir centenas de passagens. As aeronaves do banco tem de 106 a 220
-- assentos; o voo mais cheio tem 3 passagens.

INSERT INTO modelo_aeronave (modelo, fabricante) VALUES ('C208 Caravan', 'Cessna');

SET @id_modelo_teste = LAST_INSERT_ID();

INSERT INTO aeronave (prefixo, id_modelo, capacidade_assentos)
VALUES ('PT-TST', @id_modelo_teste, 2);

SET @id_aeronave_teste = LAST_INSERT_ID();

-- Estado de partida, para conferencia dos testes seguintes.
SELECT v.id_voo,
       v.id_aeronave,
       a.capacidade_assentos,
       v.passagens_vendidas,
       v.status,
       v.portao
  FROM voo v
  JOIN aeronave a ON a.id_aeronave = v.id_aeronave
 ORDER BY v.id_voo;


-- =============================================================================
-- 5.1 DESAFIO 1 - trg_voo_capacidade_update (troca de aeronave)
-- =============================================================================

SELECT '--- T1.1 INVALIDO: por a aeronave PT-TST (2 assentos) no voo 1, que tem 3 passagens. Esperado: ERRO 1644 ---' AS teste;

UPDATE voo SET id_aeronave = @id_aeronave_teste WHERE id_voo = 1;

-- Contraprova de que o UPDATE nao foi aplicado: a aeronave do voo 1 continua
-- sendo a original. BEFORE cumpriu seu papel, o estado invalido nunca existiu.
SELECT id_voo, id_aeronave, passagens_vendidas FROM voo WHERE id_voo = 1;


SELECT '--- T1.2 VALIDO: por a mesma aeronave PT-TST no voo 8, que tem 0 passagens. Esperado: sucesso ---' AS teste;

UPDATE voo SET id_aeronave = @id_aeronave_teste WHERE id_voo = 8;

SELECT v.id_voo, v.id_aeronave, a.prefixo, a.capacidade_assentos, v.passagens_vendidas
  FROM voo v JOIN aeronave a ON a.id_aeronave = v.id_aeronave
 WHERE v.id_voo = 8;

-- Devolve o voo 8 a aeronave original, para nao contaminar os testes seguintes.
UPDATE voo SET id_aeronave = 2 WHERE id_voo = 8;


SELECT '--- T1.2b INVALIDO POR OUTRO MOTIVO: por no voo 1 uma aeronave que NAO EXISTE (9999). Esperado: ERRO 1452 da chave estrangeira, e NAO 1644 da trigger ---' AS teste;

-- A trigger nao deve opinar aqui. Com v_capacidade DEFAULT 0 ela recusava com
-- 1644 "aeronave 9999 tem 0 assentos", escondendo a causa real e devolvendo o
-- codigo errado. Com DEFAULT NULL e a guarda IS NOT NULL, a validacao de
-- capacidade e ignorada e quem recusa e a fk_voo_aeronave.
UPDATE voo SET id_aeronave = 9999 WHERE id_voo = 1;

-- Contraprova: o voo 1 continua com a aeronave original.
SELECT id_voo, id_aeronave, passagens_vendidas FROM voo WHERE id_voo = 1;


-- =============================================================================
-- 5.2 DESAFIO 1 - trg_aeronave_capacidade_update (reducao de capacidade)
-- =============================================================================
-- A aeronave 1 opera o voo 1 (3 passagens) e o voo 7 (1 passagem). O voo mais
-- cheio e o 1, com 3.

SELECT '--- T1.3 INVALIDO: reduzir a aeronave 1 de 180 para 2 assentos. Esperado: ERRO 1644 citando o voo 1 ---' AS teste;

UPDATE aeronave SET capacidade_assentos = 2 WHERE id_aeronave = 1;

SELECT id_aeronave, prefixo, capacidade_assentos FROM aeronave WHERE id_aeronave = 1;


SELECT '--- T1.4 VALIDO: reduzir a mesma aeronave 1 de 180 para 100 assentos, acima das 3 vendidas. Esperado: sucesso ---' AS teste;

UPDATE aeronave SET capacidade_assentos = 100 WHERE id_aeronave = 1;

SELECT id_aeronave, prefixo, capacidade_assentos FROM aeronave WHERE id_aeronave = 1;


SELECT '--- T1.5 LIMITE: reduzir a aeronave 1 para exatamente 3 assentos, igual as 3 vendidas. Esperado: sucesso, a regra e "exceder", nao "atingir" ---' AS teste;

UPDATE aeronave SET capacidade_assentos = 3 WHERE id_aeronave = 1;

SELECT id_aeronave, prefixo, capacidade_assentos FROM aeronave WHERE id_aeronave = 1;

-- E agora um assento a menos que as vendidas, que deve ser recusado.
SELECT '--- T1.6 LIMITE INVALIDO: reduzir a aeronave 1 para 2 assentos, um a menos que as 3 vendidas. Esperado: ERRO 1644 ---' AS teste;

UPDATE aeronave SET capacidade_assentos = 2 WHERE id_aeronave = 1;

-- Restaura a capacidade original. Aumentar nunca dispara a verificacao.
UPDATE aeronave SET capacidade_assentos = 180 WHERE id_aeronave = 1;

SELECT id_aeronave, prefixo, capacidade_assentos FROM aeronave WHERE id_aeronave = 1;


-- =============================================================================
-- 5.3 DESAFIO 2 - trg_voo_auditoria_update (auditoria)
-- =============================================================================

SELECT '--- T2.1 status: voo 5 de Aguardando para Cancelado ---' AS teste;

UPDATE voo SET status = 'Cancelado' WHERE id_voo = 5;


SELECT '--- T2.2 portao: voo 8 de 11 para NULL (liberacao) e depois de NULL para 22 (primeira atribuicao). E o caso que <> perderia ---' AS teste;

UPDATE voo SET portao = NULL WHERE id_voo = 8;
UPDATE voo SET portao = '22' WHERE id_voo = 8;

-- As duas transicoes acima envolvem NULL de um dos lados. Com
-- OLD.portao <> NEW.portao a condicao avaliaria NULL nas duas, IF trataria NULL
-- como falso e o log ficaria VAZIO. O <=> registra as duas.


SELECT '--- T2.2b os dois campos no mesmo UPDATE: voo 3 muda status e portao de uma vez. Esperado: DUAS linhas de log, uma por campo ---' AS teste;

UPDATE voo SET status = 'Confirmado', portao = '31' WHERE id_voo = 3;


SELECT '--- Log completo (SELECT *), com valor anterior, posterior, data_hora e usuario ---' AS teste;

SELECT * FROM log_alteracao_voo ORDER BY id_log;


SELECT '--- T2.3 UPDATE que nao muda valor nenhum: reescreve status e portao do voo 5 com os mesmos valores. Esperado: o log NAO cresce ---' AS teste;

SELECT COUNT(*) AS linhas_no_log_antes FROM log_alteracao_voo;

UPDATE voo SET status = 'Cancelado', portao = '07' WHERE id_voo = 5;

SELECT ROW_COUNT() AS linhas_afetadas_pelo_update;

SELECT COUNT(*) AS linhas_no_log_depois FROM log_alteracao_voo;

-- linhas_afetadas_pelo_update = 0 porque o MySQL nao reescreve linha cujo
-- conteudo nao mudou, mas a trigger AFTER UPDATE dispara de qualquer forma
-- (FOR EACH ROW vale para as linhas que casaram com o WHERE). A prova de que
-- os IF estao corretos e o contador do log, que fica igual.


SELECT '--- T2.4 UPDATE em coluna NAO monitorada: muda a chegada prevista do voo 5. Esperado: o log NAO cresce ---' AS teste;

UPDATE voo SET data_hora_chegada_prevista = '2026-09-01 13:50:00' WHERE id_voo = 5;

SELECT COUNT(*) AS linhas_no_log_depois FROM log_alteracao_voo;


-- =============================================================================
-- 5.4 DESAFIO 3 - contador passagens_vendidas
-- =============================================================================
-- Roteiro da secao 4.3 do enunciado: consultar antes, executar o DML, consultar
-- depois.

SELECT '--- T3.1 INSERT de passagem. Contador do voo 1 ANTES ---' AS teste;

SELECT id_voo, passagens_vendidas FROM voo WHERE id_voo = 1;

SELECT COUNT(*) AS contagem_real_passagem FROM passagem WHERE id_voo = 1;

INSERT INTO passagem (id_passageiro, id_voo, assento, localizador, classe, checkin_realizado)
VALUES (4, 1, '15C', 'TST001', 'Economica', FALSE);

SELECT '--- Contador do voo 1 DEPOIS do INSERT. Esperado: 3 -> 4, sem erro 1442 na cadeia ---' AS teste;

SELECT id_voo, passagens_vendidas FROM voo WHERE id_voo = 1;


SELECT '--- T3.2 DELETE da mesma passagem. Esperado: 4 -> 3 ---' AS teste;

DELETE FROM passagem WHERE localizador = 'TST001';

SELECT id_voo, passagens_vendidas FROM voo WHERE id_voo = 1;


SELECT '--- T3.3 Remanejamento: mover a passagem MNO501 do voo 5 para o voo 2. Contadores ANTES ---' AS teste;

SELECT id_voo, passagens_vendidas FROM voo WHERE id_voo IN (2, 5) ORDER BY id_voo;

UPDATE passagem SET id_voo = 2 WHERE localizador = 'MNO501';

SELECT '--- Contadores DEPOIS. Esperado: voo 5 de 1 -> 0 e voo 2 de 2 -> 3 ---' AS teste;

SELECT id_voo, passagens_vendidas FROM voo WHERE id_voo IN (2, 5) ORDER BY id_voo;


-- -----------------------------------------------------------------------------
-- T3.4 Invariante: o contador bate com a contagem real em TODOS os voos
-- -----------------------------------------------------------------------------
-- Esta e a prova de que a desnormalizacao esta sob controle. Depois de um
-- INSERT, um DELETE, um remanejamento e duas trocas de aeronave, o valor
-- guardado ainda e igual ao COUNT(*) da tabela passagem em todos os voos.

SELECT '--- T3.4 Contador guardado x contagem real, voo a voo ---' AS teste;

SELECT v.id_voo,
       v.passagens_vendidas                AS guardado,
       COALESCE(p.total, 0)                AS real_count,
       IF(v.passagens_vendidas = COALESCE(p.total, 0), 'OK', 'DIVERGENTE') AS conferencia
  FROM voo v
  LEFT JOIN (SELECT id_voo, COUNT(*) AS total FROM passagem GROUP BY id_voo) p
         ON p.id_voo = v.id_voo
 ORDER BY v.id_voo;

SELECT '--- T3.4 Resumo: divergencias encontradas (esperado: 0) ---' AS teste;

SELECT COUNT(*) AS voos_divergentes
  FROM voo v
  LEFT JOIN (SELECT id_voo, COUNT(*) AS total FROM passagem GROUP BY id_voo) p
         ON p.id_voo = v.id_voo
 WHERE v.passagens_vendidas <> COALESCE(p.total, 0);


-- -----------------------------------------------------------------------------
-- 5.5 Saldo de assentos derivado na leitura
-- -----------------------------------------------------------------------------
-- Demonstra o argumento da secao 3: o saldo nao precisa ser guardado, porque e
-- uma subtracao sobre o contador estavel e a capacidade atual da aeronave.

SELECT r.numero_voo,
       a.prefixo,
       a.capacidade_assentos,
       v.passagens_vendidas,
       a.capacidade_assentos - v.passagens_vendidas AS assentos_livres
  FROM voo v
  JOIN rota r     ON r.id_rota     = v.id_rota
  JOIN aeronave a ON a.id_aeronave = v.id_aeronave
 ORDER BY v.id_voo;


-- =============================================================================
-- 6. Fim
-- =============================================================================
-- Resumo do que foi demonstrado:
--   D1  duas portas dos fundos da regra de capacidade da Aula 10 fechadas,
--       com recusa por SIGNAL (1644) e aceitacao do caso valido, inclusive no
--       limite exato (T1.5 e T1.6). A trigger tambem se cala quando a aeronave
--       nao existe, deixando a chave estrangeira recusar com 1452 (T1.2b).
--   D2  auditoria de status e portao com OLD e NEW, incluindo a transicao a
--       partir de NULL que o operador <> perderia, e nenhum registro quando
--       nada muda de fato.
--   D3  contador derivado mantido pelo SGBD em INSERT, DELETE e remanejamento,
--       conferido contra a contagem real de todos os voos.
