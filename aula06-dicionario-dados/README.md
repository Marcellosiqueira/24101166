# Aula 06 — Dicionário de Dados

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Documentação técnica do banco `aeroporto`, montada sobre o modelo de dicionário de
dados fornecido pelo professor.

## Arquivo

`Aula06_Dicionario_de_Dados_Marcello_Siqueira.docx`, 6 páginas.

O documento parte do `.docx` original do professor, preservando os estilos, a
numeração das seções e o texto das seções 1 a 3. O que mudou foi o preenchimento
e dois ajustes de formatação: as tabelas passaram a ocupar a largura útil da
página, porque com 11 colunas na largura original a palavra "VARCHAR" quebrava em
três linhas, e as linhas foram marcadas para não serem cortadas no meio pela
quebra de página, com o cabeçalho se repetindo nas continuações.

A seção 11 do modelo, "Exemplo preenchido", foi removida. Era um exemplo
ilustrativo de uma tabela de usuários, parte do template e não do sistema
documentado.

## O que a atividade pedia

| Item | Onde está |
| --- | --- |
| Nome e descrição de cada tabela | seção 5, uma ficha por tabela |
| Campos, tipo, tamanho, obrigatoriedade | seção 5.2 de cada ficha |
| PK e FK | colunas PK? e FK? das fichas, detalhadas na seção 6 |
| Valor padrão | coluna Default |
| Regras ou domínio dos valores | coluna Regra / Domínio, com os domínios fechados na seção 8 |
| Exemplos de valores | coluna Exemplo |
| Relacionamentos entre as tabelas | seção 6 |
| Pelo menos 3 regras de negócio | seção 7, com 9 regras |
| Índices e restrições | seção 9, com 11 índices |

## Conteúdo

Quatro tabelas documentadas: `aeronave`, `passageiro`, `voo` e a associativa
`passagem`. São as mesmas do modelo lógico da Aula 05 e do banco criado na Aula
08, então o dicionário descreve um banco que existe e roda, não um desenho no
papel.

As 9 regras de negócio estão classificadas pela forma como são aplicadas: UNIQUE,
CHECK, FK ou aplicação. Oito das nove estão no banco como constraint e foram
verificadas rodando o `testes_constraints.sql` da Aula 08.

A RN-009, que impediria um passageiro de estar em dois voos simultâneos de
aeroportos diferentes, está documentada como **não implementada**. É uma regra
temporal, envolve comparar `data_hora_partida` entre registros distintos, e
`UNIQUE` não alcança. Documentar a lacuna em vez de omitir é o ponto: quem ler o
dicionário precisa saber que essa validação não está no banco.

## Relação com as outras entregas

- Aula 05: modelo lógico de onde vem a estrutura
- Aula 08: script MySQL que implementa o modelo, de onde vêm os tipos, tamanhos,
  defaults e nomes de constraint registrados aqui
