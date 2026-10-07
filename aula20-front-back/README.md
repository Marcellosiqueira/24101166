# Aula 20: Front + Back

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

Aplicação com MySQL, PHP e JavaScript (Fetch API) que lista alunos, notas e status
acadêmico, em duas versões: a inicial calcula o status no JavaScript, a final calcula
no PHP.

## Arquivos

```text
aula20-front-back/
├── index.html          versão final
├── index-v1.html       versão inicial
├── js/
│   ├── tabela.js       montagem da tabela, usada pelas duas versões
│   ├── app.js          versão final: só exibe o status recebido
│   └── app-v1.js       versão inicial: calcula o status
├── api/
│   ├── conexao.php     conexão PDO e resposta JSON
│   ├── alunos.php      versão final: devolve o status calculado
│   └── alunos-v1.php   versão inicial: devolve só id, nome e nota
└── banco/
    └── alunos.sql      criação do banco, da tabela e dos 6 registros
```

As duas versões ficam lado a lado para a comparação pedida no item 8. Cada página tem
um link para a outra.

## Como executar no Laragon

1. Abrir o Laragon e clicar em Start All.
2. Executar `banco/alunos.sql` no HeidiSQL (Database, depois Arquivo, Executar arquivo
   SQL) ou no Workbench. Ele cria o banco `aula20`.
3. Copiar a pasta `aula20-front-back` para `C:\laragon\www\`.
4. Abrir `http://localhost/aula20-front-back/` no navegador.

A conexão usa o padrão do Laragon, `root` sem senha em `127.0.0.1`. Para outro
ambiente, as variáveis `DB_HOST`, `DB_NAME`, `DB_USER` e `DB_PASS` substituem os
valores sem alterar o código.

A página precisa ser aberta pelo servidor, com `http://localhost`. Aberta direto do
disco, com `file://`, o navegador bloqueia o `fetch()` e o PHP não é executado.

## Dados

Seis alunos, três aprovados e três reprovados. Dois registros estão ali de propósito
para testar o limite da regra: Carlos Mendes com 7,00, que precisa sair aprovado
porque a regra é nota maior ou igual a 7, e Fernanda Rocha com 6,99, que precisa sair
reprovada. A tabela tem `CHECK (nota BETWEEN 0 AND 10)`, então uma nota 11 é recusada
pelo banco.

## Resultado

| Aluno | Nota | Status |
|---|---:|---|
| Ana Souza | 8,5 | Aprovado |
| Bruno Lima | 6,0 | Reprovado |
| Carlos Mendes | 7,0 | Aprovado |
| Daniel Oliveira | 5,5 | Reprovado |
| Eduarda Santos | 9,0 | Aprovado |
| Fernanda Rocha | 6,99 | Reprovado |

As duas versões produzem exatamente esta tabela. Foi conferido carregando as duas
páginas com `fetch()` real contra o PHP e o MySQL.

## Detalhes de implementação

**Conversão da nota no PHP.** O PDO devolve colunas `DECIMAL` como texto, então sem
conversão o JSON sairia com `"nota": "8.50"`, entre aspas. Na versão inicial o
JavaScript compararia texto com número. O PHP converte com `(float)` antes de gerar o
JSON, e a nota sai como `8.5`.

**Erro sem detalhe para o cliente.** Se o banco falhar, a API responde HTTP 500 com
`{"erro": "Falha ao consultar os alunos"}` e grava a mensagem real no log do servidor.
A mensagem do PDO pode conter nome de banco, usuário e host, que não devem chegar ao
navegador.

**Nome exibido como texto.** A tabela é montada com `textContent`, sem concatenar
HTML. Um nome cadastrado como `<img src=x onerror=alert(1)>` aparece escrito na tela
em vez de ser executado. Foi testado.

## Onde a regra de negócio deve ficar

No backend. A versão final é a correta, pelos motivos que o enunciado lista.

**Segurança.** Todo código JavaScript roda no computador do usuário e pode ser lido e
alterado pelas ferramentas de desenvolvedor do navegador. Na versão inicial, trocar
`>= 7` por `>= 0` faz todos aparecerem aprovados na tela. O dado no banco não muda,
mas qualquer decisão tomada a partir daquela tela passa a valer sobre uma regra que o
usuário controla. No PHP, a regra roda no servidor e o cliente só recebe o resultado.

**Reutilização e diferentes clientes.** Se amanhã existir um aplicativo de celular, um
relatório em PDF e uma integração com o sistema da secretaria, na versão inicial cada
um precisa reimplementar a regra. Na versão final todos consomem o mesmo
`alunos.php` e recebem o mesmo status.

**Consistência.** Com a regra copiada em vários clientes, basta um deles ficar
desatualizado para o mesmo aluno aparecer aprovado num lugar e reprovado em outro.
Com uma regra só, isso não acontece.

**Manutenção.** Se a média mínima mudar de 7 para 6, a versão final muda uma
constante, `NOTA_MINIMA_APROVACAO`, em um arquivo. A versão inicial exige alterar e
republicar todo cliente que tiver a regra, e torcer para que os navegadores não usem
a versão antiga em cache.

**Responsabilidade de cada camada.** O backend decide, o frontend apresenta. Na versão
final o `app.js` tem uma linha e não sabe o que é aprovação. A decisão de mostrar
"Aprovado" em verde é de apresentação e continua no frontend, onde deve estar.

A validação no frontend ainda tem lugar, para dar retorno rápido ao usuário, como
avisar que uma nota digitada passa de 10 antes de enviar o formulário. Ela serve como
conveniência; a regra que vale continua sendo a do servidor.

Existe ainda uma terceira posição possível, no próprio banco, com uma coluna gerada ou
uma view calculando o status. Ela tem a vantagem de valer até para quem consulta o
banco direto, sem passar pelo PHP, que é o argumento que usei nas Aulas 08 e 10 para
colocar as regras de integridade no banco. Para esta atividade a regra fica no PHP,
como o enunciado pede, e a diferença é registrada aqui porque a mesma pergunta se
aplica um nível abaixo.
