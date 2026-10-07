<?php
// Versao inicial: o PHP so entrega os dados. O status e calculado no JavaScript.
require __DIR__ . '/conexao.php';

responder(function (PDO $pdo): array {
    $alunos = $pdo->query('SELECT id, nome, nota FROM alunos ORDER BY nome')->fetchAll();

    // O PDO devolve DECIMAL como texto ("8.50"). Converte para numero para o
    // JSON sair como 8.5 e o JavaScript comparar numero com numero.
    foreach ($alunos as &$aluno) {
        $aluno['id']   = (int) $aluno['id'];
        $aluno['nota'] = (float) $aluno['nota'];
    }
    return $alunos;
});
