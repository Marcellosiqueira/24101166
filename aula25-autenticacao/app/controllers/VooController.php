<?php
// Recebe a requisicao, chama o model e escolhe a view. Nao tem SQL.

require_once __DIR__ . '/../models/Voo.php';
require_once __DIR__ . '/../auth.php';

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

    public function buscar(): void
    {
        $destino = $_GET['destino'] ?? '';
        $voos = $this->voo->buscarSeguro($destino);
        $this->tela('buscar', ['voos' => $voos, 'destino' => $destino]);
    }

    public function excluidos(): void
    {
        $voos = $this->voo->listarExcluidos();
        $this->tela('excluidos', ['voos' => $voos]);
    }

    public function criar(): void
    {
        $this->tela('criar', $this->opcoes() + ['dados' => ['status' => 'Aguardando']]);
    }

    public function salvar(): void
    {
        $erros = $this->voo->validar($_POST, true);
        if (!$erros) {
            try {
                $this->voo->criar($_POST);
                $this->voltar('Voo cadastrado.');
            } catch (DomainException $e) {
                $erros[] = $e->getMessage();
            }
        }
        $this->tela('criar', $this->opcoes() + ['dados' => $_POST, 'erros' => $erros]);
    }

    public function editar(): void
    {
        $voo = $this->voo->buscar((int) ($_GET['id'] ?? 0));
        if ($voo === null) {
            $this->voltar('Voo não encontrado.', 'erro');
        }
        $this->tela('editar', $this->opcoes() + ['dados' => $voo]);
    }

    public function atualizar(): void
    {
        $id = (int) ($_POST['id_voo'] ?? 0);
        $erros = $this->voo->validar($_POST, false);
        if (!$erros) {
            try {
                $this->voo->editar($id, $_POST);
                $this->voltar('Voo atualizado.');
            } catch (DomainException $e) {
                $erros[] = $e->getMessage();
            }
        }
        $this->tela('editar', $this->opcoes() + ['dados' => $_POST, 'erros' => $erros]);
    }

    // Primeiro passo da exclusao: tela de confirmacao com os dados do voo.
    // So exibe; quem altera e excluir(), que exige POST.
    public function confirmarExclusao(): void
    {
        exigirAdmin();
        $voo = $this->voo->buscar((int) ($_GET['id'] ?? 0));
        if ($voo === null) {
            $this->voltar('Voo não encontrado ou já excluído.', 'erro');
        }
        $this->tela('excluir', ['voo' => $voo]);
    }

    public function excluir(): void
    {
        exigirAdmin();
        try {
            $this->voo->excluir((int) ($_POST['id_voo'] ?? 0), $this->usuarioId());
        } catch (DomainException $e) {
            $this->voltar($e->getMessage(), 'erro');
        }
        $this->voltar('Voo excluído. Ele pode ser restaurado em Voos excluídos.');
    }

    public function restaurar(): void
    {
        exigirAdmin();
        try {
            $this->voo->restaurar((int) ($_POST['id_voo'] ?? 0), $this->usuarioId());
        } catch (DomainException $e) {
            $this->voltar($e->getMessage(), 'erro', 'excluidos');
        }
        $this->voltar('Voo restaurado. Ele voltou para a lista de voos.', 'ok', 'excluidos');
    }

    private function usuarioId(): int
    {
        return (int) $_SESSION['usuario_id'];
    }

    private function opcoes(): array
    {
        return [
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
    private function voltar(string $mensagem, string $tipo = 'ok', string $acao = 'listar'): never
    {
        $_SESSION['aviso'] = ['tipo' => $tipo, 'texto' => $mensagem];
        header('Location: index.php' . ($acao === 'listar' ? '' : "?acao=$acao"));
        exit;
    }
}
