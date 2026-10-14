<p><a href="index.php?acao=criar">Novo voo</a></p>
<table>
  <tr><th>Número</th><th>Origem</th><th>Destino</th><th>Aeronave</th><th>Partida</th><th>Portão</th><th>Status</th><th>Ações</th></tr>
  <?php foreach ($voos as $v): ?>
    <tr>
      <td><?= htmlspecialchars($v['numero_voo']) ?></td>
      <td><?= htmlspecialchars($v['origem']) ?></td>
      <td><?= htmlspecialchars($v['destino']) ?></td>
      <td><?= htmlspecialchars($v['prefixo']) ?></td>
      <td><?= htmlspecialchars($v['data_hora_partida']) ?></td>
      <td><?= htmlspecialchars($v['portao'] ?? '') ?></td>
      <td><?= htmlspecialchars($v['status']) ?></td>
      <td>
        <a href="index.php?acao=editar&id=<?= (int) $v['id_voo'] ?>">Editar</a>
        <form class="inline" method="post" action="index.php?acao=excluir" onsubmit="return confirm('Excluir este voo?')">
          <input type="hidden" name="id_voo" value="<?= (int) $v['id_voo'] ?>">
          <button>Excluir</button>
        </form>
      </td>
    </tr>
  <?php endforeach; ?>
</table>
