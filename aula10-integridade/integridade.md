# Aula 10 — Regras de integridade do banco de dados

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Identificação, implementação e teste das regras de integridade do banco `aeroporto`. A
base é o **esquema normalizado da Aula 09**, com seis tabelas, e não o esquema de quatro
tabelas da Aula 08.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `sql_integridade.sql` | Recria o banco inteiro já com as regras de integridade |
| `integridade.md` | Esta análise e os resultados dos testes |

O `sql_integridade.sql` é autocontido: roda do zero, cria as seis tabelas com as
restrições, as duas triggers e os dados de exemplo.

## O que mudou em relação à Aula 09

Quatro regras novas, mais duas triggers:

| Regra | Onde |
|---|---|
| `ck_voo_chegada_apos_partida` | `voo` — chegada prevista posterior à partida |
| `ck_rota_origem_iata` | `rota` — origem no formato IATA |
| `ck_rota_destino_iata` | `rota` — destino no formato IATA |
| `trg_passagem_capacidade_insert` / `_update` | `passagem` — capacidade da aeronave |

**Uma observação de honestidade sobre o escopo:** o `NOT NULL` em
`modelo_aeronave.fabricante` já existia no esquema da Aula 09 — a coluna nasceu
`VARCHAR(50) NOT NULL` quando a tabela foi extraída. Ele está documentado e testado aqui
(teste T20), mas é regra **herdada**, não acrescentada nesta aula. Registro a distinção
para não contabilizar como trabalho novo algo que já estava feito.

---

## 1. Integridade de entidade

> Toda tabela deve ter uma chave primária, e nenhuma parte dela pode ser nula ou
> duplicada.

**Problema que evita:** linha sem identidade. Sem chave primária, não há como referenciar
um registro específico, não há como impedir duplicatas exatas e nenhuma chave estrangeira
pode apontar para ele. Duas passagens idênticas seriam indistinguíveis e o cancelamento
de uma cancelaria as duas.

**Implementação:** `PRIMARY KEY` em cada uma das seis tabelas.

| Tabela | Chave primária |
|---|---|
| `modelo_aeronave` | `id_modelo INT AUTO_INCREMENT` |
| `aeronave` | `id_aeronave INT AUTO_INCREMENT` |
| `passageiro` | `id_passageiro INT AUTO_INCREMENT` |
| `rota` | `id_rota INT AUTO_INCREMENT` |
| `voo` | `id_voo INT AUTO_INCREMENT` |
| `passagem` | `id_passagem INT AUTO_INCREMENT` |

O `PRIMARY KEY` do MySQL já implica `NOT NULL` e `UNIQUE`, então a integridade de entidade
está garantida pela própria declaração, sem restrição adicional.

### Por que chave substituta em todas as tabelas

Todas as seis usam `AUTO_INCREMENT` em vez da chave natural. A decisão vem da Aula 05 e
tem três motivos concretos neste domínio:

**O caso que forçou a decisão foi o CPF.** `passageiro.cpf` é a chave natural óbvia, mas
**passageiro estrangeiro não tem CPF** — Henrik Johansson, nos dados de exemplo, entra com
`cpf` nulo. Chave primária não aceita nulo. Usar o CPF como PK excluiria estrangeiros do
sistema, o que é inaceitável para um aeroporto. O CPF permanece como chave candidata,
declarada `UNIQUE` e aceitando nulo.

**Chave natural muda; chave substituta não.** Um prefixo de aeronave pode ser
reatribuído, um número de voo pode ser remanejado entre temporadas. Quando a chave natural
muda, toda linha que a referencia precisa mudar junto. Com chave substituta, a mudança é
um `UPDATE` em uma coluna e as referências continuam válidas.

**Chave composta se propaga.** A chave natural de `voo` é o par
`(numero_voo, data_hora_partida)`. Como PK, esse par apareceria em `passagem` como duas
colunas de chave estrangeira, e em qualquer tabela futura que referenciasse passagem, a
chave cresceria de novo. O `id_voo` mantém as referências com uma coluna.

O custo é que a chave substituta não impede duplicata semântica: dois registros com
`id` diferente e o mesmo conteúdo real. É exatamente por isso que **toda chave natural foi
preservada como `UNIQUE`**, o que é o assunto da seção 4.

### Um detalhe do MySQL que muda como a integridade de entidade se testa

A metade "não duplicada" da regra se demonstra por `INSERT`: repetir uma chave existente
retorna 1062, e é o teste T01.

A metade "não nula" **não se demonstra por `INSERT`**. O MySQL trata `NULL` em coluna
`AUTO_INCREMENT` como **pedido de geração de valor**, e não como violação: o comando

```sql
INSERT INTO passageiro (id_passageiro, nome) VALUES (NULL, 'Teste');
```

é aceito sem erro nenhum, e o servidor grava o próximo id da sequência. Verificado — o
registro entrou com `id_passageiro = 9`.

A recusa só aparece ao tentar **apagar** um valor de chave já existente:

```sql
UPDATE passageiro SET id_passageiro = NULL WHERE id_passageiro = 1;
-- ERROR 1048 (23000): Column 'id_passageiro' cannot be null
```

Por isso o teste da nulidade da chave primária é um `UPDATE`, e está na seção 9.1.1 junto
com as demais recusas em atualização. Tratá-lo como `INSERT` daria um falso negativo: o
comando passaria e o teste pareceria ter provado algo que não provou.

**Testes:** T01 (PK duplicada), T02 (PK nula, por `UPDATE` — seção 9.1.1).

---

## 2. Integridade referencial

> Toda chave estrangeira deve apontar para uma linha que existe, e a ação sobre a linha
> referenciada precisa ser definida.

**Problema que evita:** registro órfão. Uma passagem apontando para um voo que não existe
é um bilhete para lugar nenhum; um voo apontando para uma aeronave inexistente não pode
ter capacidade calculada nem ocupação verificada.

### As cinco chaves estrangeiras

```
aeronave.id_modelo     → modelo_aeronave.id_modelo
voo.id_rota            → rota.id_rota
voo.id_aeronave        → aeronave.id_aeronave
passagem.id_passageiro → passageiro.id_passageiro
passagem.id_voo        → voo.id_voo
```

Duas delas — `fk_aeronave_modelo` e `fk_voo_rota` — são novas, nascidas das decomposições
da Aula 09, e não tinham documentação de integridade até aqui.

### `ON DELETE RESTRICT` em todas as cinco — a justificativa caso a caso

As cinco usam `RESTRICT`, mas pelo mesmo motivo aplicado a situações diferentes. O que
importa é **o que `CASCADE` faria em cada caso concreto**:

**`passagem.id_voo → voo`.** Com `ON DELETE CASCADE`, apagar um voo apagaria em silêncio
**todas as passagens vendidas para ele**. Um operador cancelando um voo por engano
destruiria o registro comercial de dezenas de bilhetes pagos — sem aviso, sem log, sem
recuperação. É a consequência mais grave do modelo inteiro. Com `RESTRICT`, a exclusão é
recusada e a operação correta fica evidente: cancelar o voo é mudar `status` para
`'Cancelado'`, o que preserva as passagens e o histórico, e é justamente para isso que o
domínio de `status` inclui esse valor.

**`voo.id_aeronave → aeronave`.** Com `CASCADE`, retirar uma aeronave da frota apagaria
**todos os voos dela** — e, pela cascata seguinte, todas as passagens desses voos. Uma
aeronave enviada para manutenção prolongada levaria consigo a agenda inteira e o histórico
de operação. Com `RESTRICT`, o banco obriga a resolver antes: remanejar os voos para outra
aeronave, e só então dar baixa.

**`voo.id_rota → rota`.** Com `CASCADE`, descontinuar uma rota apagaria todas as
ocorrências passadas e futuras daquele número de voo. O histórico operacional sumiria
junto com a decisão comercial de encerrar o trecho. Com `RESTRICT`, a rota só sai depois
que não houver mais voos associados.

**`aeronave.id_modelo → modelo_aeronave`.** Com `CASCADE`, apagar um modelo apagaria
**todas as aeronaves daquele modelo**, e em cascata seus voos e passagens. Um registro de
catálogo derrubando a frota é desproporcional: modelo é dado de referência, não dado
operacional. Com `RESTRICT`, o catálogo não pode ser esvaziado por baixo da frota.

**`passagem.id_passageiro → passageiro`.** Com `CASCADE`, excluir um cadastro de
passageiro apagaria **todas as passagens dele**, incluindo voos já realizados. Além da
perda de histórico, isso quebraria a conciliação financeira: o bilhete foi pago e o voo
aconteceu, mesmo que o cadastro seja removido. Com `RESTRICT`, a exclusão é recusada
enquanto houver passagem, o que é o comportamento correto — cadastro de quem já voou não
se apaga.

O padrão comum: **nas cinco relações, o registro referenciado é o dado de referência e o
referenciador é o dado operacional com valor histórico ou financeiro.** Em nenhuma delas a
exclusão do pai deveria significar "esse fato nunca aconteceu". `CASCADE` só faria sentido
para relação de composição verdadeira, em que o filho não tem existência independente — o
que não ocorre em nenhum ponto deste modelo.

### `ON UPDATE CASCADE` em todas as cinco

Aqui a escolha é oposta, e por uma razão simétrica: se a chave primária referenciada
mudar, todas as referências **devem** acompanhar, ou o banco fica inconsistente na hora.
`RESTRICT` no update impediria a correção de uma chave; `CASCADE` propaga.

Na prática o caso é raro, porque as chaves são `AUTO_INCREMENT` e não têm motivo para
mudar. `ON UPDATE CASCADE` está declarado como salvaguarda: se uma renumeração for
necessária em manutenção, ela funciona sem quebrar referência.

**Testes:** T03 a T06 e T32 (inserção com FK inexistente), T07 a T11 (exclusão de pai com
filhos). As cinco chaves estrangeiras são testadas nas duas direções.

---

## 3. Integridade de domínio

> Todo atributo deve aceitar apenas valores do conjunto que faz sentido para ele.

**Problema que evita:** dado sintaticamente válido e semanticamente absurdo. Um status
`'embarcando'` que o painel não sabe exibir, uma capacidade zero, um voo que chega antes
de partir.

### Tipo e tamanho

O tipo é a primeira linha de defesa de domínio, escolhida por atributo:

| Coluna | Tipo | Justificativa |
|---|---|---|
| `cpf` | `CHAR(11)` | Tamanho fixo, sem pontuação. `CHAR` e não `VARCHAR` porque o comprimento nunca varia; os separadores ficam fora porque não carregam informação. |
| `origem`, `destino` | `CHAR(3)` | Código IATA tem exatamente três caracteres. |
| `portao` | `VARCHAR(5)` | Texto e não número: tem zero à esquerda (`08`, `04`) e é identificador, não quantidade. Ninguém soma portões. |
| `data_hora_partida` | `DATETIME` | Data e hora no mesmo campo, porque a identidade da ocorrência do voo é o instante completo. |
| `capacidade_assentos` | `INT` | Quantidade, admite comparação e agregação. |
| `checkin_realizado` | `BOOLEAN` | Dois estados. |
| `localizador` | `CHAR(6)` | Padrão de seis caracteres do setor. |

### `CHECK`

Sete restrições de verificação, três delas novas nesta aula:

| Restrição | Regra | Novo? |
|---|---|---|
| `ck_aeronave_capacidade` | `capacidade_assentos > 0` | herdada |
| `ck_voo_status` | `status IN ('Embarque','Confirmado','Aguardando','Cancelado')` | herdada |
| `ck_passagem_classe` | `classe IN ('Economica','Executiva','Primeira')` | herdada |
| `ck_rota_origem_destino` | `origem <> destino` | herdada (migrou de `voo` na Aula 09) |
| `ck_voo_chegada_apos_partida` | `data_hora_chegada_prevista > data_hora_partida` | **novo** |
| `ck_rota_origem_iata` | `REGEXP_LIKE(origem, '^[A-Z]{3}$', 'c')` | **novo** |
| `ck_rota_destino_iata` | `REGEXP_LIKE(destino, '^[A-Z]{3}$', 'c')` | **novo** |

**`ck_voo_chegada_apos_partida`** evita viagem no tempo: previsão de chegada anterior à
partida. O erro é fácil de cometer em voo que cruza a meia-noite, digitando a data do dia
anterior. Um detalhe importante do comportamento: **a restrição não impede voo sem
previsão de chegada**. Quando `data_hora_chegada_prevista` é `NULL`, a comparação avalia
como `UNKNOWN`, e o SQL aceita `CHECK` que não seja explicitamente falso. Um voo
programado sem horário de chegada definido continua entrando (contraprova C05).

**`ck_rota_*_iata`** garante o formato do código de aeroporto: exatamente três letras
maiúsculas. Sem ele, `BS1`, `bsb` ou `GR` entrariam e quebrariam qualquer integração com
sistema externo, que espera o padrão IATA.

O terceiro argumento `'c'` do `REGEXP_LIKE` **não é decorativo**. A collation do banco é
`utf8mb4_unicode_ci`, que é *case-insensitive*; sem forçar o modo sensível a caixa, o
padrão `^[A-Z]{3}$` aceitaria `bsb` em minúsculas e a restrição não faria o que promete.
O teste T16 verifica exatamente isso.

### `DEFAULT`

| Coluna | Default | Justificativa |
|---|---|---|
| `voo.status` | `'Aguardando'` | Todo voo nasce aguardando; o valor evita `NULL` em coluna obrigatória e reflete o estado inicial real. |
| `passagem.classe` | `'Economica'` | A maioria esmagadora das vendas; o default reduz erro de digitação. |
| `passagem.checkin_realizado` | `FALSE` | Passagem recém-emitida nunca tem check-in feito. |

`DEFAULT` é integridade de domínio no sentido preventivo: em vez de recusar o valor
errado, fornece o certo quando nenhum é informado.

**Testes:** T12 a T19; e T34, que viola o domínio de `status` por `UPDATE` em vez de
`INSERT` (seção 9.1.1).

---

## 4. Integridade de chave

> Toda chave candidata da relação deve ser declarada, não apenas a que virou chave
> primária.

**Problema que evita:** duplicata semântica. Como todas as PKs são substitutas, o banco
sozinho não impediria dois registros com `id` diferente representando a mesma coisa real
— dois cadastros do mesmo CPF, duas rotas com o mesmo número de voo. **A chave substituta
resolve identidade, não unicidade.** Declarar as chaves candidatas é o que fecha essa
lacuna.

### Chaves candidatas por tabela

| Tabela | PK | Demais chaves candidatas |
|---|---|---|
| `modelo_aeronave` | `id_modelo` | `modelo` |
| `aeronave` | `id_aeronave` | `prefixo` |
| `passageiro` | `id_passageiro` | `cpf` (parcial — aceita nulo) |
| `rota` | `id_rota` | `numero_voo` |
| `voo` | `id_voo` | `(id_rota, data_hora_partida)` |
| `passagem` | `id_passagem` | `localizador`; `(id_passageiro, id_voo)`; `(id_voo, assento)` |

`passagem` tem **quatro** chaves candidatas — uma primária e três alternativas —, cada uma
representando uma regra de negócio distinta. Isso é tratado na seção 7.

O caso do `cpf` é o único parcial: ele identifica unicamente quem o tem, mas nem todo
passageiro tem. Por isso é chave candidata para fins de unicidade e não pode ser chave
primária.

**Testes:** T23 a T30.

---

## 5. Restrições de unicidade

> Nenhum valor de chave candidata pode se repetir.

Oito restrições `UNIQUE`, três delas compostas.

| Restrição | Tabela | Colunas | Problema que evita |
|---|---|---|---|
| `uq_modelo_aeronave_modelo` | `modelo_aeronave` | `modelo` | Mesmo modelo cadastrado duas vezes, possivelmente com fabricantes divergentes — reintroduzindo pela porta dos fundos a inconsistência que a 3FN eliminou. |
| `uq_aeronave_prefixo` | `aeronave` | `prefixo` | Duas aeronaves com a mesma matrícula. O prefixo é identificador internacional único. |
| `uq_passageiro_cpf` | `passageiro` | `cpf` | Mesma pessoa cadastrada duas vezes, com histórico de voos fragmentado entre os dois cadastros. |
| `uq_rota_numero_voo` | `rota` | `numero_voo` | Ver abaixo — é a mais importante das oito. |
| `uq_voo_rota_partida` | `voo` | `(id_rota, data_hora_partida)` | O mesmo voo partindo duas vezes no mesmo instante. |
| `uq_passagem_localizador` | `passagem` | `localizador` | Dois bilhetes com o mesmo código de reserva. |
| `uq_passagem_passageiro_voo` | `passagem` | `(id_passageiro, id_voo)` | Mesmo passageiro ocupando dois assentos no mesmo voo. Era o desafio da Aula 05. |
| `uq_passagem_voo_assento` | `passagem` | `(id_voo, assento)` | Dois passageiros no mesmo assento — overbooking de poltrona. |

### Sobre `uq_rota_numero_voo`

Esta merece destaque porque **não é uma restrição isolada: ela sustenta outra.**

Na Aula 08, a regra "o mesmo número de voo não pode partir duas vezes no mesmo instante"
era `uq_voo_numero_partida UNIQUE (numero_voo, data_hora_partida)`, direto na tabela `voo`.

Com a normalização da Aula 09, `numero_voo` saiu de `voo` e foi para `rota`. A restrição
foi reescrita como `uq_voo_rota_partida UNIQUE (id_rota, data_hora_partida)`.

**A equivalência entre as duas só existe porque `numero_voo` é `UNIQUE` em `rota`.** Sem
`uq_rota_numero_voo`, dois `id_rota` diferentes poderiam carregar o mesmo `numero_voo`, e
o mesmo número partiria duas vezes no mesmo instante por rotas distintas sem que
`uq_voo_rota_partida` percebesse. A regra ficaria **mais fraca do que era na Aula 08** —
uma regressão silenciosa introduzida pela normalização.

As duas restrições trabalham juntas e nenhuma delas sozinha entrega a regra.

**Confirmado no dicionário do SGBD, não apenas neste texto.** A consulta a
`information_schema.table_constraints` executada no banco criado retorna:

```
CONSTRAINT_NAME       CONSTRAINT_TYPE   TABLE_NAME
uq_rota_numero_voo    UNIQUE            rota
```

O teste T26 verifica o comportamento.

### `UNIQUE` e `NULL`

`uq_passageiro_cpf` aceita vários passageiros com `cpf` nulo. No padrão SQL, `NULL` não é
igual a `NULL`, então múltiplos nulos não conflitam em restrição de unicidade. É o que
permite cadastrar quantos estrangeiros forem necessários sem afrouxar a regra para quem
tem CPF. Contraprova C01.

---

## 6. Obrigatoriedade de preenchimento

> Coluna sem a qual o registro não faz sentido deve ser `NOT NULL`.

**Problema que evita:** registro incompleto que o sistema não consegue processar. Um voo
sem data de partida não pode ser ordenado no painel; uma passagem sem assento não permite
embarque.

### Colunas obrigatórias

| Tabela | `NOT NULL` | Por quê |
|---|---|---|
| `modelo_aeronave` | `modelo`, `fabricante` | Um modelo sem fabricante não identifica nada. Era exatamente a dependência `modelo → fabricante` que motivou a extração da tabela na Aula 09; permitir fabricante nulo esvaziaria o propósito dela. |
| `aeronave` | `prefixo`, `id_modelo`, `capacidade_assentos` | Sem prefixo a aeronave não é identificável; sem capacidade não há controle de ocupação nem a regra de negócio da seção 7. |
| `passageiro` | `nome` | Único dado sem o qual não há passageiro. |
| `rota` | `numero_voo`, `origem`, `destino` | Uma rota é, por definição, um número ligando dois pontos. |
| `voo` | `id_rota`, `id_aeronave`, `data_hora_partida`, `status` | Voo sem aeronave escalada não opera; sem partida não é agendável; `status` tem `DEFAULT`, então nunca fica nulo por omissão. |
| `passagem` | `id_passageiro`, `id_voo`, `assento`, `localizador`, `classe`, `checkin_realizado` | Todos os seis compõem o bilhete. `classe` e `checkin_realizado` têm `DEFAULT`. |

### As colunas que aceitam nulo — e por quê

Esta é a parte que exige justificativa, porque **cada `NOT NULL` ausente é uma decisão,
não um esquecimento**:

**`passageiro.cpf`.** Passageiro estrangeiro não tem CPF. Decisão de modelagem da Aula 05,
e a razão de a chave primária ser substituta. Exigir o preenchimento excluiria estrangeiros
do sistema.

**`passageiro.email` e `passageiro.telefone`.** São canais de contato, não identidade. Um
passageiro que compra no balcão pode não fornecer nenhum dos dois, e recusar a venda por
isso seria transformar uma conveniência em obstáculo.

**`passageiro.data_nascimento`.** Relevante para tarifa de menor e política de menor
desacompanhado, mas não para emitir o bilhete.

**`voo.portao`.** O portão só é atribuído perto do embarque, muitas vezes horas depois de
o voo entrar na programação. Ver a seção 8 — é um caso explícito de restrição que
impediria operação válida.

**`voo.data_hora_chegada_prevista`.** Um voo pode ser programado antes de a previsão de
chegada ser calculada. O `CHECK` da seção 3 foi escrito para conviver com isso.

**Testes:** T20 a T22. Contraprovas C04 e C05.

---

## 7. Regras de negócio

Regras específicas do funcionamento do sistema, garantidas pelo banco e não pela
aplicação. Todas identificadas a partir **deste** projeto, e não de exemplos genéricos.

| # | Regra | Implementação | Teste |
|---|---|---|---|
| RN-01 | Um CPF não pertence a dois passageiros | `uq_passageiro_cpf` | T23 |
| RN-02 | Uma matrícula de aeronave é única na frota | `uq_aeronave_prefixo` | T24 |
| RN-03 | Um número de voo corresponde a uma única rota | `uq_rota_numero_voo` | T26 |
| RN-04 | Um voo não parte de onde chega | `ck_rota_origem_destino` | T15 |
| RN-05 | Origem e destino seguem o padrão IATA | `ck_rota_*_iata` | T16–T18 |
| RN-06 | O mesmo voo não parte duas vezes no mesmo instante | `uq_voo_rota_partida` | T27 |
| RN-07 | Um voo não chega antes de partir | `ck_voo_chegada_apos_partida` | T19 |
| RN-08 | O status do voo é um dos quatro previstos | `ck_voo_status` | T12, T34 |
| RN-09 | O mesmo passageiro não ocupa dois assentos no mesmo voo | `uq_passagem_passageiro_voo` | T28 |
| RN-10 | O mesmo assento não é vendido duas vezes no mesmo voo | `uq_passagem_voo_assento` | T29 |
| RN-11 | Cada bilhete tem um localizador exclusivo | `uq_passagem_localizador` | T30 |
| RN-12 | A classe da passagem é uma das três previstas | `ck_passagem_classe` | T13 |
| RN-13 | Aeronave em operação tem capacidade positiva | `ck_aeronave_capacidade` | T14 |
| RN-14 | Não se apaga registro do qual outro depende | `ON DELETE RESTRICT` (5 FKs) | T07–T11 |
| RN-15 | **Passagens vendidas não excedem a capacidade da aeronave** | trigger — ver abaixo | T31, T33 |

### RN-15: a regra que as restrições declarativas não alcançam

**A regra.** O número de passagens vendidas para um voo não pode exceder
`capacidade_assentos` da aeronave escalada.

**Por que não é um `CHECK`.** A verificação precisa **contar linhas de `passagem`** e
**ler `capacidade_assentos` de `aeronave`**, atravessando `voo`. O `CHECK` do MySQL 8 não
aceita subconsulta nem função de agregação — a regra é inexpressável nele. Não é limitação
de sintaxe deste projeto, é limitação do recurso.

**Por que não é `UNIQUE`.** `UNIQUE` compara valores entre linhas; não conta linhas nem
compara a contagem com um limite armazenado em outra tabela.

**Por que trigger e não validação na aplicação.** A trigger é o **único recurso do próprio
SGBD** que alcança a regra. Fora dela, a garantia dependeria de todo cliente lembrar de
verificar antes de inserir — que é exatamente o argumento contra o qual a Aula 08 se
posicionou ao colocar as regras de negócio no banco. Uma regra que só a aplicação conhece
é uma regra que o próximo script de importação vai violar.

**Implementação.** Duas triggers `BEFORE`, uma em `INSERT` e outra em `UPDATE`:

```sql
CREATE TRIGGER trg_passagem_capacidade_insert
BEFORE INSERT ON passagem
FOR EACH ROW
BEGIN
    DECLARE v_capacidade INT;
    DECLARE v_vendidas   INT;
    SELECT a.capacidade_assentos INTO v_capacidade
      FROM voo v JOIN aeronave a ON a.id_aeronave = v.id_aeronave
     WHERE v.id_voo = NEW.id_voo;
    SELECT COUNT(*) INTO v_vendidas FROM passagem WHERE id_voo = NEW.id_voo;
    IF v_vendidas >= v_capacidade THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Capacidade da aeronave excedida para este voo';
    END IF;
END
```

A segunda trigger não é redundância: **sem ela a regra seria contornável por `UPDATE`**,
movendo uma passagem para um voo já lotado. Ela só executa a verificação quando `id_voo`
muda, para não pagar o custo em atualizações de check-in ou classe. O teste T33 exercita
exatamente esse caminho, e é o que impede que a segunda trigger seja código não
verificado.

`SIGNAL SQLSTATE '45000'` é o mecanismo padrão para erro definido pelo usuário; o MySQL o
reporta como **erro 1644**, confirmado no teste T31.

**Limitação registrada.** Sob concorrência alta, duas transações podem ler a mesma
contagem antes de qualquer uma gravar, e as duas passarem — a última poltrona seria
vendida duas vezes. A garantia completa exigiria bloqueio explícito na linha do voo
(`SELECT ... FOR UPDATE`) dentro de uma transação. Para o escopo desta disciplina a
trigger é suficiente, mas a ressalva fica registrada em vez de omitida.

---

## 8. Regras identificadas e deliberadamente não implementadas

> **Observação 7 do enunciado:** "Não deverão ser criadas restrições apenas para aumentar
> a quantidade de comandos SQL. (…) Também deverá ser evitada a utilização de regras que
> impeçam operações válidas do sistema."

Esta seção existe para responder a essa observação. Cada item abaixo é uma restrição que
**seria plausível**, foi analisada, e foi rejeitada com motivo. Deixar de implementar é
uma decisão de projeto tão documentável quanto implementar.

### 8.1 `UNIQUE` em `passageiro.email` — rejeitada

**Por que pareceria certo.** E-mail é identificador natural em quase todo sistema de
cadastro, e a duplicata costuma indicar cadastro repetido da mesma pessoa.

**Por que está errado aqui.** **Uma família compartilha um e-mail.** Pai, mãe e dois filhos
comprando passagens na mesma reserva, com o mesmo endereço de contato, são quatro
passageiros legítimos e distintos. Uma restrição de unicidade recusaria o cadastro do
segundo em diante.

Este é precisamente o caso que a observação 7 descreve: **regra que impede operação
válida**. O sistema perderia uma venda real para satisfazer uma restrição que o negócio não
pede. A identidade do passageiro é o CPF, ou o `id_passageiro` quando não há CPF — o
e-mail é canal de contato, e canal de contato se compartilha.

**Contraprovas C06 e C07** demonstram que dois passageiros distintos com o mesmo e-mail
entram sem erro.

### 8.2 `NOT NULL` em `voo.portao` — rejeitada

**Por que pareceria certo.** Todo voo embarca por algum portão; um campo nulo parece dado
faltando.

**Por que está errado aqui.** **O portão é atribuído perto do embarque.** Um voo entra na
programação semanas antes, e a alocação de portão depende da ocupação do terminal no dia,
que só se conhece com poucas horas de antecedência. Muitas vezes ele muda depois de
publicado.

Exigir preenchimento impediria cadastrar voo programado — que é a operação mais comum do
sistema. O nulo aqui **carrega informação**: significa "portão ainda não atribuído", que é
um estado legítimo e diferente de "dado perdido".

**Contraprova C04** demonstra o cadastro de voo com `portao` nulo.

### 8.3 Validação de dígito verificador do CPF — rejeitada

**Por que pareceria certo.** O CPF tem dígitos verificadores calculáveis, e a validação
pegaria erro de digitação na hora.

**Por que está errado aqui.** Dois motivos, e o primeiro é decisivo:

**O campo aceita nulo por decisão de modelagem da Aula 05** — passageiro estrangeiro não
tem CPF. Qualquer validação precisaria ser condicional ao campo não ser nulo, o que já
complica a expressão sem ganho proporcional.

**O cálculo do dígito verificador é aritmético**, com pesos posicionais e módulo 11.
Expressá-lo em `CHECK` do MySQL exigiria uma expressão longa e ilegível sobre `SUBSTRING`,
ou uma função armazenada — e uma função em `CHECK` precisa ser determinística e
introduziria dependência de código externo à definição da tabela. O custo de manutenção não
se justifica para uma validação que a camada de entrada faz melhor, com mensagem de erro
compreensível para o operador.

O banco garante o que é estrutural: o CPF tem 11 caracteres (`CHAR(11)`) e não se repete
(`uq_passageiro_cpf`). A plausibilidade aritmética fica na aplicação.

### 8.4 Mesmo passageiro em dois voos simultâneos — não implementada

**A regra.** Um passageiro não pode ter passagens para dois voos que partem de aeroportos
diferentes em horários sobrepostos. Ninguém embarca em Brasília e em Guarulhos ao mesmo
tempo.

**Por que nenhuma restrição declarativa alcança.** A verificação é **temporal e
relacional**: exige comparar o intervalo `[partida, chegada]` do voo sendo inserido com o
intervalo de todos os outros voos do mesmo passageiro, e ainda cruzar a origem de um com o
destino do outro para distinguir sobreposição real de conexão legítima.

- `CHECK` não alcança: precisa de subconsulta e agregação, pelos mesmos motivos da RN-15.
- `UNIQUE` não alcança: compara igualdade de valores, não sobreposição de intervalos.
- Chave estrangeira não tem nada a ver com o caso.

**Por que não foi implementada por trigger, diferente da RN-15.** A RN-15 tem um critério
objetivo e fechado: contar passagens e comparar com um número. Esta regra **não tem
critério fechado**. Ela precisaria distinguir:

- conexão legítima — chegar em Brasília às 10:10 e partir de Brasília às 11:20 é a
  operação normal de quem faz baldeação, e o modelo hoje não representa conexão;
- tempo mínimo de conexão, que varia por aeroporto e por terminal;
- remarcação, em que o passageiro tem duas passagens porque uma foi reemitida;
- passagem cancelada, estado que a tabela `passagem` hoje nem registra.

Implementar sem esses conceitos modelados produziria uma trigger que **bloqueia conexão
legítima** — de novo o problema que a observação 7 manda evitar, e desta vez sobre a
operação mais corriqueira de um aeroporto.

**Fica documentada como regra conhecida e não implementada**, no mesmo formato adotado na
RN-009 do dicionário de dados da Aula 06. Implementá-la exigiria antes modelar conexão,
tempo mínimo de baldeação e status da passagem — evolução do modelo, não restrição a
acrescentar ao esquema atual.

### 8.5 Resumo das decisões

| Regra candidata | Decisão | Motivo |
|---|---|---|
| `UNIQUE` em `email` | **Não** | Família compartilha e-mail; bloquearia cadastro legítimo |
| `NOT NULL` em `portao` | **Não** | Portão é atribuído perto do embarque; bloquearia voo programado |
| Dígito verificador do CPF | **Não** | Campo aceita nulo; validação aritmética pertence à aplicação |
| Voos simultâneos do mesmo passageiro | **Não** | Sem critério fechado; bloquearia conexão legítima |
| Capacidade da aeronave (RN-15) | **Sim, por trigger** | Critério objetivo; único recurso do SGBD que alcança |

---

## 9. Testes realizados e resultados

Executados em **MySQL 8.0.46** real, em contêiner Docker. Cada comando foi rodado
isoladamente, e o código de erro abaixo é o **retornado pelo servidor**, capturado da saída
— não transcrito de documentação.

O `sql_integridade.sql` cria o banco com código de saída **0** e `stderr` vazio: 6 modelos,
6 aeronaves, 8 passageiros, 7 rotas, 8 voos e 12 passagens. **A carga limpa é a primeira
contraprova**: as restrições não bloqueiam a operação legítima do sistema.

### 9.1 Recusas em inserção e exclusão

| # | Situação testada | Regra | Esperado | Obtido | Constraint acionada |
|---|---|---|---|---|---|
| T01 | `id_passageiro` duplicado | Entidade | 1062 | **1062** | `passageiro.PRIMARY` |
| T03 | Passagem para voo inexistente | Referencial | 1452 | **1452** | `fk_passagem_voo` |
| T04 | Voo com aeronave inexistente | Referencial | 1452 | **1452** | `fk_voo_aeronave` |
| T05 | Aeronave com modelo inexistente | Referencial | 1452 | **1452** | `fk_aeronave_modelo` |
| T06 | Voo com rota inexistente | Referencial | 1452 | **1452** | `fk_voo_rota` |
| T32 | Passagem para passageiro inexistente | Referencial | 1452 | **1452** | `fk_passagem_passageiro` |
| T07 | Apagar aeronave com voos | Referencial | 1451 | **1451** | `fk_voo_aeronave` |
| T08 | Apagar modelo com aeronaves | Referencial | 1451 | **1451** | `fk_aeronave_modelo` |
| T09 | Apagar rota com voos | Referencial | 1451 | **1451** | `fk_voo_rota` |
| T10 | Apagar voo com passagens | Referencial | 1451 | **1451** | `fk_passagem_voo` |
| T11 | Apagar passageiro com passagens | Referencial | 1451 | **1451** | `fk_passagem_passageiro` |
| T12 | Status `'embarcando'` | Domínio | 3819 | **3819** | `ck_voo_status` |
| T13 | Classe `'Turista'` | Domínio | 3819 | **3819** | `ck_passagem_classe` |
| T14 | Capacidade zero | Domínio | 3819 | **3819** | `ck_aeronave_capacidade` |
| T15 | Rota `BSB → BSB` | Negócio | 3819 | **3819** | `ck_rota_origem_destino` |
| T16 | Origem `'bsb'` minúscula | Domínio | 3819 | **3819** | `ck_rota_origem_iata` |
| T17 | Origem `'BS1'` com dígito | Domínio | 3819 | **3819** | `ck_rota_origem_iata` |
| T18 | Destino `'GR'` com 2 letras | Domínio | 3819 | **3819** | `ck_rota_destino_iata` |
| T19 | Chegada antes da partida | Negócio | 3819 | **3819** | `ck_voo_chegada_apos_partida` |
| T20 | `fabricante` nulo | Obrigatoriedade | 1048 | **1048** | coluna `NOT NULL` |
| T21 | `nome` nulo | Obrigatoriedade | 1048 | **1048** | coluna `NOT NULL` |
| T22 | `origem` nula | Obrigatoriedade | 1048 | **1048** | coluna `NOT NULL` |
| T23 | CPF duplicado | Unicidade | 1062 | **1062** | `uq_passageiro_cpf` |
| T24 | Prefixo duplicado | Unicidade | 1062 | **1062** | `uq_aeronave_prefixo` |
| T25 | Modelo duplicado | Unicidade | 1062 | **1062** | `uq_modelo_aeronave_modelo` |
| T26 | `numero_voo` duplicado em rota | Unicidade | 1062 | **1062** | `uq_rota_numero_voo` |
| T27 | Mesma rota e mesma partida | Unicidade | 1062 | **1062** | `uq_voo_rota_partida` |
| T28 | Passageiro em 2 assentos no voo | Negócio | 1062 | **1062** | `uq_passagem_passageiro_voo` |
| T29 | 2 passageiros no mesmo assento | Negócio | 1062 | **1062** | `uq_passagem_voo_assento` |
| T30 | Localizador duplicado | Unicidade | 1062 | **1062** | `uq_passagem_localizador` |
| T31 | Passagem além da capacidade | Negócio | 1644 | **1644** | `trg_passagem_capacidade_insert` |

**31 de 31 recusados, com o código esperado em todos.**

Mensagens representativas, copiadas da saída do servidor:

```
T19  ERROR 3819 (HY000): Check constraint 'ck_voo_chegada_apos_partida' is violated.
T16  ERROR 3819 (HY000): Check constraint 'ck_rota_origem_iata' is violated.
T26  ERROR 1062 (23000): Duplicate entry '305' for key 'rota.uq_rota_numero_voo'
T31  ERROR 1644 (45000): Capacidade da aeronave excedida para este voo
T08  ERROR 1451 (23000): Cannot delete or update a parent row: a foreign key
                          constraint fails (`aeroporto`.`aeronave`,
                          CONSTRAINT `fk_aeronave_modelo` ...)
```

**Sobre o teste T31.** Para exercitar a capacidade sem inserir centenas de passagens, o
teste cadastra uma aeronave `PR-MIN` com `capacidade_assentos = 1` e um voo para ela. A
primeira passagem entra normalmente; a segunda é recusada pela trigger. Isso testa a regra
no seu limite exato, que é onde ela precisa funcionar.

#### 9.1.1 Recusas em atualização

Os testes da seção anterior são todos `INSERT` ou `DELETE`. Testar só essas duas operações
deixa de fora uma categoria inteira, e não por detalhe: **restrição que vale na inserção e
não vale na atualização é um buraco clássico de modelagem.** O dado entra correto, passa
por todas as verificações, e depois é levado a um estado inválido por um `UPDATE` que
ninguém checou. O resultado é pior do que não ter a regra, porque o banco parece garantida
uma consistência que ele não mantém.

Três motivos concretos para a categoria existir neste trabalho:

- **A `trg_passagem_capacidade_update` só existe por causa disso.** Ela foi escrita
  precisamente porque a versão de `INSERT` sozinha deixaria a regra contornável: bastava
  inserir a passagem em um voo vazio e depois movê-la para o lotado. Sem um teste de
  `UPDATE`, essa segunda trigger seria código nunca verificado — exatamente o tipo de
  salvaguarda que se descobre quebrada quando já é tarde.
- **A nulidade da chave primária só é observável por `UPDATE`**, pelo comportamento do
  `AUTO_INCREMENT` descrito na seção 1.
- **Os `CHECK` precisam valer nas duas operações.** O MySQL os aplica em `INSERT` e
  `UPDATE`, mas isso é afirmação sobre o SGBD que vale a pena confirmar no banco real, e
  não presumir.

| # | Situação testada | Regra | Esperado | Obtido | Constraint acionada |
|---|---|---|---|---|---|
| T02 | `UPDATE` colocando `NULL` na chave primária | Entidade | 1048 | **1048** | `passageiro.id_passageiro` |
| T33 | `UPDATE` movendo passagem para voo já lotado | Negócio | 1644 | **1644** | `trg_passagem_capacidade_update` |
| T34 | `UPDATE` mudando `status` para valor fora do domínio | Domínio | 3819 | **3819** | `ck_voo_status` |

**3 de 3 recusados, com o código esperado em todos.**

```
T02  ERROR 1048 (23000): Column 'id_passageiro' cannot be null
T33  ERROR 1644 (45000): Capacidade da aeronave excedida para este voo
T34  ERROR 3819 (HY000): Check constraint 'ck_voo_status' is violated.
```

T33 reaproveita o cenário montado para T31 — a aeronave `PR-MIN` de um assento, com a
passagem `CAP001` já vendida — e tenta mover para lá uma passagem existente de outro voo.
A trigger de `UPDATE` recusa, provando que o caminho alternativo está fechado.

Somando as duas seções: **34 comandos recusados, 34 com o código esperado.**

### 9.2 Comandos que devem ser aceitos — contraprovas

Metade do trabalho de uma restrição é **não** bloquear o que é válido. Estas dez operações
legítimas foram executadas contra o banco com todas as regras ativas:

| # | Situação testada | O que demonstra | Resultado |
|---|---|---|---|
| C01 | Segundo passageiro sem CPF | `UNIQUE` aceita vários nulos | **aceito** |
| C02 | Mesmo passageiro em outro voo | O N:N funciona; `uq_passagem_passageiro_voo` restringe por voo, não por passageiro | **aceito** |
| C03 | Mesmo assento em voo diferente | `uq_passagem_voo_assento` é composta, não bloqueia o assento globalmente | **aceito** |
| C04 | Voo com `portao` nulo | Voo programado sem portão atribuído entra (seção 8.2) | **aceito** |
| C05 | Voo sem chegada prevista | O `CHECK` da seção 3 não bloqueia nulo | **aceito** |
| C06 | Passageira com e-mail `familia@` | Sem `UNIQUE` em e-mail (seção 8.1) | **aceito** |
| C07 | Segundo passageiro com o **mesmo** e-mail | Família compartilhando contato — a operação que um `UNIQUE` teria bloqueado | **aceito** |
| C08 | Nova rota `CWB → POA` | Código IATA válido passa no `REGEXP` | **aceito** |
| C09 | Mudar status para `'Cancelado'` | A forma correta de cancelar voo, preservando as passagens (seção 2) | **aceito** |
| C10 | Passagem em classe `'Primeira'` | Valor legítimo do domínio | **aceito** |

**10 de 10 aceitos.** Nenhuma restrição bloqueia operação válida.

O par C06/C07 é o mais relevante: demonstra na prática a decisão da seção 8.1. Se
`passageiro.email` fosse `UNIQUE`, C07 falharia e o sistema recusaria um cadastro
legítimo.

### 9.3 Conferência no dicionário do SGBD

As restrições foram verificadas em `information_schema`, para confirmar que existem no
banco e não apenas no arquivo:

**Sete `CHECK`**, incluindo os três novos:

```
ck_aeronave_capacidade        (capacidade_assentos > 0)
ck_passagem_classe            (classe in ('Economica','Executiva','Primeira'))
ck_rota_destino_iata          regexp_like(destino,'^[A-Z]{3}$','c')
ck_rota_origem_destino        (origem <> destino)
ck_rota_origem_iata           regexp_like(origem,'^[A-Z]{3}$','c')
ck_voo_chegada_apos_partida   (data_hora_chegada_prevista > data_hora_partida)
ck_voo_status                 (status in ('Embarque','Confirmado','Aguardando','Cancelado'))
```

**Duas triggers:**

```
trg_passagem_capacidade_insert   BEFORE   INSERT   passagem
trg_passagem_capacidade_update   BEFORE   UPDATE   passagem
```

**`uq_rota_numero_voo` confirmada** como `UNIQUE` na tabela `rota`, conforme a seção 5.

### 9.4 Como reproduzir

```bash
mysql -u root -p < sql_integridade.sql
```

O arquivo recria o banco `aeroporto` do zero, com as restrições, as triggers e os dados.
Ao final ele lista as tabelas, as restrições registradas em `information_schema` e as
contagens por tabela.

---

## 10. Resumo

| Categoria | Restrições | Testes |
|---|---|---|
| Integridade de entidade | 6 `PRIMARY KEY` | T01, T02 |
| Integridade referencial | 5 `FOREIGN KEY`, todas `ON DELETE RESTRICT` / `ON UPDATE CASCADE` | T03–T11, T32 |
| Integridade de domínio | Tipos, 7 `CHECK`, 3 `DEFAULT` | T12–T19, T34 |
| Integridade de chave | 8 chaves candidatas além das 6 primárias | T23–T30 |
| Unicidade | 8 `UNIQUE`, 3 delas compostas | T23–T30 |
| Obrigatoriedade | 19 colunas `NOT NULL` além das 6 primárias; 6 colunas nulas por decisão justificada | T20–T22, C04–C05 |
| Regras de negócio | 15 regras, 14 declarativas e 1 por trigger | T07–T34 |
| **Não implementadas** | 4 regras analisadas e rejeitadas com motivo | C04, C06–C07 |

**44 testes executados: 34 recusas e 10 contraprovas, todos com o resultado esperado.**
Das 34 recusas, 31 são em inserção ou exclusão e 3 em atualização.

O banco recusa dado inconsistente em todas as sete categorias de integridade, nas três
operações que alteram dados — inserção, exclusão e atualização — e não bloqueia nenhuma
operação legítima. As regras que o SGBD não alcança de forma declarativa estão
documentadas com o motivo, e a única implementada por trigger tem a justificativa de ser o
único recurso do próprio banco capaz de expressá-la.
