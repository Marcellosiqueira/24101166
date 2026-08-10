# Atividade Prática 01 — Conceito de Dado e Informação

**Disciplina:** Banco de Dados
**Aluno:** Marcello Siqueira
**Cenário:** Sistema de Gerenciamento de Aeroporto

---

## Introdução

Antes de escrever qualquer linha de código, é preciso entender o que o sistema
vai guardar e o que ele precisa responder. Essa é a diferença entre **dado** e
**informação**:

- **Dado** é o registro bruto, isolado, sem contexto. Exemplo: `14:30`, `GOL`,
  `A320`, `atrasado`.
- **Informação** é o dado processado, relacionado e colocado em contexto, capaz
  de apoiar uma decisão. Exemplo: "O voo G3-1234, da GOL, previsto para as
  14:30, está atrasado em 40 minutos e embarcará no portão 12".

O mesmo dado (`14:30`) não diz nada sozinho. Ele só vira informação quando é
combinado com outros dados e ganha significado.

---

## 1. Levantamento dos dados

Os dados foram organizados em grupos por entidade, do jeito que provavelmente
virariam tabelas mais adiante no curso.

### 1.1 Passageiros

| Dado | Descrição |
|------|-----------|
| ID do passageiro | Identificador único interno do sistema |
| Nome completo | Nome como consta no documento |
| CPF / Passaporte | Documento oficial usado no check-in |
| Data de nascimento | Necessária para tarifas e regras de menor desacompanhado |
| Nacionalidade | Relevante para voos internacionais e imigração |
| Telefone | Contato para avisos de alteração de voo |
| E-mail | Envio de cartão de embarque e notificações |
| Necessidade especial | Cadeira de rodas, acompanhamento, restrição de mobilidade |
| Programa de fidelidade | Número e categoria (se houver) |

### 1.2 Voos

| Dado | Descrição |
|------|-----------|
| Número do voo | Código comercial (ex.: G3-1234) |
| Companhia aérea | Operadora responsável pelo voo |
| Aeroporto de origem | Código IATA (ex.: BSB) |
| Aeroporto de destino | Código IATA (ex.: GRU) |
| Data e hora de partida prevista | Base para a programação do aeroporto |
| Data e hora de chegada prevista | Usada para conexões e escala de equipe |
| Data e hora reais | Permitem medir atraso e pontualidade |
| Status do voo | Programado, em embarque, decolado, atrasado, cancelado |
| Portão de embarque | Local onde o passageiro deve se apresentar |
| Aeronave utilizada | Liga o voo ao equipamento e à sua capacidade |
| Tipo do voo | Doméstico ou internacional |

### 1.3 Aeronaves

| Dado | Descrição |
|------|-----------|
| Prefixo / matrícula | Identificador único da aeronave (ex.: PR-ABC) |
| Modelo | Ex.: A320, B737-800 |
| Fabricante | Airbus, Boeing, Embraer |
| Capacidade de passageiros | Limite de assentos por classe |
| Capacidade de carga | Peso máximo de bagagem e carga |
| Companhia proprietária | A quem a aeronave pertence |
| Ano de fabricação | Idade da frota |
| Data da última manutenção | Controle de liberação para voo |
| Situação operacional | Disponível, em manutenção, inoperante |

### 1.4 Companhias aéreas

| Dado | Descrição |
|------|-----------|
| Código IATA/ICAO | Identificação padronizada da empresa |
| Razão social | Nome jurídico |
| Nome fantasia | Nome comercial |
| CNPJ | Necessário para contratos e faturamento |
| País de origem | Define tratamento doméstico ou estrangeiro |
| Contato operacional | Telefone e e-mail do representante no aeroporto |
| Balcões de check-in alocados | Espaço físico contratado no terminal |

### 1.5 Bagagens

| Dado | Descrição |
|------|-----------|
| Código da etiqueta | Identificador único da bagagem (tag) |
| Passageiro proprietário | Vínculo com quem despachou |
| Voo vinculado | Em qual voo a bagagem foi despachada |
| Peso | Base para cobrança de excesso |
| Dimensões | Controle de volume e de bagagem especial |
| Tipo | Comum, especial, frágil, animal vivo |
| Status | Despachada, em trânsito, embarcada, entregue, extraviada |
| Local atual | Última leitura registrada na esteira |

### 1.6 Funcionários

| Dado | Descrição |
|------|-----------|
| Matrícula | Identificador único do funcionário |
| Nome completo | Identificação pessoal |
| CPF | Documento oficial |
| Cargo / função | Check-in, segurança, solo, controlador, limpeza |
| Setor | Área do aeroporto onde atua |
| Empresa empregadora | Aeroporto, companhia aérea ou terceirizada |
| Turno de trabalho | Escala e horário |
| Nível de acesso | Áreas restritas que pode acessar |
| Data de admissão | Controle de vínculo |

### 1.7 Reservas e bilhetes

| Dado | Descrição |
|------|-----------|
| Código da reserva (localizador) | Identificador da compra |
| Passageiro | Quem viajará |
| Voo | Qual voo foi reservado |
| Assento | Poltrona designada |
| Classe | Econômica, executiva, primeira |
| Valor pago | Controle financeiro |
| Forma de pagamento | Cartão, pix, milhas |
| Status da reserva | Confirmada, check-in realizado, embarcada, cancelada, no-show |
| Data e hora do check-in | Registro do atendimento |

### 1.8 Infraestrutura do aeroporto

| Dado | Descrição |
|------|-----------|
| Portões de embarque | Número, terminal e situação (livre/ocupado) |
| Pistas | Identificação, comprimento e situação operacional |
| Pátios e posições de estacionamento | Onde cada aeronave fica alocada |
| Esteiras de bagagem | Número e voo vinculado no momento |
| Balcões de check-in | Número, terminal e companhia alocada |
| Terminais | Divisão física do aeroporto |

---

## 2. Informações que o sistema deverá fornecer

A partir dos dados acima, o sistema deve ser capaz de responder:

1. Quais são os próximos voos a partir de agora, com horário e portão.
2. Quais voos estão atrasados e qual o tempo médio de atraso do dia.
3. Lista completa de passageiros de um voo específico.
4. Histórico de viagens de um determinado passageiro.
5. Quantidade de bagagens despachadas por voo e o peso total transportado.
6. Portão de embarque atual de cada voo em operação.
7. Taxa de ocupação de um voo (assentos vendidos sobre assentos disponíveis).
8. Quais aeronaves estão disponíveis para voar e quais estão em manutenção.
9. Quais portões estão livres em determinado horário.
10. Quantos passageiros passaram pelo aeroporto em um dia, mês ou ano.
11. Ranking das companhias aéreas por pontualidade.
12. Rotas mais movimentadas com origem ou destino no aeroporto.
13. Localização atual de uma bagagem a partir do código da etiqueta.
14. Relação de bagagens extraviadas e seus respectivos passageiros.
15. Escala de funcionários por turno e por setor.
16. Passageiros com necessidade de assistência especial em cada voo.
17. Faturamento por companhia aérea em determinado período.
18. Horários de pico de movimento no terminal.
19. Passageiros que não compareceram ao embarque (*no-show*) por voo.
20. Quais voos uma determinada aeronave realizou em um período.

---

## 3. Dados indispensáveis

Se fosse preciso reduzir o sistema ao mínimo viável, estes dez dados não
poderiam faltar:

| # | Dado | Por que é indispensável |
|---|------|-------------------------|
| 1 | ID do passageiro | Identifica cada pessoa de forma única, mesmo que existam homônimos, e liga o passageiro às reservas e bagagens. |
| 2 | CPF ou passaporte | É o documento conferido no check-in e no embarque; sem ele não há como validar quem está viajando. |
| 3 | Número do voo | Identifica de forma única cada operação e é a referência usada por passageiros, companhias e funcionários. |
| 4 | Data e hora de partida | Organiza toda a programação do aeroporto: portões, pistas, escalas e conexões dependem dela. |
| 5 | Aeroporto de origem e destino | Sem eles o voo não tem sentido; definem a rota e o tipo de operação (doméstica ou internacional). |
| 6 | Status do voo | É o dado mais consultado por passageiros e o que dispara ações operacionais em caso de atraso ou cancelamento. |
| 7 | Prefixo da aeronave | Liga o voo ao equipamento real, permitindo controlar capacidade, manutenção e disponibilidade da frota. |
| 8 | Código da reserva | Amarra passageiro, voo e assento; é a chave que o passageiro apresenta no atendimento. |
| 9 | Código da etiqueta de bagagem | Único jeito de rastrear uma mala e devolvê-la ao dono certo em caso de extravio. |
| 10 | Portão de embarque | Informação operacional crítica: sem ela o passageiro não sabe para onde ir e o embarque não acontece. |

---

## 4. Perguntas para o cliente

Perguntas que eu faria na reunião de levantamento de requisitos:

1. O check-in poderá ser feito apenas no balcão ou também por totem e aplicativo? Cada canal precisa ser registrado de forma diferente?
2. Existe limite de peso e de quantidade de bagagens por passageiro? Esse limite varia por companhia ou por classe do bilhete?
3. Um passageiro pode remarcar ou cancelar o voo pelo sistema? Quem tem permissão para fazer isso?
4. Como o embarque será controlado na prática — leitura do cartão de embarque, biometria ou conferência manual?
5. O aeroporto opera voos internacionais? Se sim, o sistema precisa se integrar com Polícia Federal, Receita ou órgãos de imigração?
6. O sistema deve controlar apenas passageiros ou também carga e correio?
7. Quem faz a alocação dos portões de embarque e das posições de pátio: o próprio aeroporto ou cada companhia? O sistema deve sugerir essa alocação automaticamente?
8. Quais informações precisam ser exibidas nos painéis de voo do terminal e com que frequência elas são atualizadas?
9. Como o aeroporto trata hoje uma bagagem extraviada? Existe um prazo ou um fluxo definido que o sistema precise seguir?
10. Quais funcionários terão acesso ao sistema e o que cada perfil poderá visualizar ou alterar? Há dados que só a companhia aérea pode ver?
11. Os dados históricos precisam ser mantidos por quanto tempo? Existe alguma exigência legal ou da ANAC sobre isso?
12. O sistema precisará se comunicar com os sistemas das companhias aéreas ou funcionará de forma independente?

---

## 5. Reflexão

### Qual foi a maior dificuldade encontrada durante a atividade?

A maior dificuldade foi separar o que é **dado** do que é **informação**. No
começo, itens como "voos atrasados" e "ocupação do voo" apareceram na lista de
dados, quando na verdade são resultados obtidos a partir de outros dados: o
atraso vem da comparação entre o horário previsto e o horário real, e a ocupação
vem da contagem de reservas confrontada com a capacidade da aeronave. Nenhum dos
dois precisa ser armazenado — os dois precisam ser calculados.

A segunda dificuldade foi decidir o nível de detalhe. É tentador tentar prever
tudo, mas o levantamento fica grande demais e perde utilidade. Foi necessário
escolher o que é essencial para o funcionamento do aeroporto e deixar o resto
para uma etapa posterior.

### É possível desenvolver um sistema sem esse levantamento inicial? Justifique.

Tecnicamente é possível começar a programar sem levantamento, mas o resultado
tende a ser um sistema que precisa ser refeito. Sem saber quais informações o
cliente espera, corre-se o risco de não armazenar algum dado necessário — e um
dado que não foi guardado não pode ser recuperado depois. Se o sistema nunca
registrou o horário real de partida, por exemplo, não existe cálculo que produza
o histórico de atrasos do ano passado.

Além disso, mudar a estrutura de um banco de dados que já está em produção, com
dados reais dentro, é bem mais caro do que planejá-la corretamente antes. O
levantamento inicial é justamente o momento em que errar é barato: alterar uma
lista em Markdown custa alguns minutos, enquanto alterar uma tabela em produção
pode significar migração de dados, indisponibilidade do sistema e retrabalho em
tudo o que depende dela.

---

## Conclusão

O exercício mostra que o banco de dados de um aeroporto não é uma coleção solta
de campos: os dados só se tornam úteis quando estão relacionados entre si. Um
passageiro se conecta a uma reserva, que se conecta a um voo, que se conecta a
uma aeronave e a uma bagagem. É esse encadeamento que transforma dado em
informação e permite responder perguntas reais da operação.
