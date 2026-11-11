<div class="cabecalho">
  <h1>Entrar</h1>
</div>
<form class="formulario" method="post" action="index.php?acao=autenticar">
  <div class="campos">
    <label class="largo">E-mail
      <input type="email" name="email" required autocomplete="username" value="<?= htmlspecialchars($email ?? '') ?>">
    </label>
    <label class="largo">Senha
      <input type="password" name="senha" required autocomplete="current-password">
    </label>
  </div>
  <div class="botoes">
    <button class="btn">Entrar</button>
  </div>
</form>
