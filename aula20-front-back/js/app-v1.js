// Versao inicial: a regra de aprovacao esta aqui, no navegador.
carregar('api/alunos-v1.php', aluno => aluno.nota >= 7 ? 'Aprovado' : 'Reprovado');
