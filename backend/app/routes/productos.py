"""
PRODUCTOS (lado del cliente)

  Público:
    GET /api/sucursales                                    sucursales activas

  Requieren sesión iniciada:
    GET /api/productos?sucursal_id=1                       catálogo de una sucursal
    GET /api/productos/escanear/<codigo>?sucursal_id=1     producto escaneado

  Granel (se vende por kilo), dos formas:
    A) Etiqueta de báscula:  /api/productos/escanear/2140001012508?sucursal_id=1
       -> el peso viene dentro del código (1.250 kg)
    B) Peso escrito:         /api/productos/escanear/GR-40001?sucursal_id=1&peso=850&unidad=g
       -> el cliente escribe el peso; unidad = kg (por defecto) o g

  Cada producto incluye:
    precio_final       precio que paga el cliente (oferta si existe)
    agotado            sin existencias en la sucursal
    caducado           la fecha de caducidad ya pasó
    caducidad_proxima  vence hoy o en los próximos 3 días
    se_puede_vender    no está agotado ni caducado
  Y si es granel con peso:
    peso_kg            kilos (3 decimales)
    importe            precio_final x peso_kg, calculado aquí en el servidor
    desde_bascula      true si el peso vino de la etiqueta de báscula
"""
import re

from flask import Blueprint, jsonify, request

from ..db import query
from ..utils.granel import (calcular_importe, es_codigo_bascula,
                            leer_codigo_bascula, normalizar_peso)
from ..utils.seguridad import requiere_rol

bp = Blueprint("productos", __name__)

# Códigos de barras (EAN) y códigos internos de granel (ej. GR-40001)
CODIGO_VALIDO = re.compile(r"^[A-Za-z0-9-]{1,20}$")

CAMPOS = """producto_id, codigo_barras, plu, nombre, categoria, tipo_venta,
            precio, precio_oferta, stock, es_local, productor,
            fecha_caducidad, caducado, caducidad_proxima"""


def _sucursal_activa():
    """Devuelve el id de la sucursal si viene en la URL y está activa; si no, None."""
    sucursal_id = request.args.get("sucursal_id", type=int)
    if not sucursal_id:
        return None
    existe = query("SELECT id FROM sucursales WHERE id = %s AND activa = 1",
                   (sucursal_id,), one=True)
    return sucursal_id if existe else None


def _completar(p):
    """Agrega los datos que la app necesita para mostrar el producto."""
    p["precio_final"] = p["precio_oferta"] or p["precio"]   # precio que paga el cliente
    p["agotado"] = p["stock"] <= 0
    # MySQL manda 0/1; los convertimos a true/false
    p["caducado"] = bool(p["caducado"])
    p["caducidad_proxima"] = bool(p["caducidad_proxima"])
    # Regla única para vender: con existencias y sin caducar
    p["se_puede_vender"] = not p["agotado"] and not p["caducado"]
    return p


@bp.get("/sucursales")
def sucursales():
    """Lista de sucursales activas (pantalla 'Elige tu sucursal')."""
    return jsonify(query("""SELECT id, nombre, direccion, municipio
                            FROM sucursales WHERE activa = 1 ORDER BY nombre"""))


@bp.get("/productos")
@requiere_rol()
def listar_productos():
    """Catálogo de una sucursal.  Ej: /api/productos?sucursal_id=1"""
    sucursal_id = _sucursal_activa()
    if not sucursal_id:
        return jsonify(error="Elige una sucursal válida"), 400

    productos = query(f"""SELECT {CAMPOS} FROM v_inventario
                          WHERE sucursal_id = %s AND activo = 1
                          ORDER BY nombre""", (sucursal_id,))
    return jsonify([_completar(p) for p in productos])


@bp.get("/productos/escanear/<codigo>")
@requiere_rol()
def escanear(codigo):
    """Lo que hace la app al leer un código de barras.
       Ej: /api/productos/escanear/7501000000029?sucursal_id=1
       Un producto caducado o agotado SÍ se devuelve (con se_puede_vender = false)
       para que la app explique por qué no se puede agregar."""
    codigo = codigo.strip()
    if not CODIGO_VALIDO.match(codigo):
        return jsonify(error="El código no es válido"), 400

    sucursal_id = _sucursal_activa()
    if not sucursal_id:
        return jsonify(error="Elige una sucursal válida"), 400

    peso = None
    desde_bascula = es_codigo_bascula(codigo)

    if desde_bascula:
        # A) Etiqueta de báscula: el PLU y el peso vienen dentro del código
        try:
            plu, peso = leer_codigo_bascula(codigo)
        except ValueError as e:
            return jsonify(error=str(e)), 400
        p = query(f"""SELECT {CAMPOS} FROM v_inventario
                      WHERE plu = %s AND sucursal_id = %s AND activo = 1
                        AND tipo_venta = 'GRANEL'""",
                  (plu, sucursal_id), one=True)
    else:
        p = query(f"""SELECT {CAMPOS} FROM v_inventario
                      WHERE codigo_barras = %s AND sucursal_id = %s AND activo = 1""",
                  (codigo, sucursal_id), one=True)

    if not p:
        return jsonify(error="Este producto no está disponible en esta sucursal"), 404

    p = _completar(p)

    # B) Peso escrito por el cliente (solo si no vino de la báscula)
    peso_escrito = request.args.get("peso")
    if peso is None and peso_escrito is not None:
        if p["tipo_venta"] != "GRANEL":
            return jsonify(error="Este producto se vende por pieza"), 400
        try:
            peso = normalizar_peso(peso_escrito, request.args.get("unidad", "kg"))
        except ValueError as e:
            return jsonify(error=str(e)), 400

    p["desde_bascula"] = desde_bascula
    if peso is not None:
        if peso > p["stock"]:
            return jsonify(error=f"Solo hay {p['stock']:.3f} kg disponibles en esta sucursal"), 409
        p["peso_kg"] = float(peso)
        p["importe"] = float(calcular_importe(p["precio_final"], peso))

    return jsonify(p)