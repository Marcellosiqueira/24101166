"""Executa os tres desafios sem interacao, para conferir a saida de uma vez.

Uso: python3 demo.py
"""

from sgbd import (
    full_table_scan,
    buscar_por_id,
    consultar,
    comparar_scan_vs_indice,
)


def titulo(texto):
    print("\n" + "=" * 58)
    print(texto)
    print("=" * 58)


titulo("DESAFIO 1 - Full Table Scan")
full_table_scan()

titulo("DESAFIO 2 - Busca por chave primaria (ID existente)")
buscar_por_id(17)

titulo("DESAFIO 2 - Busca por chave primaria (ID inexistente)")
buscar_por_id(99)

titulo("DESAFIO 3 - Voos para Brasilia, so numero e portao")
consultar(["NUMERO_VOO", "PORTAO"], "DESTINO", "=", "Brasilia")

titulo("DESAFIO 3 - Voos em embarque, so numero, portao e horario")
consultar(["NUMERO_VOO", "PORTAO", "HORARIO"], "STATUS", "=", "Embarque")

titulo("DESAFIO 3 - Voos a partir das 18:00, filtro em campo de texto ordenavel")
consultar(["NUMERO_VOO", "DESTINO", "HORARIO"], "HORARIO", ">=", "18:00")

titulo("DESAFIO 3 - Voos com numero acima de 700, filtro numerico")
consultar(["NUMERO_VOO", "DESTINO", "STATUS"], "NUMERO_VOO", ">", "700")

titulo("EXTRA - Scan sequencial x indice hash")
comparar_scan_vs_indice()
