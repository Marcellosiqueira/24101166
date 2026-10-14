# Aula 21: Estrutura de sistemas

Disciplina de Banco de Dados, IDP.
Marcello Azevedo Pinheiro Siqueira, matrícula 24101166.

CRUD de voos do projeto do aeroporto em PHP e MySQL, organizado em camadas: conexão
centralizada, model com todo o SQL, controller que coordena e views só com HTML.

## Estrutura

```text
aula21-estrutura-sistemas/
├── public/                    única pasta exposta pelo servidor
│   ├── index.php              porta única de entrada
│   └── css/style.css
├── config/
│   └── database.php           a única conexão do sistema, lida do .env
├── app/
│   ├── models/Voo.php         listar, buscar, criar, editar, excluir
│   ├── controllers/VooController.php
│   └── views/
│       ├── includes/          header.php e footer.php
│       └── voos/              listar.php, criar.php, editar.php, _form.php
├── banco/usuario_app.sql      usuário do banco com privilégios mínimos
├── logs/                      erros, fora da web e fora do Git
├── .env.example               modelo do .env, que nunca vai para o Git
└── .gitignore
```

A estrutura segue a dos slides da aula (`public/`, `config/`, `app/`), com o
`includes/` do roteiro dentro de `app/views/`.

## Como executar no Laragon

1. Rodar `aula10-integridade/sql_integridade.sql`, que cria o banco `aeroporto`.
   Opcionalmente, rodar depois `aula15-triggers/triggers.sql`.
2. Rodar `banco/usuario_app.sql` como root.
3. Copiar `.env.example` para `.env` e conferir a senha.
4. Copiar a pasta para `C:\laragon\www\` e abrir
   `http://localhost/aula21-estrutura-sistemas/public/`.

Sem o Laragon, de dentro da pasta: `php -S localhost:8000 -t public`.

As pastas `config/`, `app/`, `banco/` e `logs/` têm um `.htaccess` com
`Require all denied`, então o Apache recusa acesso direto a elas mesmo que o
servidor esteja apontado para a raiz do projeto e não para `public/`.

## Adaptação ao esquema do projeto

Na normalização da Aula 09, número do voo, origem e destino foram para a tabela
`rota`, e o prefixo está em `aeronave`. Por isso:

- a listagem faz `JOIN` com `rota` e `aeronave` dentro do model;
- o formulário escolhe a rota e a aeronave por listas de seleção, e não por texto
  livre, o que evita digitar uma rota que não existe.

## Regras do voo

As regras já estão no banco desde a Aula 10, como constraint, e o model não as
repete em PHP. Ele executa o comando e, se o banco recusar, traduz o código do erro
numa mensagem para a tela:

| Situação | Erro do banco | Mensagem |
| --- | --- | --- |
| Mesma rota no mesmo horário | 1062 | Já existe um voo desta rota com a mesma data e hora de partida |
| Chegada antes da partida | 3819 (MariaDB: 4025) | A chegada prevista precisa ser depois da partida |
| Excluir voo com passagens | 1451 | Este voo tem passagens vendidas e não pode ser excluído |
| Trocar para aeronave menor que as passagens vendidas | 1644 | Mensagem da trigger da Aula 15 |

A exclusão de voo com passagens vendidas, ponto de atenção do roteiro, é recusada
pelo `ON DELETE RESTRICT` da chave estrangeira, e a tela orienta mudar o status para
Cancelado.

## Segurança

- Todo SQL com prepared statements; nenhuma variável concatenada na consulta.
- Toda saída nas views com `htmlspecialchars()`.
- Credenciais no `.env`, fora do Git e fora de `public/`.
- Usuário `aeroporto_app` só com `SELECT`, `INSERT`, `UPDATE` e `DELETE`, sem root.
- Erro detalhado vai para `logs/erros.log`; a tela mostra só "Erro interno". Para
  ver o detalhe em desenvolvimento, `APP_DEBUG=1` no `.env`.
- Criar, editar e excluir só aceitam POST. A exclusão é um formulário com botão, e
  não um link: um link de exclusão pode ser disparado por um navegador que
  pré-carrega páginas. Após gravar, a página redireciona, então recarregar não
  reenvia o formulário.

## Teste

Rodado com PHP 8.3 contra o banco da Aula 10:

| Operação | Resultado |
| --- | --- |
| Listar | 8 voos com número, rota, aeronave, partida, portão e status |
| Criar | voo gravado, mensagem "Voo cadastrado" |
| Criar duplicado | recusado com a mensagem do 1062 |
| Chegada antes da partida | recusado com a mensagem da constraint |
| Editar | formulário preenchido com os dados atuais; alteração gravada |
| Excluir voo com passagens | recusado com a mensagem do 1451 |
| Excluir voo sem passagens | excluído |
| Excluir por GET | 404 |
| Portão com HTML | exibido como texto |
| Senha errada no .env | tela mostra "Erro interno"; detalhe só no log |

## Checklist do roteiro

- [x] Estrutura de pastas organizada
- [x] Conexão em um único arquivo
- [x] Model `Voo` com listar, buscar, criar, editar e excluir
- [x] Todas as consultas com prepared statements
- [x] Nenhum SQL dentro das views
- [x] Saída de dados com `htmlspecialchars()`
- [x] Listar, criar, editar e excluir voos pelo navegador
