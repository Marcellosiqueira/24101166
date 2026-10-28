<div class="cabecalho">
  <h1>Voos excluídos</h1>
</div>

<?php if (!$voos): ?>
  <p class="vazio">Nenhum voo excluído.</p>
<?php else: ?>
<div class="tabela-rolagem">
<table>
  <thead>
    <tr><th>Número</th><th>Rota</th><th>Partida</th><th>Excluído em</th><th>Por</th><th class="acoes">Ações</th></tr>
  </thead>
  <tbody>
  <?php foreach ($voos as $v): ?>
    <tr>
      <td class="mono forte"><?= htmlspecialchars($v['numero_voo']) ?></td>
      <td class="mono"><?= htmlspecialchars($v['origem']) ?> <span class="seta">→</span> <?= htmlspecialchars($v['destino']) ?></td>
      <td><?= htmlspecialchars(date('d/m/Y H:i', strtotime($v['data_hora_partida']))) ?></td>
      <td><?= htmlspecialchars(date('d/m/Y H:i', strtotime($v['deleted_at']))) ?></td>
      <td><?= $v['excluido_por'] !== null ? htmlspecialchars($v['excluido_por']) : '<span class="tracos">-</span>' ?></td>
      <td class="acoes">
        <?php if (ehAdmin()): ?>
        <form class="inline" method="post" action="index.php?acao=restaurar">
          <input type="hidden" name="id_voo" value="<?= (int) $v['id_voo'] ?>">
          <button class="link">Restaurar</button>
        </form>
        <?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
<?php endif; ?>
