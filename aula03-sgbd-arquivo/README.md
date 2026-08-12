# Simulando um SGBD sobre arquivos de texto

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Base: painel de voos, 30 registros, delimitador `;`.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `sgbd.py` | Implementação dos três desafios e menu interativo |
| `demo.py` | Executa tudo sem interação, para conferir a saída de uma vez |
| `dados.txt` | Base fornecida |

Esquema:

```
ID;NUMERO_VOO;DESTINO;PORTAO;HORARIO;STATUS
1;305;Brasilia;12;08:30;Embarque
```

O delimitador é detectado em tempo de execução e os nomes das colunas vêm do
cabeçalho, então o código não tem string literal de coluna espalhada pelo corpo.

## Execução

```bash
python3 sgbd.py    # menu interativo
python3 demo.py    # todas as consultas de uma vez
```

## Desafio 1: Full Table Scan

`full_table_scan()` percorre o arquivo linha a linha, faz o `split` pelo
delimitador e imprime a tabela formatada.

A leitura usa um generator (`ler_registros`), não uma lista. O consumo de memória
fica constante independente do tamanho do arquivo, que é o comportamento de um
iterador de tuplas de um SGBD. `read()` ou `readlines()` trariam o arquivo inteiro
para a RAM.

```
SELECT * FROM voos;

ID | NUMERO_VOO | DESTINO        | PORTAO | HORARIO | STATUS
---+------------+----------------+--------+---------+-----------
1  | 305        | Brasilia       | 12     | 08:30   | Embarque
2  | 420        | Rio de Janeiro | 08     | 09:15   | Confirmado
...
30 | 650        | Brasilia       | 05     | 23:55   | Confirmado

(30 registro(s))
Linhas lidas: 30 | Tempo: 0.058 ms
```

## Desafio 2: Busca por chave primária

`buscar_por_id(id)` compara o primeiro campo de cada linha e sai do laço com
`return` assim que encontra. O contador `linhas_lidas` aparece na saída de
propósito: é ele que expõe o custo real da consulta.

ID existente:

```
SELECT * FROM voos WHERE ID = 17;

  ID           : 17
  NUMERO_VOO   : 732
  DESTINO      : Rio de Janeiro
  PORTAO       : 05
  HORARIO      : 18:00
  STATUS       : Confirmado

Encontrado apos ler 17 de 30 linha(s). Tempo: 0.021 ms
Leitura interrompida (early exit).
```

ID inexistente:

```
SELECT * FROM voos WHERE ID = 99;

Nenhum voo encontrado com ID = 99.
Arquivo percorrido inteiro: 30 linha(s) lidas. Tempo: 0.024 ms
Sem indice, provar que a chave nao existe custa o arquivo todo.
```

A diferença entre os dois casos é o ponto do desafio. Achar o ID 17 custa 17
leituras. Concluir que o ID 99 não existe custa as 30, o arquivo inteiro. O early
exit ajuda no caso positivo e não ajuda em nada no negativo, porque sem estrutura
auxiliar não há como afirmar que a chave não está lá sem olhar tudo.

Vale registrar uma observação sobre o esquema: `ID` é a chave primária, mas
`NUMERO_VOO` é o identificador que o passageiro usa. São duas chaves candidatas.
`ID` é chave substituta (surrogate key), `NUMERO_VOO` seria chave natural. Em um
SGBD real, `NUMERO_VOO` receberia uma constraint `UNIQUE` e provavelmente um índice
próprio, já que quase nenhuma consulta de usuário parte do `ID`.

## Desafio 3: Filtro e projeção

`consultar(projecao, coluna_filtro, operador, valor)` aceita `>`, `>=`, `<`, `<=`,
`=` e `!=`. A projeção é resolvida por índice de coluna uma única vez antes do
laço, não a cada linha.

Voos para Brasília, apenas número e portão:

```
SELECT NUMERO_VOO, PORTAO FROM voos WHERE DESTINO = Brasilia;

NUMERO_VOO | PORTAO
-----------+-------
305        | 12
308        | 07
215        | 09
104        | 03
290        | 11
156        | 10
681        | 13
806        | 01
314        | 06
650        | 05

(10 registro(s))
Linhas lidas: 30 | Linhas retornadas: 10 | Tempo: 0.070 ms
```

Voos a partir das 18:00:

```
SELECT NUMERO_VOO, DESTINO, HORARIO FROM voos WHERE HORARIO >= 18:00;

NUMERO_VOO | DESTINO        | HORARIO
-----------+----------------+--------
732        | Rio de Janeiro | 18:00
156        | Brasilia       | 18:20
...
(14 registro(s))
```

Voos com número acima de 700:

```
SELECT NUMERO_VOO, DESTINO, STATUS FROM voos WHERE NUMERO_VOO > 700;

(8 registro(s))
```

### Tratamento de tipos

Três detalhes do arquivo obrigam a cuidar da conversão antes de comparar:

`NUMERO_VOO` precisa virar número. Como todo campo lido de arquivo texto é string,
comparar direto faria `"711" > "700"` funcionar por coincidência, mas `"99" > "700"`
retornaria `True`, porque a ordem lexicográfica compara caractere a caractere. A
função `_converter` tenta `float` primeiro.

`PORTAO` tem zero à esquerda (`08`, `01`, `05`). Está declarado em `COLUNAS_TEXTUAIS`
e é comparado como texto. Converter para número funcionaria nas comparações, mas
descaracteriza o dado: portão é identificador, não quantidade. Ninguém soma portões.

`HORARIO` fica como texto e a comparação lexicográfica resolve. O formato `HH:MM`
com zero à esquerda tem a propriedade de que a ordem alfabética coincide com a
ordem cronológica, então `"18:00" >= "12:00"` está correto sem parsing de data. Isso
só vale porque o formato é fixo e zero-padded. Se houvesse `8:30` sem o zero, a
comparação quebraria e seria necessário converter para minutos desde a meia-noite.

### O custo real da projeção

A saída mostra `Linhas lidas: 30 | Linhas retornadas: 10`. Mesmo devolvendo 10
linhas e 2 colunas, o I/O foi o arquivo inteiro com todas as 6 colunas. A projeção
reduz o que chega ao usuário, não o que sai do disco.

Em um SGBD orientado a linhas, o comportamento é o mesmo: a página lida traz a
tupla completa. Em um SGBD colunar, cada coluna vive em um arquivo separado e
selecionar só `NUMERO_VOO` e `PORTAO` realmente evita tocar em `DESTINO`, `HORARIO`
e `STATUS`. É por isso que bancos analíticos são colunares.

## Questões para reflexão

### 1. Desempenho com milhões de linhas

A busca do Desafio 2 é O(n) em número de registros. Com 30 linhas o tempo é
0,021 ms e ninguém percebe. Com 10 milhões de linhas a cerca de 45 bytes por
registro, são aproximadamente 450 MB que precisam atravessar o barramento de disco
a cada consulta.

Três efeitos aparecem nessa escala:

**Custo médio e pior caso.** Em média a busca lê n/2 linhas. Chave inexistente lê n
linhas, sempre. Em um painel de voos consultado por número de voo digitado pelo
usuário, erro de digitação é comum, e cada erro custa o arquivo inteiro.

**I/O domina, não CPU.** O `split` e a comparação de string são baratos. O gargalo é
trazer os blocos do disco para a memória. Em SSD NVMe, 450 MB de leitura sequencial
levam por volta de 0,15 a 0,3 segundo. Em HDD, algo entre 4 e 6 segundos. Por
consulta.

**Concorrência multiplica.** Cem terminais de aeroporto consultando ao mesmo tempo
significam cem varreduras competindo pela mesma banda de disco. O tempo de resposta
individual degrada bem além do linear, porque a fila de I/O satura.

A medição está no código, na opção 4 do menu. O script replica a base para 300 mil
registros e busca o último ID, pior caso do scan:

```
Escala           |  Registros |    Scan (ms) |  Indice (ms) |    Ganho
------------------------------------------------------------------------
base original    |         30 |       0.0700 |       0.0086 |       8x
base replicada   |    300,000 |     176.6017 |       0.0186 |    9505x
```

O scan saiu de 0,07 ms para 176 ms, um fator próximo de 2.500 para 10.000 vezes
mais registros. Comportamento linear, como esperado. A busca indexada saiu de
0,0086 ms para 0,0186 ms, praticamente constante. Extrapolando para 10 milhões de
registros, o scan passaria de 5 segundos enquanto o índice continuaria na casa dos
microssegundos.

Uma melhoria parcial sem índice seria ordenar o arquivo por ID e aplicar busca
binária com `seek`, caindo para O(log n). Isso exige registros de tamanho fixo ou
uma tabela de offsets, e quebra em toda inserção fora de ordem. É essencialmente o
motivo de a solução real ser o índice.

### 2. Como um índice evita a leitura sequencial

O índice troca leitura de dado por leitura de metadado. Em vez de percorrer os
registros procurando a chave, o sistema consulta uma estrutura pequena que mapeia
chave para endereço físico e vai direto ao ponto.

**Tabela hash.** Aplica uma função de hash sobre a chave e obtém o bucket com o
ponteiro para o registro. Custo O(1) médio. A implementação em `construir_indice` e
`buscar_com_indice` é exatamente isso: um `dict` de `ID -> offset em bytes`, seguido
de `seek(offset)` e uma única leitura de linha. O índice guarda a posição, não o
registro, o que mantém a estrutura pequena o bastante para caber na memória.

A limitação do hash é que ele só serve para igualdade. `WHERE ID = 17` funciona,
`WHERE HORARIO >= '18:00'` não aproveita nada, porque o hash destrói a ordem das
chaves. Duas chaves consecutivas caem em buckets sem relação nenhuma.

**Árvore B / B+.** Mantém as chaves ordenadas em uma árvore de alto fator de
ramificação, com cada nó do tamanho de uma página de disco, tipicamente 4 KB ou
8 KB. Com fator de ramificação na casa das centenas, 10 milhões de registros cabem
em 3 ou 4 níveis. A busca custa 3 ou 4 acessos a disco contra os milhões do scan.

Como as chaves ficam ordenadas e as folhas da B+ são encadeadas entre si, a mesma
estrutura resolve consultas de faixa, prefixo e `ORDER BY` sem ordenação adicional.
Aplicado a este painel: um índice B+ sobre `HORARIO` responde "próximos voos a
partir das 18:00" descendo até a primeira folha que satisfaz o critério e seguindo o
encadeamento, sem tocar nos voos da manhã. É por isso que B+ é o índice padrão da
maioria dos SGBDs e hash fica reservado para igualdade pura.

Para esta base especificamente, os índices que fariam sentido: `ID` como chave
primária, índice automático; `NUMERO_VOO` com `UNIQUE`, porque é por ele que o
usuário consulta; `HORARIO` em B+, para as consultas de faixa do painel; `DESTINO` e
`STATUS` provavelmente não valem índice, porque têm baixa cardinalidade. Com apenas
três valores possíveis de `STATUS`, qualquer filtro retorna cerca de um terço da
tabela e o otimizador escolheria o full table scan de propósito.

Esse é o ponto de virada que costuma ser esquecido: quando a consulta retorna uma
fração grande da tabela, digamos acima de 20% ou 30%, leitura sequencial é mais
rápida que milhares de acessos aleatórios espalhados pelo disco. O índice também não
é grátis: ocupa espaço, precisa ser atualizado a cada `INSERT`, `UPDATE` e `DELETE`,
e essa manutenção pesa em carga de escrita intensa. Um painel de voos escreve muito,
já que status e portão mudam o tempo todo.

### 3. Concorrência entre dois processos

O arquivo texto não tem controle de concorrência nenhum. O cenário do painel de voos
torna os problemas concretos, porque o check-in escreve enquanto os monitores leem.

**Lost update.** O processo A e o processo B leem o voo de ID 5, ambos com status
`Aguardando`. A muda para `Embarque` e grava. B, que ainda tem a versão antiga em
memória, muda o portão de `07` para `19` e grava. A alteração de A desaparece. O
painel mostra `Aguardando` no portão 19 quando o voo já está embarcando.

**Leitura suja.** B lê o arquivo enquanto A está no meio da reescrita e pega um
estado parcial, possivelmente uma linha truncada no meio de um campo. O monitor
exibe um voo com destino cortado ou horário vazio. A consulta retornou um dado que
nunca existiu de forma consistente.

**Corrupção estrutural.** Alterar uma linha no meio do arquivo muda o comprimento
total quando o novo valor tem tamanho diferente, então a operação normal é reescrever
o arquivo inteiro. Dois processos reescrevendo simultaneamente, ou uma queda no meio
da reescrita, deixam o arquivo truncado ou com registros duplicados. Não existe
rollback: o estado anterior já foi sobrescrito.

**Índices dessincronizados.** Se houver índice de offsets em memória e o arquivo for
reescrito por outro processo, todos os offsets passam a apontar para posições
erradas. A busca pelo ID 17 retorna o voo 23, sem erro nenhum, silenciosamente. Esse
é o pior tipo de falha, porque não aparece em log.

**Leitura não repetível e registros fantasma.** A mesma consulta executada duas vezes
dentro de uma operação retorna resultados diferentes porque B alterou ou inseriu
linhas no intervalo. Um relatório que soma voos por status pode contar o mesmo voo em
duas categorias.

O que um SGBD coloca no lugar disso:

- Bloqueios em nível de linha, compartilhados para leitura e exclusivos para escrita,
  em vez de travar o arquivo inteiro
- MVCC, onde cada transação enxerga uma versão consistente dos dados e leitores não
  bloqueiam escritores, que é o que permite os monitores lerem enquanto o check-in
  escreve
- Write-ahead log, que grava a intenção antes da alteração e permite rollback e
  recuperação após queda de energia
- Detecção de deadlock, para o caso de A esperar por B enquanto B espera por A
- Atomicidade, garantindo que a transação inteira é aplicada ou nenhuma parte dela é

Um paliativo em arquivo é usar `fcntl.flock` para bloqueio exclusivo e escrever em
arquivo temporário seguido de `os.replace`, que é atômico dentro do mesmo sistema de
arquivos. Isso resolve corrupção e leitura suja, mas serializa todo o acesso: um
escritor bloqueia todo mundo, inclusive os leitores. É o motivo de existirem SGBDs em
vez de todos manipularmos CSV.
