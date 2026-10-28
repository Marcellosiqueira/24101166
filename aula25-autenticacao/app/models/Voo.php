<?php
// Model de Voos: todo o SQL da tabela voo fica aqui.
// No esquema normalizado da Aula 09, numero_voo, origem e destino moram na
// tabela rota, e o prefixo na tabela aeronave. Por isso a listagem faz JOIN.
//
// Aula 22: soft delete. Excluir preenche deleted_at; nenhum metodo faz DELETE.

require_once __DIR__ . '/../../config/database.php';

class Voo
{
    public const STATUS = ['Aguardando', 'Confirmado', 'Embarque', 'Cancelado'];

    // Filtro de registros ativos, escrito num lugar so. Toda consulta de voo
    // do model usa o alias v e esta constante; os excluidos so aparecem em
    // listarExcluidos() e restaurar(), que usam EXCLUIDO.
    private const ATIVO    = 'v.deleted_at IS NULL';
    private const EXCLUIDO = 'v.deleted_at IS NOT NULL';

    private const COLUNAS_LISTA = "v.id_voo, r.numero_voo, r.origem, r.destino, a.prefixo,
                                   v.data_hora_partida, v.data_hora_chegada_prevista,
                                   v.portao, v.status";

    protected PDO $db;

    public function __construct()
    {
        $this->db = Database::conectar();
    }

    public function listar(): array
    {
        $sql = "SELECT " . self::COLUNAS_LISTA . "
                  FROM voo v
                  JOIN rota r     ON r.id_rota     = v.id_rota
                  JOIN aeronave a ON a.id_aeronave = v.id_aeronave
                 WHERE " . self::ATIVO . "
                 ORDER BY v.data_hora_partida";
        return $this->db->query($sql)->fetchAll();
    }

    // Aula 23: busca por destino com as 5 colunas do enunciado. O comando vai
    // para o banco sem o texto, e o texto vai depois como valor de :destino.
    // A versao vulneravel (buscarVulneravel) foi removida depois dos testes.
    public function buscarSeguro(string $destino): array
    {
        $stmt = $this->db->prepare(
            "SELECT v.id_voo AS id, r.numero_voo, r.origem, r.destino, v.status
               FROM voo v
               JOIN rota r ON r.id_rota = v.id_rota
              WHERE " . self::ATIVO . " AND r.destino = :destino"
        );
        $stmt->execute([':destino' => $destino]);
        return $stmt->fetchAll();
    }

    // Excluidos, com quem excluiu, lido da ultima linha de auditoria do voo.
    public function listarExcluidos(): array
    {
        $sql = "SELECT " . self::COLUNAS_LISTA . ", v.deleted_at, u.nome AS excluido_por
                  FROM voo v
                  JOIN rota r     ON r.id_rota     = v.id_rota
                  JOIN aeronave a ON a.id_aeronave = v.id_aeronave
                  LEFT JOIN auditoria au ON au.id = (
                        SELECT MAX(x.id) FROM auditoria x
                         WHERE x.tabela = 'voo' AND x.acao = 'excluir'
                           AND x.registro_id = v.id_voo)
                  LEFT JOIN usuario u ON u.id_usuario = au.usuario_id
                 WHERE " . self::EXCLUIDO . "
                 ORDER BY v.deleted_at DESC";
        return $this->db->query($sql)->fetchAll();
    }

    public function buscar(int $id): ?array
    {
        $stmt = $this->db->prepare(
            "SELECT v.id_voo, v.id_rota, v.id_aeronave, v.data_hora_partida,
                    v.data_hora_chegada_prevista, v.portao, v.status,
                    r.numero_voo, r.origem, r.destino
               FROM voo v
               JOIN rota r ON r.id_rota = v.id_rota
              WHERE v.id_voo = :id AND " . self::ATIVO
        );
        $stmt->execute([':id' => $id]);
        return $stmt->fetch() ?: null;
    }

    // Aula 25: validacao no servidor antes de gravar. Devolve a lista de
    // erros; vazia significa que pode salvar. A partida no futuro so e exigida
    // no cadastro: um voo que ja partiu ainda precisa ter o status atualizado.
    public function validar(array $d, bool $novo): array
    {
        $erros   = [];
        $codigo  = strtoupper(trim($d['numero_voo'] ?? ''));
        $origem  = strtoupper(trim($d['origem'] ?? ''));
        $destino = strtoupper(trim($d['destino'] ?? ''));

        if (!preg_match('/^[A-Z]{2}[0-9]{3,4}$/', $codigo)) {
            $erros[] = 'Código do voo inválido: use duas letras e 3 ou 4 números (ex.: LA1234).';
        }
        if (!preg_match('/^[A-Z]{3}$/', $origem) || !preg_match('/^[A-Z]{3}$/', $destino)) {
            $erros[] = 'Origem e destino devem ser códigos de aeroporto com 3 letras (ex.: BSB).';
        } elseif ($origem === $destino) {
            $erros[] = 'A origem precisa ser diferente do destino.';
        }

        $partida = DateTime::createFromFormat('Y-m-d\\TH:i', $d['data_hora_partida'] ?? '');
        if ($partida === false) {
            $erros[] = 'Informe a data e a hora de partida.';
        } elseif ($novo && $partida <= new DateTime()) {
            $erros[] = 'A data de partida precisa estar no futuro.';
        }

        if ((int) ($d['id_aeronave'] ?? 0) <= 0) {
            $erros[] = 'Escolha a aeronave.';
        }
        return $erros;
    }

    public function criar(array $dados): void
    {
        $this->transacao(function () use ($dados) {
            $this->db->prepare(
                "INSERT INTO voo (id_rota, id_aeronave, data_hora_partida,
                                  data_hora_chegada_prevista, portao, status)
                 VALUES (:id_rota, :id_aeronave, :partida, :chegada, :portao, :status)"
            )->execute($this->parametros($dados));
        }, 'Não foi possível salvar o voo.');
    }

    public function editar(int $id, array $dados): void
    {
        if ($this->buscar($id) === null) {
            throw new DomainException('Voo não encontrado.');
        }
        $this->transacao(fn() => $this->db->prepare(
            "UPDATE voo v
                SET v.id_rota = :id_rota,
                    v.id_aeronave = :id_aeronave,
                    v.data_hora_partida = :partida,
                    v.data_hora_chegada_prevista = :chegada,
                    v.portao = :portao,
                    v.status = :status
              WHERE v.id_voo = :id AND " . self::ATIVO
        )->execute($this->parametros($dados) + [':id' => $id]), 'Não foi possível salvar o voo.');
    }

    // Soft delete. O UPDATE e a linha de auditoria vao na mesma transacao:
    // se a auditoria falhar, o voo continua ativo.
    public function excluir(int $id, int $usuarioId): void
    {
        $this->transacao(function () use ($id, $usuarioId) {
            // FOR UPDATE trava a linha ate o commit. Enquanto ela estiver
            // travada, nenhuma passagem nova entra para este voo, porque a
            // chave estrangeira de passagem precisa ler a linha do voo.
            $voo = $this->travar($id, self::ATIVO);
            if ($voo === null) {
                throw new DomainException('Voo não encontrado ou já excluído.');
            }

            $passagens = $this->passagens($id);
            if ($passagens > 0) {
                throw new DomainException(
                    "Este voo tem $passagens passagem(ns) vendida(s) e não pode ser excluído. "
                    . 'Para tirá-lo de operação, altere o status para Cancelado.'
                );
            }

            $this->db->prepare("UPDATE voo SET deleted_at = NOW() WHERE id_voo = :id")
                     ->execute([':id' => $id]);

            $this->auditar('excluir', $id, $usuarioId, $voo);
        });
    }

    public function restaurar(int $id, int $usuarioId): void
    {
        $this->transacao(function () use ($id, $usuarioId) {
            $voo = $this->travar($id, self::EXCLUIDO);
            if ($voo === null) {
                throw new DomainException('Voo não encontrado entre os excluídos.');
            }

            // Se um voo ativo com a mesma rota e partida foi cadastrado depois
            // da exclusao, o indice unico recusa com 1062.
            $this->db->prepare("UPDATE voo SET deleted_at = NULL WHERE id_voo = :id")
                     ->execute([':id' => $id]);

            $this->auditar('restaurar', $id, $usuarioId, $voo);
        });
    }

    // Opcoes dos campos de selecao do formulario de voo.
    // Aula 25: o formulario recebe codigo, origem e destino digitados. Se o
    // codigo ja existe, usa a rota dele; se nao, cria. Um codigo e sempre a
    // mesma rota (premissa da normalizacao da Aula 09), entao o mesmo codigo
    // com outra origem ou destino e recusado.
    // Sem FOR UPDATE: no MySQL 8 ele exige UPDATE na tabela, e a aplicacao nao
    // altera rota. Se duas pessoas criarem o mesmo codigo ao mesmo tempo, a
    // segunda esbarra em uq_rota_numero_voo (1062) e recebe uma mensagem.
    private function resolverRota(string $codigo, string $origem, string $destino): int
    {
        $stmt = $this->db->prepare(
            "SELECT id_rota, origem, destino FROM rota WHERE numero_voo = :codigo"
        );
        $stmt->execute([':codigo' => $codigo]);
        $rota = $stmt->fetch();

        if ($rota === false) {
            $this->db->prepare(
                "INSERT INTO rota (numero_voo, origem, destino) VALUES (:codigo, :origem, :destino)"
            )->execute([':codigo' => $codigo, ':origem' => $origem, ':destino' => $destino]);
            return (int) $this->db->lastInsertId();
        }
        if ($rota['origem'] !== $origem || $rota['destino'] !== $destino) {
            throw new DomainException(
                "O voo $codigo já está cadastrado como {$rota['origem']} → {$rota['destino']}."
            );
        }
        return (int) $rota['id_rota'];
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

    // Grava a linha de auditoria com o estado do voo antes da operacao.
    // Protegido para o teste de rollback (testes/rollback.php) poder simular
    // uma falha aqui.
    protected function auditar(string $acao, int $id, int $usuarioId, array $antes): void
    {
        unset($antes['ativo']); // coluna gerada, derivada de deleted_at
        $this->db->prepare(
            "INSERT INTO auditoria (tabela, registro_id, acao, usuario_id, dados_antes)
             VALUES ('voo', :id, :acao, :usuario, :antes)"
        )->execute([
            ':id'      => $id,
            ':acao'    => $acao,
            ':usuario' => $usuarioId,
            ':antes'   => json_encode($antes, JSON_UNESCAPED_UNICODE),
        ]);
    }

    private function travar(int $id, string $filtro): ?array
    {
        $stmt = $this->db->prepare(
            "SELECT v.* FROM voo v WHERE v.id_voo = :id AND $filtro FOR UPDATE"
        );
        $stmt->execute([':id' => $id]);
        return $stmt->fetch() ?: null;
    }

    private function passagens(int $id): int
    {
        $stmt = $this->db->prepare("SELECT COUNT(*) FROM passagem WHERE id_voo = :id");
        $stmt->execute([':id' => $id]);
        return (int) $stmt->fetchColumn();
    }

    // Tudo ou nada: qualquer excecao dentro de $passos desfaz a transacao.
    private function transacao(callable $passos,
                                string $padrao = 'Não foi possível concluir a operação. Nada foi alterado.'): void
    {
        $this->db->beginTransaction();
        try {
            $passos();
            $this->db->commit();
        } catch (Throwable $e) {
            $this->db->rollBack();
            if ($e instanceof PDOException) {
                throw new DomainException($this->traduzir($e, $padrao), 0, $e);
            }
            throw $e;
        }
    }

    // Converte o que vem do formulario para o formato das colunas:
    // datetime-local usa "T" entre data e hora, e campo vazio vira NULL.
    private function parametros(array $d): array
    {
        $data = fn($v) => ($v ?? '') === '' ? null : str_replace('T', ' ', $v);
        $texto = fn($v) => ($v = trim($v ?? '')) === '' ? null : $v;

        return [
            ':id_rota'     => $this->resolverRota(
                strtoupper(trim($d['numero_voo'] ?? '')),
                strtoupper(trim($d['origem'] ?? '')),
                strtoupper(trim($d['destino'] ?? ''))
            ),
            ':id_aeronave' => (int) ($d['id_aeronave'] ?? 0),
            ':partida'     => $data($d['data_hora_partida'] ?? null),
            ':chegada'     => $data($d['data_hora_chegada_prevista'] ?? null),
            ':portao'      => $texto($d['portao'] ?? null),
            ':status'      => $texto($d['status'] ?? null) ?? 'Aguardando',
        ];
    }

    // As regras do voo ja estao no banco como constraint (Aula 10) e trigger
    // (Aula 15). O model traduz a recusa do banco numa mensagem para o usuario.
    private function traduzir(PDOException $e, string $padrao): string
    {
        $codigo = (int) ($e->errorInfo[1] ?? 0);
        $texto  = $e->errorInfo[2] ?? '';

        switch ($codigo) {
            case 1062:
                if (str_contains($texto, 'uq_rota_numero_voo')) {
                    return 'Este código de voo acabou de ser cadastrado por outra pessoa. Tente de novo.';
                }
                return 'Já existe um voo ativo desta rota com a mesma data e hora de partida.';
            case 1048: return 'Preencha a rota, a aeronave e a data de partida.';
            case 1452:
                if (str_contains($texto, 'fk_voo_')) {
                    return 'A rota ou a aeronave escolhida não existe.';
                }
                break;
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
        // Aula 25: erro tecnico vai so para o log; a tela recebe a mensagem generica.
        error_log($e->getMessage());
        return $padrao;
    }
}
