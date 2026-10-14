<?php
// Model de Voos: todo o SQL da tabela voo fica aqui.
// No esquema normalizado da Aula 09, numero_voo, origem e destino moram na
// tabela rota, e o prefixo na tabela aeronave. Por isso a listagem faz JOIN.

require_once __DIR__ . '/../../config/database.php';

class Voo
{
    public const STATUS = ['Aguardando', 'Confirmado', 'Embarque', 'Cancelado'];

    private PDO $db;

    public function __construct()
    {
        $this->db = Database::conectar();
    }

    public function listar(): array
    {
        $sql = "SELECT v.id_voo, r.numero_voo, r.origem, r.destino, a.prefixo,
                       v.data_hora_partida, v.data_hora_chegada_prevista,
                       v.portao, v.status
                  FROM voo v
                  JOIN rota r     ON r.id_rota     = v.id_rota
                  JOIN aeronave a ON a.id_aeronave = v.id_aeronave
                 ORDER BY v.data_hora_partida";
        return $this->db->query($sql)->fetchAll();
    }

    public function buscar(int $id): ?array
    {
        $stmt = $this->db->prepare(
            "SELECT id_voo, id_rota, id_aeronave, data_hora_partida,
                    data_hora_chegada_prevista, portao, status
               FROM voo WHERE id_voo = :id"
        );
        $stmt->execute([':id' => $id]);
        return $stmt->fetch() ?: null;
    }

    public function criar(array $dados): void
    {
        $this->executar(
            "INSERT INTO voo (id_rota, id_aeronave, data_hora_partida,
                              data_hora_chegada_prevista, portao, status)
             VALUES (:id_rota, :id_aeronave, :partida, :chegada, :portao, :status)",
            $this->parametros($dados)
        );
    }

    public function editar(int $id, array $dados): void
    {
        $this->executar(
            "UPDATE voo
                SET id_rota = :id_rota,
                    id_aeronave = :id_aeronave,
                    data_hora_partida = :partida,
                    data_hora_chegada_prevista = :chegada,
                    portao = :portao,
                    status = :status
              WHERE id_voo = :id",
            $this->parametros($dados) + [':id' => $id]
        );
    }

    public function excluir(int $id): void
    {
        $this->executar("DELETE FROM voo WHERE id_voo = :id", [':id' => $id]);
    }

    // Opcoes dos campos de selecao do formulario de voo.
    public function rotas(): array
    {
        return $this->db->query(
            "SELECT id_rota, numero_voo, origem, destino FROM rota ORDER BY numero_voo"
        )->fetchAll();
    }

    public function aeronaves(): array
    {
        return $this->db->query(
            "SELECT a.id_aeronave, a.prefixo, m.modelo, a.capacidade_assentos
               FROM aeronave a
               JOIN modelo_aeronave m ON m.id_modelo = a.id_modelo
              ORDER BY a.prefixo"
        )->fetchAll();
    }

    // Converte o que vem do formulario para o formato das colunas:
    // datetime-local usa "T" entre data e hora, e campo vazio vira NULL.
    private function parametros(array $d): array
    {
        $data = fn($v) => ($v ?? '') === '' ? null : str_replace('T', ' ', $v);
        $texto = fn($v) => ($v = trim($v ?? '')) === '' ? null : $v;

        return [
            ':id_rota'     => (int) ($d['id_rota'] ?? 0),
            ':id_aeronave' => (int) ($d['id_aeronave'] ?? 0),
            ':partida'     => $data($d['data_hora_partida'] ?? null),
            ':chegada'     => $data($d['data_hora_chegada_prevista'] ?? null),
            ':portao'      => $texto($d['portao'] ?? null),
            ':status'      => $texto($d['status'] ?? null) ?? 'Aguardando',
        ];
    }

    // As regras do voo ja estao no banco como constraint (Aula 10) e trigger
    // (Aula 15). O model nao repete as regras: executa e traduz a recusa do
    // banco numa mensagem para o usuario.
    private function executar(string $sql, array $parametros): void
    {
        try {
            $this->db->prepare($sql)->execute($parametros);
        } catch (PDOException $e) {
            throw new DomainException($this->traduzir($e), 0, $e);
        }
    }

    private function traduzir(PDOException $e): string
    {
        $codigo = (int) ($e->errorInfo[1] ?? 0);
        $texto  = $e->errorInfo[2] ?? '';

        switch ($codigo) {
            case 1062: return 'Já existe um voo desta rota com a mesma data e hora de partida.';
            case 1048: return 'Preencha a rota, a aeronave e a data de partida.';
            case 1452: return 'A rota ou a aeronave escolhida não existe.';
            case 1451: return 'Este voo tem passagens vendidas e não pode ser excluído. '
                            . 'Para tirá-lo de operação, altere o status para Cancelado.';
            case 1644: return $texto; // mensagem de negocio escrita nas triggers
            case 3819: // CHECK no MySQL
            case 4025: // CHECK no MariaDB
                if (str_contains($texto, 'chegada')) {
                    return 'A chegada prevista precisa ser depois da partida.';
                }
                if (str_contains($texto, 'status')) {
                    return 'Status inválido.';
                }
        }
        error_log($e->getMessage());
        return 'Não foi possível salvar o voo.';
    }
}
