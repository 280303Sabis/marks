"""
ADMINISTRADOR (portal web) - Inventario y kárdex  (PASO W9)

  Solo usuarios con rol ADMIN:
    GET  /api/admin/inventario?sucursal_id=1
         Existencias de la sucursal con alertas (stock bajo, por caducar,
         caducado, sin stock) y los totales para las tarjetas.
    GET  /api/admin/kardex?sucursal_id=1&producto_id=&tipo=todos&periodo=mes
         Entradas y salidas (kárdex) con quién las hizo y el folio de la venta.
    POST /api/admin/inventario/movimiento
         Registra una ENTRADA, una MERMA o un AJUSTE (conteo físico).
    PUT  /api/admin/inventario/<producto_id>
         Cambia el stock mínimo y la fecha de caducidad (no mueve existencias).

  Tipos de movimiento:
    ENTRADA       llega mercancía              -> suma "cantidad"
    MERMA         producto dañado o caducado   -> resta "cantidad" (pide motivo)
    AJUSTE        conteo físico                -> el stock queda en "stock_real" (pide motivo)
    SALIDA_VENTA  la crea el pago de la app (no se registra aquí)

  Cada cambio se guarda en una sola transacción: se bloquea el renglón de
  inventario (FOR UPDATE), se actualiza el stock y se escribe el kárdex con
  el usuario que lo hizo. Así dos personas no pueden pisarse el stock.
"""
from datetime import date
from decimal import Decimal, InvalidOperation

from flask import Blueprint, g, jsonify, request

from ..db import get_db, query
from ..utils.seguridad import requiere_rol
from .admin import _desfase_bd, _hora_mx, _inicio_periodo, _sucursal, _sucursales

bp = Blueprint("admin_inventario", __name__)

TIPOS_KARDEX = ("ENTRADA", "SALIDA_VENTA", "MERMA", "AJUSTE")
TIPOS_MANUALES = ("ENTRADA", "MERMA", "AJUSTE")
PERIODOS_KARDEX = ("hoy", "semana", "mes", "anio", "todo")
CANTIDAD_MAXIMA = Decimal("9999")


# ------------------------------------------------------------------
# Ayudantes
# ------------------------------------------------------------------
def _error(mensaje, estado=400, **extra):
    return jsonify(error=mensaje, **extra), estado


def _numero(valor):
    """Texto o número -> Decimal. None si no es un número válido."""
    try:
        n = Decimal(str(valor).strip().replace(",", "."))
    except (InvalidOperation, AttributeError):
        return None
    return n if n.is_finite() else None


def _cantidad_valida(n, tipo_venta, permite_cero=False):
    """Revisa una cantidad según el tipo de producto. Devuelve un mensaje de error o None."""
    if n is None:
        return "Escribe una cantidad válida"
    if n < 0:
        return "La cantidad no puede ser negativa"
    if n == 0 and not permite_cero:
        return "La cantidad debe ser mayor que cero"
    if n > CANTIDAD_MAXIMA:
        return f"La cantidad máxima por movimiento es {CANTIDAD_MAXIMA}"
    if tipo_venta == "UNIDAD" and n != n.to_integral_value():
        return "Este producto se vende por pieza: usa números enteros"
    if tipo_venta == "GRANEL" and n != n.quantize(Decimal("0.001")):
        return "Usa máximo 3 decimales (gramos)"
    return None


def _fecha(valor):
    """'2026-11-05' -> date. '' o None -> None. Inválida -> False."""
    if valor in (None, ""):
        return None
    try:
        return date.fromisoformat(str(valor)[:10])
    except ValueError:
        return False


def _fila_inventario(producto_id, sucursal_id):
    """Un producto de la sucursal, como aparece en la tabla del panel."""
    return query("""SELECT producto_id, codigo_barras, plu, nombre, categoria, tipo_venta,
                           COALESCE(precio_oferta, precio) AS precio, es_local, productor,
                           activo, stock, stock_minimo, stock_bajo, fecha_caducidad,
                           caducado, caducidad_proxima
                    FROM v_inventario
                    WHERE producto_id = %s AND sucursal_id = %s""",
                 (producto_id, sucursal_id), one=True)


# ------------------------------------------------------------------
# EXISTENCIAS
# ------------------------------------------------------------------
@bp.get("/inventario")
@requiere_rol("ADMIN")
def inventario():
    s = _sucursal()
    if not s:
        return _error("No hay sucursales activas", 404)

    productos = query("""SELECT producto_id, codigo_barras, plu, nombre, categoria, tipo_venta,
                                COALESCE(precio_oferta, precio) AS precio, es_local, productor,
                                activo, stock, stock_minimo, stock_bajo, fecha_caducidad,
                                caducado, caducidad_proxima
                         FROM v_inventario
                         WHERE sucursal_id = %s
                         ORDER BY activo DESC, caducado DESC, (stock <= 0) DESC,
                                  stock_bajo DESC, caducidad_proxima DESC, nombre""",
                      (s["id"],))

    activos = [p for p in productos if p["activo"]]
    resumen = {
        "productos": len(activos),
        "sin_stock": sum(1 for p in activos if p["stock"] <= 0),
        "stock_bajo": sum(1 for p in activos if p["stock_bajo"] and p["stock"] > 0),
        "por_caducar": sum(1 for p in activos if p["caducidad_proxima"]),
        "caducados": sum(1 for p in activos if p["caducado"]),
    }
    return jsonify(sucursal=s, sucursales=_sucursales(), resumen=resumen, productos=productos)


# ------------------------------------------------------------------
# KÁRDEX (entradas y salidas)
# ------------------------------------------------------------------
@bp.get("/kardex")
@requiere_rol("ADMIN")
def kardex():
    s = _sucursal()
    if not s:
        return _error("No hay sucursales activas", 404)
    desfase = _desfase_bd()

    periodo = (request.args.get("periodo") or "mes").lower()
    if periodo not in PERIODOS_KARDEX:
        periodo = "mes"

    filtros = ""
    params = [s["id"]]
    if periodo != "todo":
        filtros += " AND m.fecha >= %s"
        params.append(_inicio_periodo(periodo, desfase))
    producto_id = request.args.get("producto_id", type=int)
    if producto_id:
        filtros += " AND m.producto_id = %s"
        params.append(producto_id)
    tipo = (request.args.get("tipo") or "").upper()
    if tipo in TIPOS_KARDEX:
        filtros += " AND m.tipo = %s"
        params.append(tipo)

    movimientos = query(f"""SELECT m.id, m.fecha, m.tipo, m.cantidad, m.stock_final, m.nota,
                                   p.id AS producto_id, p.nombre AS producto, p.tipo_venta,
                                   v.folio,
                                   CONCAT_WS(' ', u.nombre, u.apellidos) AS usuario,
                                   r.nombre AS rol
                            FROM movimientos_inventario m
                            JOIN productos p      ON p.id = m.producto_id
                            LEFT JOIN ventas v    ON v.id = m.venta_id
                            LEFT JOIN usuarios u  ON u.id = m.usuario_id
                            LEFT JOIN roles r     ON r.id = u.rol_id
                            WHERE m.sucursal_id = %s {filtros}
                            ORDER BY m.fecha DESC, m.id DESC
                            LIMIT 500""", params)

    totales = {t: Decimal("0") for t in TIPOS_KARDEX}
    for m in movimientos:
        totales[m["tipo"]] += m["cantidad"]
        m["fecha"] = _hora_mx(m["fecha"], desfase)
        # En ventas no se muestra el nombre del cliente: basta el folio
        if m["tipo"] == "SALIDA_VENTA":
            m["usuario"] = "Cliente (app)"
        elif not m["usuario"]:
            m["usuario"] = "Sistema"      # carga inicial hecha con el script de la base
        m.pop("rol")

    productos = query("""SELECT producto_id AS id, nombre, tipo_venta FROM v_inventario
                         WHERE sucursal_id = %s ORDER BY nombre""", (s["id"],))

    return jsonify(sucursal=s, sucursales=_sucursales(), periodo=periodo,
                   productos=productos, movimientos=movimientos,
                   totales={"entradas": totales["ENTRADA"],
                            "ventas": -totales["SALIDA_VENTA"],
                            "mermas": -totales["MERMA"],
                            "ajustes": totales["AJUSTE"]},
                   limite=len(movimientos) == 500)


# ------------------------------------------------------------------
# REGISTRAR ENTRADA, MERMA O AJUSTE
# ------------------------------------------------------------------
@bp.post("/inventario/movimiento")
@requiere_rol("ADMIN")
def registrar_movimiento():
    d = request.get_json(silent=True) or {}
    tipo = str(d.get("tipo") or "").upper()
    if tipo not in TIPOS_MANUALES:
        return _error("Elige el tipo de movimiento: entrada, merma o ajuste")
    try:
        sucursal_id = int(d.get("sucursal_id"))
        producto_id = int(d.get("producto_id"))
    except (TypeError, ValueError):
        return _error("Falta la sucursal o el producto")

    nota = str(d.get("nota") or "").strip()[:200]
    if tipo in ("MERMA", "AJUSTE") and len(nota) < 3:
        return _error("Escribe el motivo (por ejemplo: empaque roto, conteo físico)")

    caducidad = _fecha(d.get("fecha_caducidad"))
    if caducidad is False:
        return _error("La fecha de caducidad no es válida")
    if caducidad and caducidad < date.today():
        return _error("La fecha de caducidad ya pasó; registra el producto como merma")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""SELECT i.stock, p.tipo_venta, p.nombre
                           FROM inventario i JOIN productos p ON p.id = i.producto_id
                           WHERE i.producto_id = %s AND i.sucursal_id = %s
                           FOR UPDATE""", (producto_id, sucursal_id))
            fila = cur.fetchone()
            if not fila:
                conn.rollback()
                return _error("Ese producto no está en el inventario de la sucursal", 404)
            stock = fila["stock"]

            if tipo == "AJUSTE":
                real = _numero(d.get("stock_real"))
                problema = _cantidad_valida(real, fila["tipo_venta"], permite_cero=True)
                if problema:
                    conn.rollback()
                    return _error(problema.replace("La cantidad", "El conteo"))
                cambio = real - stock
                if cambio == 0:
                    conn.rollback()
                    return _error("El conteo es igual al stock actual; no hay nada que ajustar")
            else:
                n = _numero(d.get("cantidad"))
                problema = _cantidad_valida(n, fila["tipo_venta"])
                if problema:
                    conn.rollback()
                    return _error(problema)
                cambio = n if tipo == "ENTRADA" else -n
                if stock + cambio < 0:
                    conn.rollback()
                    return _error(f"Solo hay {stock.normalize():f} en existencia; "
                                  "la merma no puede ser mayor", 409, codigo="STOCK_INSUFICIENTE")

            stock_final = stock + cambio
            if tipo == "ENTRADA" and caducidad:
                # Mercancía nueva: la caducidad del lote que llegó
                cur.execute("""UPDATE inventario SET stock = %s, fecha_caducidad = %s
                               WHERE producto_id = %s AND sucursal_id = %s""",
                            (stock_final, caducidad, producto_id, sucursal_id))
            else:
                cur.execute("""UPDATE inventario SET stock = %s
                               WHERE producto_id = %s AND sucursal_id = %s""",
                            (stock_final, producto_id, sucursal_id))

            cur.execute("""INSERT INTO movimientos_inventario
                             (producto_id, sucursal_id, tipo, cantidad, stock_final,
                              usuario_id, nota)
                           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                        (producto_id, sucursal_id, tipo, cambio, stock_final,
                         g.usuario_id, nota or None))
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    nombres = {"ENTRADA": "Entrada registrada", "MERMA": "Merma registrada",
               "AJUSTE": "Ajuste registrado"}
    return jsonify(mensaje=f"{nombres[tipo]}: {fila['nombre']}",
                   producto=_fila_inventario(producto_id, sucursal_id)), 201


# ------------------------------------------------------------------
# STOCK MÍNIMO Y CADUCIDAD
# ------------------------------------------------------------------
@bp.put("/inventario/<int:producto_id>")
@requiere_rol("ADMIN")
def editar_inventario(producto_id):
    d = request.get_json(silent=True) or {}
    try:
        sucursal_id = int(d.get("sucursal_id"))
    except (TypeError, ValueError):
        return _error("Falta la sucursal")

    actual = _fila_inventario(producto_id, sucursal_id)
    if not actual:
        return _error("Ese producto no está en el inventario de la sucursal", 404)

    minimo = _numero(d.get("stock_minimo"))
    problema = _cantidad_valida(minimo, actual["tipo_venta"], permite_cero=True)
    if problema:
        return _error(problema.replace("La cantidad", "El stock mínimo"))

    caducidad = _fecha(d.get("fecha_caducidad"))
    if caducidad is False:
        return _error("La fecha de caducidad no es válida")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE inventario SET stock_minimo = %s, fecha_caducidad = %s
                           WHERE producto_id = %s AND sucursal_id = %s""",
                        (minimo, caducidad, producto_id, sucursal_id))
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    return jsonify(mensaje="Datos del inventario guardados",
                   producto=_fila_inventario(producto_id, sucursal_id))