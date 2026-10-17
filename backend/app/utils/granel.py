"""
PRODUCTOS A GRANEL (se venden por kilo)

Dos formas de agregarlos:

A) ETIQUETA DE BÁSCULA (la principal, como en un súper real):
   el cliente pesa en la báscula de la tienda, que imprime un código
   EAN-13 de "peso variable" con este formato:

        21  PPPPP  WWWWW  C
        |     |      |    └─ dígito verificador
        |     |      └────── peso en gramos (01250 = 1.250 kg)
        |     └───────────── PLU del producto (columna productos.plu)
        └─────────────────── prefijo 21 = artículo de peso variable

   Ejemplo: 2140001012508 -> PLU 40001 (Manzana roja), 1.250 kg

B) PESO ESCRITO A MANO (respaldo): el cliente escanea la etiqueta del
   anaquel (GR-40001) y escribe el peso que marcó la báscula.

El importe SIEMPRE lo calcula el servidor con estas funciones.
"""
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

PREFIJO_BASCULA = "21"
PESO_MINIMO = Decimal("0.010")   # 10 g
PESO_MAXIMO = Decimal("25.000")  # 25 kg (capacidad de la báscula)


def digito_verificador_ean13(primeros_12):
    """Calcula el dígito 13 de un EAN-13 a partir de los primeros 12."""
    total = sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(primeros_12))
    return str((10 - total % 10) % 10)


def es_codigo_bascula(codigo):
    """True si el código tiene la forma de una etiqueta de báscula."""
    return len(codigo) == 13 and codigo.isdigit() and codigo.startswith(PREFIJO_BASCULA)


def validar_peso(peso):
    """Lanza ValueError si el peso está fuera del rango permitido."""
    if peso < PESO_MINIMO:
        raise ValueError("El peso mínimo es de 10 g")
    if peso > PESO_MAXIMO:
        raise ValueError("El peso máximo es de 25 kg")
    return peso


def leer_codigo_bascula(codigo):
    """Devuelve (plu, peso_kg) o lanza ValueError con el motivo."""
    if not es_codigo_bascula(codigo):
        raise ValueError("No es una etiqueta de báscula")
    if digito_verificador_ean13(codigo[:12]) != codigo[12]:
        raise ValueError("La etiqueta de báscula no es válida")
    plu = codigo[2:7]
    gramos = int(codigo[7:12])
    peso = (Decimal(gramos) / Decimal(1000)).quantize(Decimal("0.001"))
    return plu, validar_peso(peso)


def normalizar_peso(valor, unidad="kg"):
    """Convierte lo que escribió el cliente a kg con 3 decimales."""
    try:
        peso = Decimal(str(valor).replace(",", "."))
    except InvalidOperation:
        raise ValueError("Escribe un peso válido")
    if not peso.is_finite():
        raise ValueError("Escribe un peso válido")
    if unidad == "g":
        peso = peso / Decimal(1000)
    elif unidad != "kg":
        raise ValueError("La unidad debe ser kg o g")
    peso = peso.quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
    return validar_peso(peso)


def calcular_importe(precio_por_kg, peso_kg):
    """precio por kg x kilos, redondeado a centavos."""
    return (Decimal(str(precio_por_kg)) * Decimal(str(peso_kg))).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP)