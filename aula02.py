# Aula 02 - Sistema academico usando apenas arquivos de texto
# alunos.txt -> ID;NOME;TELEFONE;EMAIL
# notas.txt  -> ID_ALUNO;DISCIPLINA;NOTA  (ID_ALUNO referencia o ID em alunos.txt)

ARQUIVO_ALUNOS = "alunos.txt"
ARQUIVO_NOTAS = "notas.txt"


def ler_alunos():
    alunos = []
    try:
        arquivo = open(ARQUIVO_ALUNOS, "r", encoding="utf-8")
    except FileNotFoundError:
        return alunos
    for linha in arquivo:
        linha = linha.strip()
        if linha == "":
            continue
        partes = linha.split(";")
        if len(partes) != 4:
            continue
        aluno = {
            "id": partes[0],
            "nome": partes[1],
            "telefone": partes[2],
            "email": partes[3],
        }
        alunos.append(aluno)
    arquivo.close()
    return alunos


def ler_notas():
    notas = []
    try:
        arquivo = open(ARQUIVO_NOTAS, "r", encoding="utf-8")
    except FileNotFoundError:
        return notas
    for linha in arquivo:
        linha = linha.strip()
        if linha == "":
            continue
        partes = linha.split(";")
        if len(partes) != 3:
            continue
        nota = {
            "id_aluno": partes[0],
            "disciplina": partes[1],
            "nota": partes[2],
        }
        notas.append(nota)
    arquivo.close()
    return notas


def escrever_notas(notas):
    # regrava o arquivo inteiro (usado ao editar ou excluir uma nota)
    arquivo = open(ARQUIVO_NOTAS, "w", encoding="utf-8")
    for nota in notas:
        arquivo.write(nota["id_aluno"] + ";" + nota["disciplina"] + ";" + nota["nota"] + "\n")
    arquivo.close()


def buscar_aluno_por_id(id_aluno):
    for aluno in ler_alunos():
        if aluno["id"] == id_aluno:
            return aluno
    return None


def buscar_aluno_por_nome(nome):
    # busca sem diferenciar maiusculas de minusculas
    for aluno in ler_alunos():
        if aluno["nome"].lower() == nome.lower():
            return aluno
    return None


def cadastrar_aluno():
    print("\n--- Cadastrar aluno ---")
    id_aluno = input("ID: ").strip()
    if id_aluno == "":
        print("ID nao pode ser vazio.")
        return
    if buscar_aluno_por_id(id_aluno) is not None:
        print("Ja existe um aluno com esse ID. Cadastro cancelado.")
        return
    nome = input("Nome: ").strip()
    telefone = input("Telefone: ").strip()
    email = input("Email: ").strip()
    if nome == "":
        print("Nome nao pode ser vazio.")
        return
    arquivo = open(ARQUIVO_ALUNOS, "a", encoding="utf-8")
    arquivo.write(id_aluno + ";" + nome + ";" + telefone + ";" + email + "\n")
    arquivo.close()
    print("Aluno cadastrado com sucesso!")


def listar_alunos():
    print("\n--- Lista de alunos ---")
    alunos = ler_alunos()
    if len(alunos) == 0:
        print("Nenhum aluno cadastrado.")
        return
    for aluno in alunos:
        print(
            "ID: " + aluno["id"]
            + " | Nome: " + aluno["nome"]
            + " | Telefone: " + aluno["telefone"]
            + " | Email: " + aluno["email"]
        )


def buscar_aluno():
    print("\n--- Buscar aluno por nome ---")
    nome = input("Nome do aluno: ").strip()
    encontrados = []
    for aluno in ler_alunos():
        if nome.lower() in aluno["nome"].lower():
            encontrados.append(aluno)
    if len(encontrados) == 0:
        print("Nenhum aluno encontrado.")
        return
    for aluno in encontrados:
        print(
            "ID: " + aluno["id"]
            + " | Nome: " + aluno["nome"]
            + " | Telefone: " + aluno["telefone"]
            + " | Email: " + aluno["email"]
        )


def cadastrar_nota():
    print("\n--- Cadastrar nota ---")
    id_aluno = input("ID do aluno: ").strip()
    # so grava a nota se o aluno existir em alunos.txt (integridade referencial)
    aluno = buscar_aluno_por_id(id_aluno)
    if aluno is None:
        print("Aluno nao encontrado. A nota nao foi gravada.")
        return
    disciplina = input("Disciplina: ").strip()
    if disciplina == "":
        print("Disciplina nao pode ser vazia.")
        return
    valor = input("Nota: ").strip().replace(",", ".")
    try:
        float(valor)
    except ValueError:
        print("Nota invalida. Digite um numero.")
        return
    arquivo = open(ARQUIVO_NOTAS, "a", encoding="utf-8")
    arquivo.write(id_aluno + ";" + disciplina + ";" + valor + "\n")
    arquivo.close()
    print("Nota cadastrada para o aluno " + aluno["nome"] + ".")


def consultar_nota():
    print("\n--- Consultar nota ---")
    nome = input("Nome do aluno: ").strip()
    aluno = buscar_aluno_por_nome(nome)
    if aluno is None:
        print("Aluno nao encontrado.")
        return
    disciplina = input("Disciplina: ").strip()
    achou = False
    # usa o ID do aluno para filtrar as linhas de notas.txt
    for nota in ler_notas():
        if nota["id_aluno"] == aluno["id"] and nota["disciplina"].lower() == disciplina.lower():
            print(
                "Aluno: " + aluno["nome"]
                + " | Disciplina: " + nota["disciplina"]
                + " | Nota: " + nota["nota"]
            )
            achou = True
    if not achou:
        print("Nenhuma nota encontrada para esse aluno nessa disciplina.")


def listar_notas_do_aluno():
    print("\n--- Notas de um aluno ---")
    nome = input("Nome do aluno: ").strip()
    aluno = buscar_aluno_por_nome(nome)
    if aluno is None:
        print("Aluno nao encontrado.")
        return
    achou = False
    for nota in ler_notas():
        if nota["id_aluno"] == aluno["id"]:
            print("Disciplina: " + nota["disciplina"] + " | Nota: " + nota["nota"])
            achou = True
    if not achou:
        print("Esse aluno ainda nao possui notas.")


def calcular_media():
    print("\n--- Media do aluno ---")
    nome = input("Nome do aluno: ").strip()
    aluno = buscar_aluno_por_nome(nome)
    if aluno is None:
        print("Aluno nao encontrado.")
        return
    soma = 0.0
    quantidade = 0
    for nota in ler_notas():
        if nota["id_aluno"] == aluno["id"]:
            soma = soma + float(nota["nota"])
            quantidade = quantidade + 1
    if quantidade == 0:
        print("Esse aluno ainda nao possui notas.")
        return
    media = soma / quantidade
    print("Media de " + aluno["nome"] + ": " + format(media, ".2f"))


def buscar_alunos_por_disciplina():
    print("\n--- Alunos de uma disciplina ---")
    disciplina = input("Disciplina: ").strip()
    achou = False
    for nota in ler_notas():
        if nota["disciplina"].lower() == disciplina.lower():
            # cada nota guarda so o ID, entao buscamos o nome em alunos.txt
            aluno = buscar_aluno_por_id(nota["id_aluno"])
            if aluno is None:
                print("Nota com ID " + nota["id_aluno"] + " sem aluno correspondente.")
            else:
                print("Aluno: " + aluno["nome"] + " | Nota: " + nota["nota"])
            achou = True
    if not achou:
        print("Nenhum aluno encontrado nessa disciplina.")


def editar_nota():
    print("\n--- Editar nota ---")
    nome = input("Nome do aluno: ").strip()
    aluno = buscar_aluno_por_nome(nome)
    if aluno is None:
        print("Aluno nao encontrado.")
        return
    disciplina = input("Disciplina: ").strip()
    notas = ler_notas()
    encontradas = 0
    for nota in notas:
        if nota["id_aluno"] == aluno["id"] and nota["disciplina"].lower() == disciplina.lower():
            encontradas = encontradas + 1
    if encontradas == 0:
        print("Nenhuma nota encontrada para esse aluno nessa disciplina.")
        return
    valor = input("Nova nota: ").strip().replace(",", ".")
    try:
        float(valor)
    except ValueError:
        print("Nota invalida. Digite um numero.")
        return
    for nota in notas:
        if nota["id_aluno"] == aluno["id"] and nota["disciplina"].lower() == disciplina.lower():
            nota["nota"] = valor
    escrever_notas(notas)
    print(str(encontradas) + " nota(s) atualizada(s) para " + aluno["nome"] + ".")


def excluir_nota():
    print("\n--- Excluir nota ---")
    nome = input("Nome do aluno: ").strip()
    aluno = buscar_aluno_por_nome(nome)
    if aluno is None:
        print("Aluno nao encontrado.")
        return
    disciplina = input("Disciplina: ").strip()
    notas = ler_notas()
    restantes = []
    removidas = 0
    for nota in notas:
        if nota["id_aluno"] == aluno["id"] and nota["disciplina"].lower() == disciplina.lower():
            removidas = removidas + 1
        else:
            restantes.append(nota)
    if removidas == 0:
        print("Nenhuma nota encontrada para esse aluno nessa disciplina.")
        return
    confirmacao = input("Confirmar exclusao de " + str(removidas) + " nota(s)? (s/n): ").strip().lower()
    if confirmacao != "s":
        print("Exclusao cancelada.")
        return
    escrever_notas(restantes)
    print(str(removidas) + " nota(s) excluida(s).")


def buscar_notas_acima_de():
    print("\n--- Alunos com nota acima de um valor ---")
    valor = input("Valor minimo: ").strip().replace(",", ".")
    try:
        minimo = float(valor)
    except ValueError:
        print("Valor invalido. Digite um numero.")
        return
    achou = False
    for nota in ler_notas():
        if float(nota["nota"]) > minimo:
            # a nota guarda so o ID, entao buscamos o nome em alunos.txt
            aluno = buscar_aluno_por_id(nota["id_aluno"])
            if aluno is None:
                print("Nota com ID " + nota["id_aluno"] + " sem aluno correspondente.")
            else:
                print(
                    "Aluno: " + aluno["nome"]
                    + " | Disciplina: " + nota["disciplina"]
                    + " | Nota: " + nota["nota"]
                )
            achou = True
    if not achou:
        print("Nenhuma nota acima de " + format(minimo, ".2f") + ".")


def mostrar_menu():
    print("\n===== SISTEMA ACADEMICO =====")
    print("1 - Cadastrar aluno")
    print("2 - Listar alunos")
    print("3 - Buscar aluno por nome")
    print("4 - Cadastrar nota")
    print("5 - Consultar nota (aluno + disciplina)")
    print("6 - Listar todas as notas de um aluno")
    print("7 - Calcular media de um aluno")
    print("8 - Buscar alunos por disciplina")
    print("9 - Editar uma nota")
    print("10 - Excluir uma nota")
    print("11 - Buscar alunos com nota acima de um valor")
    print("0 - Sair")


def main():
    while True:
        mostrar_menu()
        opcao = input("Escolha uma opcao: ").strip()
        if opcao == "1":
            cadastrar_aluno()
        elif opcao == "2":
            listar_alunos()
        elif opcao == "3":
            buscar_aluno()
        elif opcao == "4":
            cadastrar_nota()
        elif opcao == "5":
            consultar_nota()
        elif opcao == "6":
            listar_notas_do_aluno()
        elif opcao == "7":
            calcular_media()
        elif opcao == "8":
            buscar_alunos_por_disciplina()
        elif opcao == "9":
            editar_nota()
        elif opcao == "10":
            excluir_nota()
        elif opcao == "11":
            buscar_notas_acima_de()
        elif opcao == "0":
            print("Encerrando o programa.")
            break
        else:
            print("Opcao invalida.")


main()
