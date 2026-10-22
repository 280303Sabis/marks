"""
CARRITO (lado del cliente)

  Requiere sesión iniciada:
    POST /api/carrito/cotizar      calcula el carrito con precios y existencias actuales

  El carrito vive en el celular, pero el TOTAL siempre lo calcula la API:
  así, si un producto caducó, se agotó o cambió de precio mientras el
  cliente compraba, se marca antes de pagar.

  El cálculo está en calcular_carrito() para que el PAGO (compras.py)
  use exactamente la misma regla que la cotización.

  Cuerpo que envía la app:
    {
      "sucursal_id": 1,
      "lineas": [
        {"codigo": "7501000000012", "cantidad": 2},       <- por pieza
        {"codigo": "2140001012508"},                      <- etiqueta de báscula (el peso viene en el código)
        {"codigo": "GR-40001", "peso_kg": 0.85}           <- granel con peso escrito
      ]
    }

  Respuesta:
    lineas[]   cada línea con su importe, o con "error" si no se puede vender
    subtotal   suma a precio normal (sin ofertas)
    ahorro     lo que se ahorra por ofertas
    total      lo que se paga (solo líneas sin error)
    articulos  piezas + bolsas de granel (cada bolsa cuenta 1)
    se_puede_pagar   true si hay productos y ninguna línea tiene error
"""
import re
from decimal import Decimal

from flask import Blueprint, g, jsonify, request

from ..db import query
from ..utils.granel import (calcular_importe, es_codigo_bascula,
                            leer_codigo_bascula, normalizar_peso)
from ..utils.puntos import resumen_puntos
from ..utils.seguridad import requiere_rol
from .productos import CAMPOS, _completar

bp = Blueprint("carrito", __name__)

CODIGO_VALIDO = re.compile(r"^[A-Za-z0-9-]{1,20}$")
MAX_LINEAS = 60          # líneas distintas en un carrito
MAX_PIEZAS = 20          # piezas del mismo producto en una línea
CENTAVO = Decimal("0.01")


class CarritoInvalido(Exception):
    """El carrito completo no se puede calcular (sucursal o formato inválido)."""


def _buscar(codigo, sucursal_id):
    """Busca el producto por código de barras o por PLU (etiqueta de báscula).
       Devuelve (producto, peso_de_bascula) o lanza ValueError con el motivo."""
    if es_codigo_bascula(codigo):
        plu, peso = leer_codigo_bascula(codigo)
        p = query(f"""SELECT {CAMPOS} FROM v_inventario
                      WHERE plu = %s AND sucursal_id = %s AND activo = 1
                        AND tipo_venta = 'GRANEL'""", (plu, sucursal_id), one=True)
    else:
        peso = None
        p = query(f"""SELECT {CAMPOS} FROM v_inventario
                      WHERE codigo_barras = %s AND sucursal_id = %s AND activo = 1""",
                  (codigo, sucursal_id), one=True)
    if not p:
        raise ValueError("Este producto no está disponible en esta sucursal")
    return _completar(p), peso


def calcular_carrito(datos):
    """Calcula el carrito. Devuelve un diccionario con líneas y totales.
       Lanza CarritoInvalido si la sucursal o el formato no son válidos."""
    # 1. Sucursal
    try:
        sucursal_id = int(datos.get("sucursal_id"))
    except (TypeError, ValueError):
        raise CarritoInvalido("Elige una sucursal válida")
    if not query("SELECT id FROM sucursales WHERE id = %s AND activa = 1",
                 (sucursal_id,), one=True):
        raise CarritoInvalido("Elige una sucursal válida")

    # 2. Líneas
    lineas = datos.get("lineas")
    if not isinstance(lineas, list):
        raise CarritoInvalido("El carrito no es válido")
    if len(lineas) > MAX_LINEAS:
        raise CarritoInvalido(f"El carrito admite máximo {MAX_LINEAS} productos distintos")

    resultado = []
    pedido_por_producto = {}   # producto_id -> piezas o kg pedidos (para revisar existencias)

    for i, linea in enumerate(lineas):
        fila = {"indice": i}
        resultado.append(fila)
        try:
            if not isinstance(linea, dict):
                raise ValueError("Línea no válida")
            codigo = str(linea.get("codigo", "")).strip()
            fila["codigo"] = codigo
            if not CODIGO_VALIDO.match(codigo):
                raise ValueError("El código no es válido")

            p, peso = _buscar(codigo, sucursal_id)
            fila.update({
                "producto_id": p["producto_id"],
                "nombre": p["nombre"],
                "tipo_venta": p["tipo_venta"],
                "precio": p["precio"],                  # precio normal
                "precio_final": p["precio_final"],      # con oferta si existe
                "es_local": p["es_local"],
            })

            if p["tipo_venta"] == "GRANEL":
                if peso is None:   # etiqueta de anaquel: el peso lo mandó la app
                    if linea.get("peso_kg") is None:
                        raise ValueError("Falta el peso del producto")
                    peso = normalizar_peso(linea["peso_kg"], "kg")
                cantidad = peso
                fila["peso_kg"] = peso
                fila["desde_bascula"] = es_codigo_bascula(codigo)
            else:
                cantidad = linea.get("cantidad", 1)
                if isinstance(cantidad, bool) or not isinstance(cantidad, int):
                    raise ValueError("La cantidad debe ser un número entero")
                if not 1 <= cantidad <= MAX_PIEZAS:
                    raise ValueError(f"La cantidad debe ser de 1 a {MAX_PIEZAS} piezas")
                cantidad = Decimal(cantidad)
                fila["cantidad"] = int(cantidad)

            if p["caducado"]:
                raise ValueError("Producto caducado: déjalo en su lugar")
            if p["agotado"]:
                raise ValueError("Producto agotado en esta sucursal")

            fila["importe"] = calcular_importe(p["precio_final"], cantidad)
            fila["importe_normal"] = calcular_importe(p["precio"], cantidad)
            fila["_cantidad"] = cantidad
            fila["_stock"] = p["stock"]
            pedido_por_producto[p["producto_id"]] = (
                pedido_por_producto.get(p["producto_id"], Decimal(0)) + cantidad)
        except ValueError as e:
            fila["error"] = str(e)

    # 3. Existencias: se suma lo pedido de cada producto en todas sus líneas
    for fila in resultado:
        if "error" in fila or "_cantidad" not in fila:
            continue
        pedido = pedido_por_producto[fila["producto_id"]]
        stock = fila["_stock"]
        if pedido > stock:
            unidad = "kg" if fila["tipo_venta"] == "GRANEL" else "piezas"
            disponible = f"{stock:.3f}" if unidad == "kg" else f"{int(stock)}"
            fila["error"] = f"Solo hay {disponible} {unidad} disponibles"

    # 4. Totales (solo líneas sin error)
    subtotal = ahorro = total = Decimal("0.00")
    for fila in resultado:
        fila.pop("_cantidad", None)
        fila.pop("_stock", None)
        if "error" in fila:
            fila.pop("importe", None)
            fila.pop("importe_normal", None)
            continue
        subtotal += fila["importe_normal"]
        total += fila["importe"]
        ahorro += fila["importe_normal"] - fila["importe"]

    con_error = sum(1 for f in resultado if "error" in f)
    return {
        "sucursal_id": sucursal_id,
        "lineas": resultado,
        "articulos": sum(f.get("cantidad", 1) for f in resultado if "error" not in f),
        "subtotal": subtotal.quantize(CENTAVO),
        "ahorro": ahorro.quantize(CENTAVO),
        "total": total.quantize(CENTAVO),
        "lineas_con_error": con_error,
        "se_puede_pagar": bool(resultado) and con_error == 0,
    }


@bp.post("/carrito/cotizar")
@requiere_rol()
def cotizar():
    datos = request.get_json(silent=True) or {}
    try:
        carrito = calcular_carrito(datos)
    except CarritoInvalido as e:
        return jsonify(error=str(e)), 400

    # Puntos del cliente: cuántos puede usar y cuántos ganaría (PASO 11)
    u = query("SELECT puntos_saldo FROM usuarios WHERE id = %s", (g.usuario_id,), one=True)
    carrito["puntos"] = resumen_puntos(carrito, u["puntos_saldo"])
    return jsonify(carrito)