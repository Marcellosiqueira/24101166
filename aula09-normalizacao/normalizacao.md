# Aula 09 — Normalização do banco de dados

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Análise de normalização do banco `aeroporto`, o mesmo desenvolvido desde o início do
semestre. O ponto de partida é o SQL da Aula 08, preservado em `sql_aula_8.sql` sem
nenhuma alteração. O resultado está em `sql_normalizado.sql`.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `sql_aula_8.sql` | Banco da Aula 08, preservado para comparação |
| `sql_normalizado.sql` | Banco após a aplicação das formas normais |
| `normalizacao.md` | Esta análise |

O original continua em `aula08-criacao-banco/aeroporto.sql`. A cópia aqui é byte a byte
idêntica e existe para que esta pasta seja autocontida, como o enunciado pede.

---

## 1. Comparação com o SQL da Aula 08

### Estrutura de partida

Quatro tabelas: `aeronave`, `passageiro`, `voo` e a associativa `passagem`.

```
aeronave  (id_aeronave PK, prefixo UNIQUE, modelo, fabricante, capacidade_assentos)
passageiro(id_passageiro PK, cpf UNIQUE NULL, nome, data_nascimento, email, telefone)
voo       (id_voo PK, numero_voo, id_aeronave FK, origem, destino,
           data_hora_partida, data_hora_chegada_prevista, portao, status)
           UNIQUE (numero_voo, data_hora_partida)
passagem  (id_passagem PK, id_passageiro FK, id_voo FK, assento,
           localizador UNIQUE, classe, checkin_realizado)
           UNIQUE (id_passageiro, id_voo), UNIQUE (id_voo, assento)
```

Todas as quatro usam chave substituta (`AUTO_INCREMENT`) como chave primária, com as
chaves naturais declaradas como `UNIQUE`. Essa decisão, tomada na Aula 05, é o que torna
a análise que vem a seguir menos óbvia do que parece, e está no centro da seção de 2FN.

### Chaves candidatas de cada tabela

Levantar as chaves candidatas antes de olhar as formas normais não é formalidade. As
definições de 2FN e 3FN falam em "atributo primo", isto é, atributo que participa de
*alguma* chave candidata, e não apenas da chave primária escolhida.

| Tabela | Chaves candidatas |
|---|---|
| `aeronave` | `id_aeronave`; `prefixo` |
| `passageiro` | `id_passageiro`; `cpf` (parcial: aceita `NULL`) |
| `voo` | `id_voo`; `(numero_voo, data_hora_partida)` |
| `passagem` | `id_passagem`; `localizador`; `(id_passageiro, id_voo)`; `(id_voo, assento)` |

### Dependências funcionais

```
aeronave    id_aeronave → prefixo, modelo, fabricante, capacidade_assentos
            prefixo     → id_aeronave, modelo, fabricante, capacidade_assentos
            modelo      → fabricante                          ← transitiva

passageiro  id_passageiro → cpf, nome, data_nascimento, email, telefone
            cpf           → id_passageiro, nome, data_nascimento, email, telefone

voo         id_voo → numero_voo, id_aeronave, origem, destino, data_hora_partida,
                     data_hora_chegada_prevista, portao, status
            (numero_voo, data_hora_partida) → id_aeronave, origem, destino,
                     data_hora_chegada_prevista, portao, status
            numero_voo → origem, destino                      ← parcial

passagem    id_passagem           → todos os demais
            localizador           → todos os demais
            (id_passageiro, id_voo) → todos os demais
            (id_voo, assento)     → todos os demais
```

### Redundâncias observadas nos dados

Duas repetições aparecem nas próprias linhas de exemplo da Aula 08:

- `fabricante` se repete: seis aeronaves, três fabricantes. "Airbus" aparece duas vezes,
  "Boeing" duas, "Embraer" duas.
- `origem` e `destino` se repetem: o voo 305 aparece em dois dias, `GRU → BSB` nas duas
  linhas.

Nenhuma das duas causa anomalia com seis e oito registros. Ambas causariam em escala, e
é essa a razão técnica de mexer.

### Alterações realizadas

| Tabela | Situação |
|---|---|
| `modelo_aeronave` | **Criada** — extraída de `aeronave` (3FN) |
| `aeronave` | Alterada — `modelo` e `fabricante` saem, entra `id_modelo` |
| `rota` | **Criada** — extraída de `voo` (2FN) |
| `voo` | Alterada — `numero_voo`, `origem` e `destino` saem, entra `id_rota` |
| `passageiro` | Inalterada |
| `passagem` | Inalterada |

Quatro tabelas passam a seis. Duas das seis não foram tocadas, e três das cinco formas
normais não exigiram alteração nenhuma.

---

## 2. Primeira Forma Normal (1FN)

> Todos os atributos devem ser atômicos, sem grupos repetitivos e sem coleções em um
> único campo.

**Situação: já atendida. Nenhuma alteração.**

Nenhuma tabela tem campo multivalorado, lista separada por vírgula ou grupo repetitivo
do tipo `telefone1`, `telefone2`, `telefone3`. Cada célula guarda um valor. Isso já vinha
resolvido desde a Aula 05, quando o relacionamento N:N entre passageiro e voo foi
resolvido pela tabela associativa `passagem` em vez de uma coluna com vários voos.

Duas colunas, porém, merecem análise em vez de aprovação automática, porque são
**atributos compostos** — atômicos para o SGBD, mas com estrutura interna reconhecível.

### `assento` = fileira + poltrona

O valor `12A` é a fileira 12, poltrona A. `01A`, `14C`, `22F` seguem o mesmo padrão.
Decompor daria `assento_fileira INT` e `assento_poltrona CHAR(1)`.

**Decisão: não decompor.**

O critério para decompor um atributo composto não é ele *ter* partes, é o sistema
precisar **acessar as partes separadamente**. Nenhuma consulta do painel de voos filtra,
agrupa ou ordena por fileira. Ninguém pergunta "quantos passageiros estão na fileira 12".
O assento é usado como identificador da poltrona dentro do voo — inclusive na constraint
`uq_passagem_voo_assento` — e nesse uso ele é indivisível. Decompor criaria duas colunas
para reconstituir com `CONCAT` em toda consulta, sem nenhum ganho.

Se o sistema passasse a alocar assentos por critério de posição — janela, corredor,
saída de emergência —, a conta mudaria e a decomposição passaria a se justificar.

### `prefixo` = marca de nacionalidade + matrícula

`PR-XAA` é a marca de nacionalidade brasileira (`PR`, `PT`, `PS`) mais a matrícula da
aeronave (`XAA`). A estrutura é padronizada pela OACI e o hífen é parte da notação
oficial.

**Decisão: não decompor.**

Mesmo critério, com um argumento adicional: o prefixo é a **matrícula internacional** da
aeronave, e nesse papel funciona como um identificador único e indivisível, análogo a um
CPF. É por ele que a aeronave é referida em plano de voo e em comunicação com o controle
de tráfego. Separar a marca de país só faria sentido para uma operadora com frota em
vários países que precisasse filtrar por nacionalidade de registro, o que não é o caso
deste sistema.

Vale notar o contraste com o CPF, que ficou `CHAR(11)` sem pontuação justamente porque
os separadores não carregam informação. No prefixo o hífen é parte do identificador, não
formatação.

### Conclusão da 1FN

O banco da Aula 08 já está em 1FN. Os dois atributos compostos identificados foram
avaliados e mantidos, por decisão de projeto e não por omissão.

---

## 3. Segunda Forma Normal (2FN)

> Estar em 1FN e não ter dependência parcial: nenhum atributo não-primo pode depender de
> apenas parte de uma chave candidata composta.

**Situação: `voo` viola. Extraída a tabela `rota`.**

Esta é a parte mais delicada da análise e a que exige mais cuidado para não errar dos
dois lados.

### Por que a 2FN parece já resolvida — e por que isso engana

A chave primária de `voo` é `id_voo`, um `AUTO_INCREMENT` de atributo único. **Uma chave
de atributo único não pode ter dependência parcial**, porque "parte" de um atributo só
não existe. Olhando apenas para a chave primária, a 2FN passa trivialmente em `voo` — e
em todas as outras tabelas, já que todas usam chave substituta.

O problema é que essa conclusão está incompleta. **A normalização se avalia contra todas
as chaves candidatas da relação, não apenas contra a chave primária escolhida.** A chave
primária é uma escolha de implementação; as dependências funcionais são propriedade dos
dados. Se bastasse acrescentar um `AUTO_INCREMENT` a qualquer tabela para satisfazer 2FN
e 3FN, as formas normais não teriam conteúdo nenhum — qualquer esquema, por pior que
fosse, ficaria "normalizado" com uma coluna a mais.

`voo` tem uma segunda chave candidata, declarada no próprio SQL da Aula 08:

```sql
CONSTRAINT uq_voo_numero_partida UNIQUE (numero_voo, data_hora_partida)
```

Ela é **composta**. É contra ela que a 2FN precisa ser verificada, e é aí que a violação
aparece.

### A premissa de negócio, declarada antes de ser usada

A dependência que gera a violação é:

```
numero_voo → origem, destino
```

Isto é: **o número do voo determina o trecho**. O voo 305 é sempre `GRU → BSB`.

Isso **não é um fato observado nos dados, é uma regra de negócio assumida.** Declaro a
premissa explicitamente porque a análise inteira desta seção depende dela:

> **Premissa.** Dentro do horizonte de operação modelado por este sistema, um número de
> voo identifica um trecho fixo: a mesma origem e o mesmo destino, em todas as suas
> ocorrências.

A evidência disponível nos dados é fraca e não sustentaria a conclusão sozinha: o voo 305
aparece duas vezes, ambas `GRU → BSB`. **Duas linhas coincidirem não provam uma
dependência funcional** — provam apenas que aquelas duas linhas não a contradizem. Uma
dependência funcional é uma afirmação sobre todos os estados possíveis da relação, e
nenhum conjunto finito de linhas a demonstra. O que os dados fazem é não refutá-la.

A premissa vem do domínio, não da amostra: companhias aéreas atribuem números de voo a
trechos comerciais, e é por isso que o passageiro compra "o 305" sabendo de onde e para
onde vai antes de escolher a data.

**Se a premissa cair, não há violação de 2FN.** Companhias remanejam numeração entre
temporadas, e um mesmo número pode passar a operar outro trecho na temporada seguinte.
Se o sistema precisar representar isso, `origem` e `destino` deixam de depender só de
`numero_voo` e passam a depender do par completo `(numero_voo, data_hora_partida)` — que
é a chave candidata inteira. A dependência deixaria de ser parcial, `voo` estaria em 2FN
como está, e a tabela `rota` seria uma decomposição desnecessária.

A alternativa correta nesse cenário seria versionar a rota por período de vigência, com
`rota` ganhando `valido_de` e `valido_ate` — o que é uma modelagem bem mais pesada e só
se justifica se o requisito existir. Registro a bifurcação porque a decisão é do domínio,
não da técnica.

### A violação

Aceita a premissa, contra a chave candidata `(numero_voo, data_hora_partida)`:

- `origem` e `destino` são atributos não-primos
- eles dependem de `numero_voo`, que é **parte** da chave candidata
- não dependem de `data_hora_partida`

Isso é dependência parcial, ou seja, violação de 2FN.

O contraste com os demais atributos confirma o diagnóstico, e os dados de exemplo o
ilustram bem. Nas duas ocorrências do voo 305:

| | origem | destino | id_aeronave | portao | data |
|---|---|---|---|---|---|
| 305 em 01/09 | GRU | BSB | 1 | 12 | 2026-09-01 |
| 305 em 02/09 | GRU | BSB | 2 | 11 | 2026-09-02 |

`origem` e `destino` não mudam, porque dependem só do número. `id_aeronave` e `portao`
mudam, porque dependem da ocorrência inteira. São dois grupos de atributos com
comportamentos diferentes convivendo na mesma tabela — que é a definição prática do
problema que a 2FN descreve.

### Anomalias que a violação produz

- **Atualização.** Se o trecho do voo 512 mudar, é preciso alterar todas as linhas com
  `numero_voo = '512'`. Uma linha esquecida deixa o mesmo número com dois trechos, um
  estado que o banco aceita sem reclamar.
- **Inserção.** Não é possível cadastrar uma rota antes de existir uma ocorrência dela.
  Uma linha nova aberta para a temporada seguinte só existe quando já tem data e aeronave.
- **Exclusão.** Apagar a última ocorrência do voo 630 apaga também a informação de que
  existe um trecho `BSB → REC` com esse número.

### A correção

```sql
CREATE TABLE rota (
    id_rota    INT AUTO_INCREMENT PRIMARY KEY,
    numero_voo VARCHAR(10) NOT NULL,
    origem     CHAR(3)     NOT NULL,
    destino    CHAR(3)     NOT NULL,

    CONSTRAINT uq_rota_numero_voo UNIQUE (numero_voo),
    CONSTRAINT ck_rota_origem_destino CHECK (origem <> destino)
);
```

`voo` perde `numero_voo`, `origem` e `destino`, e ganha `id_rota` como chave estrangeira.
Passa a guardar apenas o que varia por ocorrência: data, aeronave escalada, portão e
status.

A decomposição é **sem perda**: `voo ⋈ rota` por `id_rota` reconstrói exatamente a tabela
original, porque `id_rota` é chave em `rota`. E **preserva as dependências**: tanto
`numero_voo → origem, destino` quanto as dependências da chave completa continuam
verificáveis dentro de uma única tabela, sem precisar de junção.

---

## 4. Terceira Forma Normal (3FN)

> Estar em 2FN e não ter dependência transitiva: nenhum atributo não-primo pode depender
> de outro atributo não-primo.

**Situação: `aeronave` viola. Extraída a tabela `modelo_aeronave`.**

### A violação

```
id_aeronave → modelo → fabricante
```

`modelo` e `fabricante` são ambos não-primos, e `modelo → fabricante` vale
independentemente da aeronave: todo "737 MAX 8" é da Boeing, todo "E195-E2" é da Embraer.
O fabricante é fato sobre o modelo, não sobre a aeronave. Chegar até ele passando por
`id_aeronave` é o desvio que caracteriza a transitividade.

Diferente do caso da 2FN, aqui **não há premissa frágil**: o fabricante de um modelo de
aeronave é imutável. Um 737 não passa a ser da Airbus na temporada seguinte.

Anomalias: corrigir a grafia de um fabricante exige `UPDATE` em todas as aeronaves
daquele modelo; um modelo só pode ser cadastrado junto com uma aeronave; e a última
aeronave de um modelo leva consigo o registro do fabricante.

### A correção

```sql
CREATE TABLE modelo_aeronave (
    id_modelo  INT AUTO_INCREMENT PRIMARY KEY,
    modelo     VARCHAR(50) NOT NULL,
    fabricante VARCHAR(50) NOT NULL,

    CONSTRAINT uq_modelo_aeronave_modelo UNIQUE (modelo)
);
```

`aeronave` perde `modelo` e `fabricante` e ganha `id_modelo`.

### Por que `capacidade_assentos` NÃO foi junto

Esta é a decisão mais discutível da normalização, e ela foi tomada contra o que os dados
sugerem.

Nos dados de exemplo, cada modelo aparece uma vez só. Não há nenhuma linha que contradiga
`modelo → capacidade_assentos`, e uma leitura mecânica da amostra levaria a mover a
capacidade para `modelo_aeronave` junto com o fabricante.

**A capacidade permanece em `aeronave`.**

A justificativa é de domínio, e é a mesma razão pela qual a premissa da 2FN precisou ser
declarada: dependência funcional é afirmação sobre todos os estados possíveis, e a
amostra é pequena demais para decidir. **A mesma aeronave pode ter configurações de
cabine diferentes.** Um A320neo configurado em classe única leva mais passageiros que o
mesmo A320neo com uma cabine executiva instalada. Duas aeronaves do mesmo modelo, na
mesma frota, podem ter capacidades diferentes conforme o layout escolhido; e uma mesma
aeronave muda de capacidade se for reconfigurada.

Ou seja: a capacidade é propriedade da **aeronave física**, não do modelo. O que o modelo
determina é um teto técnico de certificação, que é outro atributo, não este.

Mover a capacidade para `modelo_aeronave` normalizaria uma dependência que não existe no
domínio, e o custo seria concreto: o banco passaria a impedir o cadastro de duas
aeronaves do mesmo modelo com capacidades diferentes, que é uma situação perfeitamente
válida. Seria uma restrição inventada pela modelagem, não pelo negócio.

Isso ilustra o ponto que o enunciado levanta ao pedir justificativa técnica: normalizar
não é decompor o máximo possível, é decompor exatamente onde existe dependência real.

### `data_hora_chegada_prevista` — candidata a 3FN, mantida

Há um segundo caso possível de transitividade em `voo`, mais sutil, que vale examinar e
descartar explicitamente.

O argumento a favor da mudança: a duração de um trecho é razoavelmente estável — `GRU →
BSB` leva cerca de 1h40 sempre. Se a duração é propriedade da **rota**, então poderíamos
ter `rota.duracao_prevista` e a chegada passaria a ser **derivada**:

```
data_hora_chegada_prevista = data_hora_partida + rota.duracao_prevista
```

Nessa leitura, `data_hora_chegada_prevista` dependeria de `id_rota` e
`data_hora_partida`, e armazená-la seria guardar um valor calculável — redundância do
tipo que a 3FN combate.

**Decisão: manter `data_hora_chegada_prevista` em `voo`.**

A dependência não se sustenta. A duração prevista de um voo **não é constante por rota**:
varia com o dia, com a direção e a intensidade do vento em altitude, com a rota efetiva
autorizada pelo controle de tráfego aéreo, com restrições de fluxo no aeroporto de
destino e com o modelo de aeronave escalado — um E190 e um A321neo não cobrem o mesmo
trecho no mesmo tempo. A previsão de chegada é calculada por voo, no planejamento
daquela operação específica, e é justamente por isso que ela é publicada por voo no
painel.

Tratá-la como derivada da rota obrigaria a inventar uma duração canônica que não existe,
e o banco perderia a capacidade de representar o dado real que o sistema precisa exibir.

O caso é análogo ao da capacidade: uma dependência plausível à primeira vista, que não
resiste ao exame do domínio. Registro os dois porque o enunciado pede justificativa tanto
para o que muda quanto para o que não muda.

### `origem` e `destino` como códigos IATA

`origem` e `destino` são `CHAR(3)`, códigos IATA de aeroporto, e não há tabela
`aeroporto` no modelo. Isso **não é violação de 3FN**, porque nenhum outro atributo do
aeroporto está armazenado: não há nome, cidade, país ou fuso. Não existe atributo
não-primo dependendo de `origem`, logo não existe transitividade.

Passaria a existir no momento em que o sistema precisasse exibir "Brasília" em vez de
`BSB`, porque aí `origem → nome_aeroporto, cidade, fuso_horario` seria uma transitividade
clara e a tabela `aeroporto` seria obrigatória. Como esse requisito não está no escopo,
criá-la agora seria acrescentar tabela sem dependência que a justifique — exatamente o
que o enunciado adverte para não fazer.

### `passagem` — dependência de chave candidata, mantida

Em `passagem` existe uma dependência defensável:

```
(id_voo, assento) → classe
```

A poltrona `01A` é executiva pela posição na cabine, não por escolha do passageiro. Dado
o voo, o assento determina a classe.

**Decisão: nenhuma alteração.**

`(id_voo, assento)` é **chave candidata** de `passagem` — está declarada como
`uq_passagem_voo_assento`. Dependência de chave candidata é exatamente o que 3FN e BCNF
permitem: a definição proíbe atributo não-primo dependendo de atributo **não-primo**, e
aqui o determinante é uma chave inteira. Não há transitividade e não há violação.

A dependência aponta para uma entidade "layout de cabine" — mapa de poltronas por
configuração de aeronave, com a classe de cada posição. Seria a modelagem correta para um
sistema que gerencia a venda de assentos. Não é o caso aqui, e criar a tabela para
demonstrar aplicação de forma normal seria precisamente a inversão que o enunciado
adverte contra. Fica registrada como evolução natural do modelo se o escopo crescer.

### Verificação de BCNF

Vale notar que as duas correções feitas resolvem também a Forma Normal de Boyce-Codd, que
é mais restritiva que a 3FN: nos dois casos o determinante da dependência problemática
(`modelo` e `numero_voo`) não era superchave da sua tabela, o que caracterizava violação
de BCNF além de 3FN. No modelo final, todo determinante de dependência funcional não
trivial é superchave da relação em que está. As seis tabelas estão em BCNF.

---

## 5. Quarta Forma Normal (4FN)

> Estar em BCNF e não ter dependência multivalorada não trivial: uma tabela não pode
> conter dois fatos multivalorados independentes entre si.

**Situação: já atendida. Nenhuma alteração.**

Uma violação de 4FN exige dois atributos multivalorados **independentes** convivendo na
mesma relação, produzindo o produto cartesiano entre eles. O exemplo clássico: uma tabela
`professor(nome, disciplina, telefone)` em que disciplinas e telefones não têm relação
nenhuma entre si — três disciplinas e dois telefones geram seis linhas para representar
cinco fatos.

Percorrendo as seis tabelas do modelo final:

- **`modelo_aeronave`**, **`rota`**: cada linha é um único fato sobre uma única entidade.
  Não há atributo multivalorado.
- **`aeronave`**: prefixo, modelo e capacidade são todos monovalorados por aeronave.
- **`passageiro`**: `email` e `telefone` são os dois únicos candidatos a multivalorados —
  uma pessoa pode ter vários de cada. **Mas o modelo os define como monovalorados**, um
  de cada por passageiro, e é assim que o sistema os usa: um contato para notificação de
  voo. Sem multivaloração declarada, não há dependência multivalorada e não há violação.
- **`voo`**: todos os atributos são monovalorados por ocorrência de voo.
- **`passagem`**: cada linha é um fato único — este passageiro, neste voo, neste assento.
  As três chaves candidatas garantem que não há repetição.

**O ponto que torna a 4FN não trivial aqui já foi resolvido antes.** O relacionamento N:N
entre passageiro e voo é multivalorado nos dois sentidos: um passageiro tem vários voos,
um voo tem vários passageiros. Se essas duas listas estivessem na mesma tabela, haveria
violação de 4FN. Elas não estão: desde a Aula 05 o N:N foi resolvido pela associativa
`passagem`, que é justamente a decomposição que a 4FN prescreve. A forma normal já estava
satisfeita antes de ser verificada — o que é o resultado esperado quando a modelagem
conceitual foi feita com cuidado.

### O cenário que criaria a violação

Se o sistema passasse a registrar **vários telefones** e **vários emails** por passageiro
na mesma tabela, `passageiro` teria duas dependências multivaloradas independentes:

```
id_passageiro ↠ telefone
id_passageiro ↠ email
```

Um passageiro com três telefones e dois emails ocuparia seis linhas para representar
cinco fatos, e a inclusão de um telefone exigiria duas linhas novas. A correção seria
decompor em `passageiro_telefone` e `passageiro_email`, separadas.

Como o requisito não existe, **nenhuma alteração é feita**. Decompor agora criaria duas
tabelas para armazenar um valor cada, com uma junção obrigatória em toda consulta, sem
nenhum ganho.

---

## 6. Quinta Forma Normal (5FN)

> Estar em 4FN e não ter dependência de junção que não decorra das chaves candidatas: a
> relação não pode ser decomposta em três ou mais projeções que se recomponham sem perda.

**Situação: já atendida. Nenhuma alteração.**

A 5FN trata do caso raro em que uma relação ternária não pode ser reduzida a relações
binárias, mas **também não é** o simples produto delas — existe uma dependência de junção
genuína, tipicamente associada a uma regra cíclica do tipo "se A se relaciona com B, e B
com C, e A com C, então a tripla (A, B, C) existe".

O modelo final não tem nenhuma relação ternária. `passagem` é a única tabela associativa
e é **binária**: liga `passageiro` a `voo`. Seus demais atributos — `assento`,
`localizador`, `classe`, `checkin_realizado` — são fatos sobre a passagem em si, não
participantes de um relacionamento de três pontas.

Testando a decomposição explicitamente: `passagem` poderia ser projetada em
`(id_passageiro, id_voo)`, `(id_voo, assento)` e `(id_passageiro, assento)`? A junção
dessas três projeções **não** reconstrói a tabela original — ela produz linhas espúrias,
combinando um passageiro com um assento de um voo em que ele não embarcou, desde que ele
tenha usado aquele número de assento em algum outro voo. Nos dados de exemplo isso é
concreto: a passageira 1 está no assento `12A` do voo 1 e no `22F` do voo 3; o passageiro
6 está no `22E` do voo 3. A junção das projeções geraria combinações que nunca existiram.

Como a decomposição não é sem perda, **não existe dependência de junção** e a tabela já
está em 5FN. Não há o que decompor.

O mesmo vale para as demais cinco tabelas: todas são relações simples sobre uma única
entidade, com dependências decorrentes apenas das suas chaves candidatas — que é a
condição suficiente para 5FN.

Registro que toda relação em 5FN está automaticamente em 4FN, e que a maioria dos
esquemas bem modelados em BCNF já satisfaz as duas sem esforço adicional. É o caso aqui.

---

## 7. Modelo final normalizado

```
SQL da Aula 8  →  1FN  →  2FN  →  3FN  →  4FN  →  5FN  →  Modelo final
                   ─       rota    modelo   ─       ─
                                  _aeronave
```

Duas decomposições em cinco formas normais. Três formas normais verificadas e mantidas
sem alteração.

### Esquema

```
modelo_aeronave (id_modelo PK, modelo UNIQUE, fabricante)
aeronave        (id_aeronave PK, prefixo UNIQUE, id_modelo FK, capacidade_assentos)
passageiro      (id_passageiro PK, cpf UNIQUE NULL, nome, data_nascimento,
                 email, telefone)
rota            (id_rota PK, numero_voo UNIQUE, origem, destino)
voo             (id_voo PK, id_rota FK, id_aeronave FK, data_hora_partida,
                 data_hora_chegada_prevista, portao, status)
                 UNIQUE (id_rota, data_hora_partida)
passagem        (id_passagem PK, id_passageiro FK, id_voo FK, assento,
                 localizador UNIQUE, classe, checkin_realizado)
                 UNIQUE (id_passageiro, id_voo), UNIQUE (id_voo, assento)
```

### Constraints que precisaram migrar

A decomposição de `voo` moveu atributos entre tabelas, e duas regras da Aula 08 seriam
perdidas silenciosamente se não fossem reescritas. **Perder constraint em normalização é
regressão**: o modelo fica mais bem estruturado e ao mesmo tempo mais permissivo, que é o
pior resultado possível.

| Aula 08 | Modelo normalizado | Observação |
|---|---|---|
| `ck_voo_rota CHECK (origem <> destino)` | `ck_rota_origem_destino`, em `rota` | A regra acompanha os atributos que restringe. Em `voo` não teria mais o que verificar, já que `origem` e `destino` saíram da tabela. |
| `uq_voo_numero_partida UNIQUE (numero_voo, data_hora_partida)` | `uq_voo_rota_partida UNIQUE (id_rota, data_hora_partida)`, em `voo` | Como `numero_voo` é `UNIQUE` em `rota`, existe correspondência de um para um entre `id_rota` e `numero_voo`. A regra preservada é idêntica: o mesmo número de voo não pode partir duas vezes no mesmo instante. |

A equivalência da segunda depende de `uq_rota_numero_voo`. Sem ela, dois `id_rota`
diferentes poderiam ter o mesmo `numero_voo` e a restrição original seria enfraquecida.
As duas constraints trabalham juntas.

As demais constraints da Aula 08 — as três chaves estrangeiras com `ON DELETE RESTRICT`,
`uq_aeronave_prefixo`, `uq_passageiro_cpf`, `ck_aeronave_capacidade`, `ck_voo_status`,
`ck_passagem_classe`, `uq_passagem_localizador`, `uq_passagem_passageiro_voo` e
`uq_passagem_voo_assento` — permanecem nas suas tabelas, inalteradas. A quarta chave
estrangeira, `fk_aeronave_modelo`, e a quinta, `fk_voo_rota`, são novas e nascem das
decomposições.

### O que a normalização custou

Redundância a menos, junção a mais. As consultas do painel deixaram de ler uma tabela e
passaram a exigir `JOIN`:

- **Painel de voos**: era `voo ⋈ aeronave`. Passou a `voo ⋈ rota ⋈ aeronave ⋈
  modelo_aeronave` — de uma junção para três.
- **Lista de embarque**: o filtro por `numero_voo` migrou de `voo` para `rota`, somando
  mais uma junção.
- **Consultas sobre `passageiro` e `passagem`**: inalteradas, porque as tabelas não foram
  tocadas.

É a troca clássica. Em um sistema com carga de leitura dominante, a decisão poderia ser
outra — bancos analíticos desnormalizam de propósito, justamente para eliminar junções.
Para um sistema transacional de aeroporto, em que status e portão mudam o tempo todo e a
consistência da escrita importa mais do que economizar uma junção na leitura, a
normalização é a escolha correta.

### O que a normalização deu de volta

Além de eliminar as anomalias listadas em cada seção, a tabela `rota` habilita uma
consulta que o esquema da Aula 08 não respondia com segurança: **quantas ocorrências cada
rota teve**. Antes seria preciso agrupar por `(numero_voo, origem, destino)` e confiar que
origem e destino estavam iguais em todas as linhas do mesmo número — a mesma premissa que
o banco não garantia. Agora a rota é entidade com identidade própria e o agrupamento é
por chave. A consulta está em `sql_normalizado.sql`, seção 6.7.

---

## 8. Validação

O `sql_normalizado.sql` foi executado em um **MySQL 8.0.46** real, em contêiner Docker,
não apenas revisado por leitura.

**Execução limpa.** O arquivo roda inteiro de uma vez, com código de saída 0 e nenhuma
mensagem em `stderr`: cria o banco, as seis tabelas, insere os dados e executa as
consultas.

**Migração conferida.** Os mesmos registros da Aula 08, redistribuídos:

| Tabela | Registros | Origem |
|---|---|---|
| `modelo_aeronave` | 6 | 6 modelos distintos extraídos das 6 aeronaves |
| `aeronave` | 6 | inalterado |
| `passageiro` | 8 | inalterado |
| `rota` | 7 | 7 números distintos nos 8 voos — o 305 se repete |
| `voo` | 8 | inalterado |
| `passagem` | 12 | inalterado |

Os `id_voo` gerados são 1 a 8, na mesma ordem da Aula 08, o que mantém válidas as chaves
estrangeiras das 12 passagens sem nenhum remapeamento.

**Equivalência dos resultados.** As cinco consultas da Aula 08 foram executadas nos dois
bancos — o original e o normalizado — e os resultados comparados por hash:

| Consulta | Resultado |
|---|---|
| Painel de voos | idêntico |
| Lista de embarque do voo 305 | idêntico |
| Ocupação por voo | idêntico |
| Passageiros com mais de um voo | idêntico |
| Próximos voos a partir das 12:00 | idêntico |

As cinco retornam saída byte a byte igual nos dois esquemas. A normalização mudou onde o
dado mora, sem mudar o que o banco responde — que é a definição prática de decomposição
sem perda.

### Como reproduzir

```bash
mysql -u root -p < sql_aula_8.sql        # banco da Aula 08
mysql -u root -p < sql_normalizado.sql   # banco normalizado
```

Os dois arquivos são independentes e cada um recria o banco `aeroporto` do zero. Rodar o
segundo substitui o primeiro.

---

## 9. Resumo

| Forma normal | Situação | Ação |
|---|---|---|
| **1FN** | Atendida | Nenhuma. `assento` e `prefixo` avaliados como atributos compostos e mantidos: o sistema não acessa as partes separadamente. |
| **2FN** | **Violada em `voo`** | Extraída `rota`. `numero_voo → origem, destino` era dependência parcial da chave candidata `(numero_voo, data_hora_partida)`. |
| **3FN** | **Violada em `aeronave`** | Extraída `modelo_aeronave`. `modelo → fabricante` era transitiva. `capacidade_assentos` mantida em `aeronave`. |
| **4FN** | Atendida | Nenhuma. Sem atributos multivalorados independentes; o N:N já estava resolvido pela associativa desde a Aula 05. |
| **5FN** | Atendida | Nenhuma. Sem relação ternária; a decomposição de `passagem` em três projeções não seria sem perda. |

Quatro tabelas passaram a seis. Duas alterações, ambas com dependência funcional
identificada e anomalia concreta associada. Três formas normais verificadas e mantidas,
com justificativa. Quatro dependências plausíveis examinadas e descartadas por análise do
domínio: `modelo → capacidade_assentos`, `rota → duração` implicando chegada derivada,
`origem → dados do aeroporto` e `(id_voo, assento) → classe`.
