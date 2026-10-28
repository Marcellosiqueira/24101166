<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aeroporto - Voos</title>
<link rel="stylesheet" href="css/style.css">
</head>
<body>
<header class="topo">
  <a class="marca" href="index.php">Aeroporto</a>
  <?php if (!empty($_SESSION['usuario'])): ?>
    <nav>
      <a href="index.php">Voos</a>
      <a href="index.php?acao=buscar">Buscar</a>
      <a href="index.php?acao=excluidos">Voos excluídos</a>
    </nav>
    <span class="operador">
      <?= htmlspecialchars($_SESSION['usuario']['nome']) ?>
      <form class="inline" method="post" action="index.php?acao=sair">
        <button class="link">Sair</button>
      </form>
    </span>
  <?php endif; ?>
</header>
<main class="conteudo">
<?php if (!empty($_SESSION['aviso'])): ?>
  <p class="aviso <?= htmlspecialchars($_SESSION['aviso']['tipo']) ?>"><?= htmlspecialchars($_SESSION['aviso']['texto']) ?></p>
  <?php unset($_SESSION['aviso']); ?>
<?php endif; ?>
<?php if (!empty($erro)): ?>
  <p class="aviso erro"><?= htmlspecialchars($erro) ?></p>
<?php endif; ?>
