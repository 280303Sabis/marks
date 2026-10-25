"""
ADMINISTRADOR (portal web) - datos reales de ventas e inventario

  Solo usuarios con rol ADMIN:
    GET /api/admin/resumen?sucursal_id=1
        Inicio del panel: ventas de hoy, unidades, por caducar, sin stock,
        productos con lo vendido hoy, el más vendido y la demanda de 7 días.
    GET /api/admin/mas-vendidos?sucursal_id=1&periodo=semana&categoria=todas&buscar=
        Ranking de productos más vendidos en el periodo.
    GET /api/admin/ventas?sucursal_id=1&periodo=semana&estado=todos&buscar=
        Historial de compras de la sucursal.

  periodo: hoy | semana | mes | anio   (semana = desde el lunes)
  Las fechas se calculan con la hora de Monterrey (UTC-6, sin horario de verano).
  Solo cuentan las ventas PAGADA y VALIDADA (las CANCELADA no son ingreso).
"""
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request

from ..db import query
from ..utils.seguridad import requiere_rol

bp = Blueprint("admin", __name__)

HORA_MX = timezone(timedelta(hours=-6))
PERIODOS = ("hoy", "semana", "mes", "anio")
ESTADOS = {"pagada": "PAGADA", "validada": "VALIDADA"}
VENTA_VALIDA = "v.estado IN ('PAGADA','VALIDADA')"


# ------------------------------------------------------------------
# Fechas: la BD guarda la hora de su servidor (Aiven = UTC, MySQL local = la de la PC)
# ------------------------------------------------------------------
def _desfase_bd():
    """Diferencia entre la hora de la BD y UTC (en horas enteras)."""
    ahora_bd = query("SELECT NOW() AS ahora", one=True)["ahora"]
    ahora_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    return timedelta(hours=round((ahora_bd - ahora_utc).total_seconds() / 3600))


def _inicio_periodo(periodo, desfase):
    """Inicio del periodo (hora de Monterrey) convertido a la hora de la BD."""
    hoy = datetime.now(HORA_MX).replace(hour=0, minute=0, second=0, microsecond=0)
    if periodo == "semana":
        inicio = hoy - timedelta(days=hoy.weekday())
    elif periodo == "mes":
        inicio = hoy.replace(day=1)
    elif periodo == "anio":
        inicio = hoy.replace(month=1, day=1)
    else:
        inicio = hoy
    return inicio.astimezone(timezone.utc).replace(tzinfo=None) + desfase


def _hora_mx(fecha_bd, desfase):
    """Fecha guardada en la BD -> texto con la hora de Monterrey."""
    if fecha_bd is None:
        return None
    utc = (fecha_bd - desfase).replace(tzinfo=timezone.utc)
    return utc.astimezone(HORA_MX).strftime("%Y-%m-%d %H:%M")


def _sucursal():
    """Sucursal pedida en la URL; si no viene, la primera activa."""
    sucursal_id = request.args.get("sucursal_id", type=int)
    if sucursal_id:
        s = query("""SELECT id, nombre, direccion, municipio FROM sucursales
                     WHERE id = %s AND activa = 1""", (sucursal_id,), one=True)
        if s:
            return s
    return query("""SELECT id, nombre, direccion, municipio FROM sucursales
                    WHERE activa = 1 ORDER BY id LIMIT 1""", one=True)


def _periodo():
    p = (request.args.get("periodo") or "semana").lower()
    return p if p in PERIODOS else "semana"


def _sucursales():
    return query("SELECT id, nombre FROM sucursales WHERE activa = 1 ORDER BY id")


# ------------------------------------------------------------------
# INICIO DEL PANEL
# ------------------------------------------------------------------
@bp.get("/resumen")
@requiere_rol("ADMIN")
def resumen():
    s = _sucursal()
    if not s:
        return jsonify(error="No hay sucursales activas"), 404
    desfase = _desfase_bd()
    hoy = _inicio_periodo("hoy", desfase)

    ventas = query(f"""SELECT COUNT(*) AS compras, COALESCE(SUM(v.total), 0) AS total,
                              COALESCE(SUM(v.ahorro), 0) AS ahorro
                       FROM ventas v
                       WHERE v.sucursal_id = %s AND v.pagada_en >= %s AND {VENTA_VALIDA}""",
                   (s["id"], hoy), one=True)
    unidades = query(f"""SELECT COALESCE(SUM(d.cantidad), 0) AS unidades
                         FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
                         WHERE v.sucursal_id = %s AND v.pagada_en >= %s AND {VENTA_VALIDA}""",
                     (s["id"], hoy), one=True)["unidades"]
    alertas = query("""SELECT COALESCE(SUM(caducidad_proxima), 0) AS por_caducar,
                              COALESCE(SUM(stock <= 0), 0)        AS sin_stock
                       FROM v_inventario WHERE sucursal_id = %s AND activo = 1""",
                    (s["id"],), one=True)

    # Productos de la sucursal con lo vendido hoy
    productos = query(f"""SELECT i.producto_id, i.nombre, i.categoria, i.tipo_venta,
                                 COALESCE(i.precio_oferta, i.precio) AS precio, i.stock,
                                 COALESCE(h.vendidas, 0) AS vendidas
                          FROM v_inventario i
                          LEFT JOIN (SELECT d.producto_id, SUM(d.cantidad) AS vendidas
                                     FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
                                     WHERE v.sucursal_id = %s AND v.pagada_en >= %s
                                       AND {VENTA_VALIDA}
                                     GROUP BY d.producto_id) h ON h.producto_id = i.producto_id
                          WHERE i.sucursal_id = %s AND i.activo = 1
                          ORDER BY vendidas DESC, i.nombre""",
                      (s["id"], hoy, s["id"]))
    mas_vendido = productos[0] if productos and productos[0]["vendidas"] > 0 else None

    # Demanda de los últimos 7 días (unidades por día, hora de Monterrey)
    inicio7 = hoy - timedelta(days=6)
    filas = query(f"""SELECT v.pagada_en, d.cantidad
                      FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
                      WHERE v.sucursal_id = %s AND v.pagada_en >= %s AND {VENTA_VALIDA}""",
                  (s["id"], inicio7))
    hoy_mx = datetime.now(HORA_MX).date()
    dias = {(hoy_mx - timedelta(days=n)).isoformat(): 0 for n in range(6, -1, -1)}
    for f in filas:
        dia = _hora_mx(f["pagada_en"], desfase)[:10]
        if dia in dias:
            dias[dia] += float(f["cantidad"])
    demanda = [{"dia": d, "unidades": round(u, 3)} for d, u in dias.items()]

    return jsonify(sucursal=s, sucursales=_sucursales(),
                   hoy={"compras": ventas["compras"], "total": ventas["total"],
                        "ahorro": ventas["ahorro"], "unidades": unidades},
                   por_caducar=int(alertas["por_caducar"]), sin_stock=int(alertas["sin_stock"]),
                   productos=productos, mas_vendido=mas_vendido, demanda=demanda)


# ------------------------------------------------------------------
# MÁS VENDIDOS
# ------------------------------------------------------------------
@bp.get("/mas-vendidos")
@requiere_rol("ADMIN")
def mas_vendidos():
    s = _sucursal()
    if not s:
        return jsonify(error="No hay sucursales activas"), 404
    desfase = _desfase_bd()
    periodo = _periodo()
    inicio = _inicio_periodo(periodo, desfase)

    filtros = ""
    params = [s["id"], inicio]
    categoria = request.args.get("categoria", type=int)
    if categoria:
        filtros += " AND p.categoria_id = %s"
        params.append(categoria)
    buscar = (request.args.get("buscar") or "").strip()[:60]
    if buscar:
        filtros += " AND (p.nombre LIKE %s OR p.codigo_barras LIKE %s OR p.plu LIKE %s)"
        params += [f"%{buscar}%"] * 3

    ranking = query(f"""SELECT p.id AS producto_id, p.nombre, p.tipo_venta,
                               c.nombre AS categoria,
                               COALESCE(p.precio_oferta, p.precio) AS precio,
                               SUM(d.cantidad) AS unidades, SUM(d.importe) AS total
                        FROM venta_detalle d
                        JOIN ventas v    ON v.id = d.venta_id
                        JOIN productos p ON p.id = d.producto_id
                        LEFT JOIN categorias c ON c.id = p.categoria_id
                        WHERE v.sucursal_id = %s AND v.pagada_en >= %s AND {VENTA_VALIDA}
                              {filtros}
                        GROUP BY p.id, p.nombre, p.tipo_venta, p.precio, p.precio_oferta, c.nombre
                        ORDER BY unidades DESC, total DESC""", params)

    unidades = sum(float(r["unidades"]) for r in ranking)
    for r in ranking:
        r["participacion"] = round(float(r["unidades"]) * 100 / unidades, 1) if unidades else 0

    # Categoría con más unidades
    por_cat = {}
    for r in ranking:
        nombre = r["categoria"] or "Sin categoría"
        por_cat[nombre] = por_cat.get(nombre, 0) + float(r["unidades"])
    top_cat = max(por_cat.items(), key=lambda x: x[1]) if por_cat else None

    return jsonify(sucursal=s, sucursales=_sucursales(), periodo=periodo,
                   categorias=query("SELECT id, nombre FROM categorias ORDER BY nombre"),
                   unidades=round(unidades, 3),
                   top_producto=ranking[0] if ranking else None,
                   top_categoria=({"nombre": top_cat[0],
                                   "participacion": round(top_cat[1] * 100 / unidades, 1)}
                                  if top_cat else None),
                   ranking=ranking)


# ------------------------------------------------------------------
# HISTORIAL DE COMPRAS
# ------------------------------------------------------------------
@bp.get("/ventas")
@requiere_rol("ADMIN")
def ventas():
    s = _sucursal()
    if not s:
        return jsonify(error="No hay sucursales activas"), 404
    desfase = _desfase_bd()
    periodo = _periodo()
    inicio = _inicio_periodo(periodo, desfase)

    filtros = ""
    params = [s["id"], inicio]
    estado = ESTADOS.get((request.args.get("estado") or "").lower())
    if estado:
        filtros += " AND v.estado = %s"
        params.append(estado)
    buscar = (request.args.get("buscar") or "").strip()[:60]
    if buscar:
        filtros += """ AND (v.folio LIKE %s OR u.correo LIKE %s
                            OR CONCAT_WS(' ', u.nombre, u.apellidos) LIKE %s)"""
        params += [f"%{buscar}%"] * 3

    filas = query(f"""SELECT v.folio, v.pagada_en, v.articulos, v.total, v.estado,
                             v.usuario_id,
                             CONCAT_WS(' ', u.nombre, u.apellidos) AS cliente, u.correo
                      FROM ventas v JOIN usuarios u ON u.id = v.usuario_id
                      WHERE v.sucursal_id = %s AND v.pagada_en >= %s AND {VENTA_VALIDA}
                            {filtros}
                      ORDER BY v.pagada_en DESC, v.id DESC
                      LIMIT 500""", params)

    total = sum(float(f["total"]) for f in filas)
    clientes = len({f["usuario_id"] for f in filas})
    for f in filas:
        f["fecha"] = _hora_mx(f.pop("pagada_en"), desfase)
        f.pop("usuario_id")

    return jsonify(sucursal=s, sucursales=_sucursales(), periodo=periodo,
                   compras=len(filas), ingreso=round(total, 2),
                   ticket_promedio=round(total / len(filas), 2) if filas else 0,
                   clientes=clientes, ventas=filas)
