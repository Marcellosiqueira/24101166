<div class="cabecalho">
  <h1>Excluir voo</h1>
</div>
<p class="nota">Confirma a exclusão deste voo? Ele sai da lista de voos, mas continua no banco e pode ser restaurado em Voos excluídos.</p>
<dl class="ficha">
  <dt>Número</dt><dd class="mono"><?= htmlspecialchars($voo['numero_voo']) ?></dd>
  <dt>Rota</dt><dd class="mono"><?= htmlspecialchars($voo['origem']) ?> → <?= htmlspecialchars($voo['destino']) ?></dd>
  <dt>Partida</dt><dd><?= htmlspecialchars(date('d/m/Y H:i', strtotime($voo['data_hora_partida']))) ?></dd>
  <dt>Status</dt><dd><?= htmlspecialchars($voo['status']) ?></dd>
</dl>
<form method="post" action="index.php?acao=excluir">
  <input type="hidden" name="id_voo" value="<?= (int) $voo['id_voo'] ?>">
  <div class="botoes">
    <button class="btn perigo">Confirmar exclusão</button>
    <a href="index.php">Cancelar</a>
  </div>
</form>
