"""
ADMINISTRADOR (portal web) - Productos  (PASO W10)

  Solo usuarios con rol ADMIN:
    GET /api/admin/productos
        Catálogo completo (también los inactivos) con su calificación,
        reportes sin revisar y existencias, más las listas de categorías
        y productores locales para los formularios.
    PUT /api/admin/productos/<producto_id>
        Cambia uno o varios de estos datos (solo los que se manden):
          nombre, descripcion, categoria_id,
          precio, precio_oferta        (null o "" = sin oferta),
          productor_id                 (null o "" = no es producto local),
          activo                       (false = deja de venderse en la app),
          opiniones_activas            (false = nadie puede opinar; las
                                        opiniones que ya existen se conservan)

  El catálogo es el mismo para todas las sucursales: un precio nuevo
  aplica en todas. Las ventas que ya se hicieron no cambian, porque
  venta_detalle guarda el nombre y el precio de ese momento.
"""
from decimal import Decimal, InvalidOperation

from flask import Blueprint, jsonify, request

from ..db import get_db, query
from ..utils.seguridad import requiere_rol

bp = Blueprint("admin_productos", __name__)

PRECIO_MAXIMO = Decimal("99999.99")
CAMPOS = ("nombre", "descripcion", "categoria_id", "precio", "precio_oferta",
          "productor_id", "activo", "opiniones_activas")


# ------------------------------------------------------------------
# Ayudantes
# ------------------------------------------------------------------
def _error(mensaje, estado=400, **extra):
    return jsonify(error=mensaje, **extra), estado


def _dinero(valor):
    """Texto o número -> Decimal con 2 decimales. None si no es válido."""
    try:
        n = Decimal(str(valor).strip().replace(",", ".").replace("$", ""))
    except (InvalidOperation, AttributeError):
        return None
    if not n.is_finite() or n != n.quantize(Decimal("0.01")):
        return None
    return n


def _booleano(valor):
    """true/false, 1/0, "true"/"false" -> bool. Cualquier otra cosa -> None."""
    if isinstance(valor, bool):
        return valor
    if valor in (1, 0, "1", "0"):
        return valor in (1, "1")
    if isinstance(valor, str) and valor.lower() in ("true", "false"):
        return valor.lower() == "true"
    return None


def _vacio(valor):
    return valor is None or (isinstance(valor, str) and not valor.strip())


SELECT_PRODUCTO = """
    SELECT p.id, p.codigo_barras, p.plu, p.nombre, p.descripcion, p.tipo_venta,
           p.categoria_id, c.nombre AS categoria,
           p.productor_id, pl.nombre AS productor, pl.municipio AS productor_municipio,
           p.precio, p.precio_oferta, p.activo, p.opiniones_activas,
           COALESCE(o.total, 0) AS opiniones, o.promedio,
           COALESCE(rp.pendientes, 0) AS reportes_pendientes,
           COALESCE(i.stock, 0) AS stock_total, COALESCE(i.sucursales, 0) AS sucursales
    FROM productos p
    LEFT JOIN categorias c           ON c.id = p.categoria_id
    LEFT JOIN productores_locales pl ON pl.id = p.productor_id
    LEFT JOIN (SELECT producto_id, COUNT(*) AS total, ROUND(AVG(estrellas), 1) AS promedio
               FROM opiniones WHERE estado = 'PUBLICADA'
               GROUP BY producto_id) o ON o.producto_id = p.id
    LEFT JOIN (SELECT op.producto_id, COUNT(*) AS pendientes
               FROM reportes_opinion r JOIN opiniones op ON op.id = r.opinion_id
               WHERE r.revisado = 0
               GROUP BY op.producto_id) rp ON rp.producto_id = p.id
    LEFT JOIN (SELECT producto_id, SUM(stock) AS stock, COUNT(*) AS sucursales
               FROM inventario GROUP BY producto_id) i ON i.producto_id = p.id
"""


def _producto(producto_id):
    return query(SELECT_PRODUCTO + " WHERE p.id = %s", (producto_id,), one=True)


# ------------------------------------------------------------------
# CATÁLOGO
# ------------------------------------------------------------------
@bp.get("/productos")
@requiere_rol("ADMIN")
def productos():
    lista = query(SELECT_PRODUCTO + " ORDER BY p.activo DESC, c.nombre, p.nombre")
    activos = [p for p in lista if p["activo"]]
    return jsonify(
        resumen={
            "productos": len(lista),
            "activos": len(activos),
            "en_oferta": sum(1 for p in activos if p["precio_oferta"] is not None),
            "locales": sum(1 for p in activos if p["productor_id"] is not None),
            "opiniones_apagadas": sum(1 for p in activos if not p["opiniones_activas"]),
        },
        productos=lista,
        categorias=query("SELECT id, nombre FROM categorias ORDER BY nombre"),
        productores=query("""SELECT id, nombre, municipio FROM productores_locales
                             ORDER BY nombre"""),
    )


# ------------------------------------------------------------------
# EDITAR UN PRODUCTO
# ------------------------------------------------------------------
@bp.put("/productos/<int:producto_id>")
@requiere_rol("ADMIN")
def editar_producto(producto_id):
    d = request.get_json(silent=True) or {}
    actual = query("""SELECT id, nombre, descripcion, categoria_id, precio, precio_oferta,
                             productor_id, activo, opiniones_activas
                      FROM productos WHERE id = %s""", (producto_id,), one=True)
    if not actual:
        return _error("Producto no encontrado", 404)
    if not any(c in d for c in CAMPOS):
        return _error("No mandaste ningún dato para cambiar")

    nuevo = dict(actual)

    if "nombre" in d:
        nombre = " ".join(str(d["nombre"] or "").split())
        if not 3 <= len(nombre) <= 120:
            return _error("El nombre debe tener de 3 a 120 caracteres")
        if query("SELECT 1 FROM productos WHERE nombre = %s AND id <> %s",
                 (nombre, producto_id), one=True):
            return _error("Ya hay otro producto con ese nombre")
        nuevo["nombre"] = nombre

    if "descripcion" in d:
        descripcion = " ".join(str(d["descripcion"] or "").split())
        if len(descripcion) > 255:
            return _error("La descripción puede tener máximo 255 caracteres")
        nuevo["descripcion"] = descripcion or None

    if "categoria_id" in d:
        if _vacio(d["categoria_id"]):
            nuevo["categoria_id"] = None
        else:
            try:
                categoria_id = int(d["categoria_id"])
            except (TypeError, ValueError):
                return _error("La categoría no es válida")
            if not query("SELECT 1 FROM categorias WHERE id = %s", (categoria_id,), one=True):
                return _error("La categoría no existe")
            nuevo["categoria_id"] = categoria_id

    if "precio" in d:
        precio = _dinero(d["precio"])
        if precio is None:
            return _error("Escribe un precio válido (máximo 2 decimales)")
        if not Decimal("0") < precio <= PRECIO_MAXIMO:
            return _error(f"El precio debe ser mayor que $0 y máximo ${PRECIO_MAXIMO}")
        nuevo["precio"] = precio

    if "precio_oferta" in d:
        if _vacio(d["precio_oferta"]):
            nuevo["precio_oferta"] = None
        else:
            oferta = _dinero(d["precio_oferta"])
            if oferta is None or oferta <= 0:
                return _error("Escribe un precio de oferta válido (máximo 2 decimales)")
            nuevo["precio_oferta"] = oferta

    # La oferta siempre debe ser menor que el precio (la base también lo exige)
    if nuevo["precio_oferta"] is not None and nuevo["precio_oferta"] >= nuevo["precio"]:
        return _error("El precio de oferta debe ser menor que el precio normal",
                      codigo="OFERTA_INVALIDA")

    if "productor_id" in d:
        if _vacio(d["productor_id"]):
            nuevo["productor_id"] = None
        else:
            try:
                productor_id = int(d["productor_id"])
            except (TypeError, ValueError):
                return _error("El productor no es válido")
            if not query("SELECT 1 FROM productores_locales WHERE id = %s",
                         (productor_id,), one=True):
                return _error("El productor no existe")
            nuevo["productor_id"] = productor_id

    for campo in ("activo", "opiniones_activas"):
        if campo in d:
            valor = _booleano(d[campo])
            if valor is None:
                return _error(f"El valor de {campo} debe ser verdadero o falso")
            nuevo[campo] = valor

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE productos
                           SET nombre = %s, descripcion = %s, categoria_id = %s,
                               precio = %s, precio_oferta = %s, productor_id = %s,
                               activo = %s, opiniones_activas = %s
                           WHERE id = %s""",
                        (nuevo["nombre"], nuevo["descripcion"], nuevo["categoria_id"],
                         nuevo["precio"], nuevo["precio_oferta"], nuevo["productor_id"],
                         nuevo["activo"], nuevo["opiniones_activas"], producto_id))
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    return jsonify(mensaje=f"Producto actualizado: {nuevo['nombre']}",
                   producto=_producto(producto_id))