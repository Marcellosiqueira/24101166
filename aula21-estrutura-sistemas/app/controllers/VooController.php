<?php
// Recebe a requisicao, chama o model e escolhe a view. Nao tem SQL.

require_once __DIR__ . '/../models/Voo.php';

class VooController
{
    private Voo $voo;

    public function __construct()
    {
        $this->voo = new Voo();
    }

    public function listar(): void
    {
        $voos = $this->voo->listar();
        $this->tela('listar', ['voos' => $voos]);
    }

    public function criar(): void
    {
        $this->tela('criar', $this->opcoes() + ['dados' => ['status' => 'Aguardando']]);
    }

    public function salvar(): void
    {
        try {
            $this->voo->criar($_POST);
        } catch (DomainException $e) {
            $this->tela('criar', $this->opcoes() + ['dados' => $_POST, 'erro' => $e->getMessage()]);
            return;
        }
        $this->voltar('Voo cadastrado.');
    }

    public function editar(): void
    {
        $id = (int) ($_GET['id'] ?? 0);
        $voo = $this->voo->buscar($id);
        if ($voo === null) {
            $this->voltar('Voo não encontrado.');
        }
        $this->tela('editar', $this->opcoes() + ['dados' => $voo]);
    }

    public function atualizar(): void
    {
        $id = (int) ($_POST['id_voo'] ?? 0);
        try {
            $this->voo->editar($id, $_POST);
        } catch (DomainException $e) {
            $this->tela('editar', $this->opcoes() + ['dados' => $_POST, 'erro' => $e->getMessage()]);
            return;
        }
        $this->voltar('Voo atualizado.');
    }

    public function excluir(): void
    {
        try {
            $this->voo->excluir((int) ($_POST['id_voo'] ?? 0));
        } catch (DomainException $e) {
            $this->voltar($e->getMessage(), 'erro');
        }
        $this->voltar('Voo excluído.');
    }

    private function opcoes(): array
    {
        return [
            'rotas'     => $this->voo->rotas(),
            'aeronaves' => $this->voo->aeronaves(),
            'statusOpcoes' => Voo::STATUS,
        ];
    }

    private function tela(string $nome, array $variaveis): void
    {
        extract($variaveis);
        require __DIR__ . '/../views/includes/header.php';
        require __DIR__ . "/../views/voos/$nome.php";
        require __DIR__ . '/../views/includes/footer.php';
    }

    // Depois de gravar, redireciona (padrao Post/Redirect/Get): recarregar a
    // pagina nao reenvia o formulario.
    private function voltar(string $mensagem, string $tipo = 'ok'): never
    {
        $_SESSION['aviso'] = ['tipo' => $tipo, 'texto' => $mensagem];
        header('Location: index.php');
        exit;
    }
}
