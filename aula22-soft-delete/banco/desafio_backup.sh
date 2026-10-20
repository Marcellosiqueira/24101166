#!/bin/sh
# Desafio extra 3: backup com mysqldump, DELETE definitivo num banco de teste
# e recuperacao do voo a partir do backup.
# Rodar como root (no Laragon, pelo terminal dele, com mysql e mysqldump no PATH).
# Uso: sh banco/desafio_backup.sh <id_voo sem passagens>   (no banco da Aula 10, 8)
set -e
ID=${1:-8}
BACKUP=backup_aeroporto.sql

# 1. Backup do banco de producao. --single-transaction tira uma foto
#    consistente sem travar as tabelas; --routines e --triggers levam as
#    triggers da Aula 15 junto.
mysqldump --single-transaction --routines --triggers aeroporto > "$BACKUP"

# 2. Banco de teste, criado a partir do backup. Nada daqui toca o aeroporto.
mysql -e "DROP DATABASE IF EXISTS aeroporto_teste; CREATE DATABASE aeroporto_teste"
mysql aeroporto_teste < "$BACKUP"

# 3. Exclusao definitiva no banco de teste.
mysql aeroporto_teste -e "DELETE FROM voo WHERE id_voo = $ID"
echo "Depois do DELETE:"
mysql aeroporto_teste -e "SELECT COUNT(*) AS voo_$ID FROM voo WHERE id_voo = $ID"

# 4. Recuperacao. Restaurar o arquivo inteiro por cima do banco de teste
#    desfaria tambem tudo o que mudou depois do backup. Por isso o backup vai
#    para um banco auxiliar e so a linha apagada volta.
#    ativo e coluna gerada e nao entra na lista de colunas.
mysql -e "DROP DATABASE IF EXISTS aeroporto_backup; CREATE DATABASE aeroporto_backup"
mysql aeroporto_backup < "$BACKUP"
COLUNAS="id_voo, id_rota, id_aeronave, data_hora_partida, data_hora_chegada_prevista,
         portao, status, deleted_at"
mysql aeroporto_teste -e "
    INSERT INTO voo ($COLUNAS)
    SELECT $COLUNAS FROM aeroporto_backup.voo WHERE id_voo = $ID"

echo "Depois da recuperacao:"
mysql aeroporto_teste -e "SELECT id_voo, id_rota, data_hora_partida, status, deleted_at
                            FROM voo WHERE id_voo = $ID"

mysql -e "DROP DATABASE aeroporto_backup"
