"""
PROGRAMA DE LEALTAD MARK'S (PASO 11)

  Ganar:    1 punto por cada $10 pagados con tarjeta (se redondea hacia abajo).
            Lo que se gasta en productos LOCALES de Nuevo León cuenta doble.
  Canjear:  100 puntos = $10 de descuento, en bloques de 100.
            Los puntos cubren como máximo el 50% de la compra.
  No se ganan puntos con puntos: si se usa descuento, los puntos se
  calculan solo sobre lo que se pagó con tarjeta.

  Ejemplo: Leche $28.50 + Pan $39.00 + Café local $89.00 = $156.50
           base = 156.50 + 89.00 (el café cuenta otra vez) = 245.50 -> 24 puntos

  Para cambiar las reglas, solo se cambian estas constantes.
"""
from decimal import ROUND_DOWN, Decimal

PESOS_POR_PUNTO = Decimal("10")       # 1 punto por cada $10
MULTIPLICADOR_LOCAL = 2               # productos locales cuentan doble
PUNTOS_POR_BLOQUE = 100               # se canjean de 100 en 100...
VALOR_BLOQUE = Decimal("10.00")       # ...y cada bloque vale $10
MAX_PORCENTAJE_CANJE = Decimal("0.50")  # hasta 50% de la compra
CENTAVO = Decimal("0.01")


def importe_local(carrito):
    """Suma de lo que se paga por productos locales (líneas sin error)."""
    return sum((Decimal(str(l["importe"])) for l in carrito["lineas"]
                if "error" not in l and l.get("es_local")), Decimal("0.00"))


def puntos_canjeables(saldo, total):
    """Cuántos puntos se pueden usar en esta compra y cuánto descuentan."""
    total = Decimal(str(total))
    maximo = (total * MAX_PORCENTAJE_CANJE).quantize(CENTAVO, rounding=ROUND_DOWN)
    bloques = min(int(saldo) // PUNTOS_POR_BLOQUE, int(maximo // VALOR_BLOQUE))
    bloques = max(bloques, 0)
    return bloques * PUNTOS_POR_BLOQUE, (VALOR_BLOQUE * bloques).quantize(CENTAVO)


def puntos_a_ganar(total, local, cobrado):
    """Puntos que gana una compra.
       total:   total de los productos (ya con ofertas)
       local:   parte del total que es de productos locales
       cobrado: lo que se pagó con tarjeta (total - descuento por puntos)"""
    total, local, cobrado = (Decimal(str(x)) for x in (total, local, cobrado))
    if total <= 0 or cobrado <= 0:
        return 0
    extra_local = local * (MULTIPLICADOR_LOCAL - 1) * cobrado / total
    return int((cobrado + extra_local) // PESOS_POR_PUNTO)


def resumen_puntos(carrito, saldo):
    """Lo que la app necesita para mostrar el interruptor "Usar mis puntos"."""
    total = carrito["total"]
    local = importe_local(carrito)
    usables, descuento = puntos_canjeables(saldo, total)
    return {
        "saldo": int(saldo),
        "puntos_por_bloque": PUNTOS_POR_BLOQUE,
        "valor_bloque": VALOR_BLOQUE,
        "puntos_usables": usables,                       # 0 si no le alcanza
        "descuento": descuento,                          # $ que descuentan esos puntos
        "total_con_puntos": (Decimal(str(total)) - descuento).quantize(CENTAVO),
        "ganarias": puntos_a_ganar(total, local, total),
        "ganarias_con_puntos": puntos_a_ganar(total, local, Decimal(str(total)) - descuento),
    }