<h2>Editar voo</h2>
<form method="post" action="index.php?acao=atualizar">
  <input type="hidden" name="id_voo" value="<?= (int) $dados['id_voo'] ?>">
  <?php require __DIR__ . '/_form.php'; ?>
</form>
