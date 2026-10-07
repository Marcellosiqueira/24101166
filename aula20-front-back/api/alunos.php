<?php
// Versao final: a regra de aprovacao mora no backend. O JavaScript so exibe.
require __DIR__ . '/conexao.php';

const NOTA_MINIMA_APROVACAO = 7.0;

function status_do_aluno(float $nota): string
{
    return $nota >= NOTA_MINIMA_APROVACAO ? 'Aprovado' : 'Reprovado';
}

responder(function (PDO $pdo): array {
    $alunos = $pdo->query('SELECT id, nome, nota FROM alunos ORDER BY nome')->fetchAll();

    foreach ($alunos as &$aluno) {
        $aluno['id']     = (int) $aluno['id'];
        $aluno['nota']   = (float) $aluno['nota'];
        $aluno['status'] = status_do_aluno($aluno['nota']);
    }
    return $alunos;
});
