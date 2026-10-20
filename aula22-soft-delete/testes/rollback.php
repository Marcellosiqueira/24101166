<?php
// Desafio extra 2: falha no meio da exclusao.
//
// Uma subclasse do model faz a gravacao da auditoria falhar, depois que o
// UPDATE de deleted_at ja rodou dentro da transacao. O teste confere que o
// rollback desfez o UPDATE: o voo continua ativo e nenhuma linha de auditoria
// foi gravada.
//
// Uso, de dentro da pasta aula22-soft-delete:  php testes/rollback.php <id_voo>
// Use um voo ativo sem passagens (no banco da Aula 10, o voo 8).

require_once __DIR__ . '/../app/models/Voo.php';

class VooComAuditoriaQuebrada extends Voo
{
    protected function auditar(string $acao, int $id, int $usuarioId, array $antes): void
    {
        // Mostra que o UPDATE ja aconteceu dentro da transacao.
        $stmt = $this->db->prepare("SELECT deleted_at FROM voo WHERE id_voo = :id");
        $stmt->execute([':id' => $id]);
        echo "  dentro da transacao, depois do UPDATE: deleted_at = ",
             $stmt->fetchColumn() ?? 'NULL', PHP_EOL;

        // Falha real do banco: usuario_id inexistente viola a chave estrangeira.
        parent::auditar($acao, $id, 999999, $antes);
    }
}

$id = (int) ($argv[1] ?? 0);
$db = Database::conectar();

$estado = function () use ($db, $id): array {
    $voo = $db->prepare("SELECT deleted_at FROM voo WHERE id_voo = :id");
    $voo->execute([':id' => $id]);
    $log = $db->prepare("SELECT COUNT(*) FROM auditoria WHERE tabela = 'voo' AND registro_id = :id");
    $log->execute([':id' => $id]);
    return [$voo->fetchColumn(), (int) $log->fetchColumn()];
};

[$antes, $logsAntes] = $estado();
if ($antes === false || $antes !== null) {
    exit("Informe um voo ativo existente.\n");
}
echo "antes:  deleted_at = NULL, linhas de auditoria = $logsAntes", PHP_EOL;

try {
    (new VooComAuditoriaQuebrada())->excluir($id, 1);
    echo "FALHOU: a exclusao deveria ter dado erro.", PHP_EOL;
    exit(1);
} catch (DomainException $e) {
    echo "  erro devolvido ao controller: ", $e->getMessage(), PHP_EOL;
    echo "  erro do banco: ", $e->getPrevious()?->getMessage(), PHP_EOL;
}

[$depois, $logsDepois] = $estado();
echo "depois: deleted_at = ", $depois ?? 'NULL', ", linhas de auditoria = $logsDepois", PHP_EOL;

$ok = $depois === null && $logsDepois === $logsAntes;
echo $ok ? "OK: rollback desfez o UPDATE." : "FALHOU: o voo ficou excluído sem auditoria.", PHP_EOL;
exit($ok ? 0 : 1);
