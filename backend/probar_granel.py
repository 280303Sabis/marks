"""
Pruebas de la lógica de granel (no necesita la API ni la base de datos).
Ejecutar desde la carpeta backend:   python probar_granel.py
"""
from decimal import Decimal

from app.utils.granel import (calcular_importe, es_codigo_bascula,
                              leer_codigo_bascula, normalizar_peso)

aprobadas = 0
fallidas = 0


def revisar(nombre, obtenido, esperado):
    global aprobadas, fallidas
    if obtenido == esperado:
        aprobadas += 1
        print(f"[OK]    {nombre}  ->  {obtenido}")
    else:
        fallidas += 1
        print(f"[FALLA] {nombre}  ->  obtuve {obtenido}, esperaba {esperado}")


def error_de(funcion, *args):
    """Ejecuta la función y regresa el mensaje del ValueError (o None si no hubo)."""
    try:
        funcion(*args)
        return None
    except ValueError as e:
        return str(e)


print("\n--- ETIQUETAS DE BÁSCULA ---")
revisar("Manzana 1.250 kg", leer_codigo_bascula("2140001012508"), ("40001", Decimal("1.250")))
revisar("Plátano 0.850 kg", leer_codigo_bascula("2140002008500"), ("40002", Decimal("0.850")))
revisar("Carne 0.500 kg", leer_codigo_bascula("2120001005007"), ("20001", Decimal("0.500")))
revisar("Código normal no es de báscula", es_codigo_bascula("7501000000012"), False)
revisar("Dígito verificador alterado", error_de(leer_codigo_bascula, "2140001012509"),
        "La etiqueta de báscula no es válida")
revisar("Etiqueta con peso 0", error_de(leer_codigo_bascula, "2140001000000"),
        "El peso mínimo es de 10 g")

print("\n--- PESO ESCRITO A MANO ---")
revisar("1.5 kg", normalizar_peso("1.5", "kg"), Decimal("1.500"))
revisar("Coma decimal 0,75 kg", normalizar_peso("0,75", "kg"), Decimal("0.750"))
revisar("850 g", normalizar_peso("850", "g"), Decimal("0.850"))
revisar("Menos de 10 g", error_de(normalizar_peso, "5", "g"), "El peso mínimo es de 10 g")
revisar("Más de 25 kg", error_de(normalizar_peso, "30", "kg"), "El peso máximo es de 25 kg")
revisar("Valor infinito", error_de(normalizar_peso, "inf", "kg"), "Escribe un peso válido")
revisar("Texto en lugar de número", error_de(normalizar_peso, "abc", "kg"), "Escribe un peso válido")

print("\n--- IMPORTE ---")
revisar("Manzana 1.250 kg x $54.90", calcular_importe("54.90", "1.250"), Decimal("68.63"))
revisar("Plátano 0.850 kg x $24.50", calcular_importe("24.50", "0.850"), Decimal("20.83"))
revisar("Carne 0.500 kg x $189.00", calcular_importe("189.00", "0.500"), Decimal("94.50"))

print(f"\n{aprobadas} pruebas pasaron, {fallidas} fallaron\n")