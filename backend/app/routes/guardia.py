"""
GUARDIA (portal web) - Validar el QR de salida  (PASO W12)

  Usuarios con rol GUARDIA (o ADMIN, para pruebas y supervisión):
    POST /api/guardia/validar
         {"qr": "MARKS1.MK-261027-000001.firma", "sucursal_id": 1}
         o, si la cámara falla:  {"folio": "MK-261027-000001", "sucursal_id": 1}
         Si la compra se puede validar, pasa a VALIDADA (con fecha y guardia)
         y responde 200 con el resumen para cotejar la bolsa.
    GET  /api/guardia/resumen?sucursal_id=1
         Lo de hoy en la sucursal: validadas, por salir y las últimas validaciones.

  Respuestas de error (el campo "codigo" le dice a la pantalla qué mostrar):
    400 QR_INVALIDO     el QR no es de MARK'S o fue alterado (la firma no coincide)
    400 FOLIO_INVALIDO  el folio escrito no tiene el formato MK-AAMMDD-NNNNNN
    404 NO_EXISTE       no hay una compra con ese folio
    409 OTRA_SUCURSAL   la compra se pagó en otra sucursal
    409 YA_VALIDADA     el QR ya se usó (dice cuándo y quién lo validó)
    409 CANCELADA       la compra fue cancelada

  El QR va firmado con HMAC (utils/qr.py): no se puede inventar ni cambiar el folio.
  La validación es una actualización condicional (WHERE estado = 'PAGADA'),
  así el mismo QR no puede validarse dos veces aunque lo escaneen al mismo tiempo.
"""
from flask import Blueprint, g, jsonify, request

from ..db import get_db, query
from ..utils.qr import FOLIO_VALIDO, leer_qr
from ..utils.seguridad import requiere_rol
from .admin import _desfase_bd, _hora_mx, _inicio_periodo

bp = Blueprint("guardia", __name__)

ROLES = ("GUARDIA", "ADMIN")


def _error(mensaje, estado, codigo, **extra):
    return jsonify(error=mensaje, codigo=codigo, **extra), estado


def _sucursal(sucursal_id):
    return query("SELECT id, nombre FROM sucursales WHERE id = %s AND activa = 1",
                 (sucursal_id,), one=True)


def _cliente_corto(nombre, apellidos):
    """'Sabina' + 'Ortega Gonzalez' -> 'Sabina O.' (el guardia no necesita más)."""
    nombre = (nombre or "").strip().split(" ")[0] or "Cliente"
    inicial = (apellidos or "").strip()[:1]
    return f"{nombre} {inicial.upper()}." if inicial else nombre


def _venta(folio):
    return query("""SELECT v.id, v.folio, v.sucursal_id, s.nombre AS sucursal, v.estado,
                           v.articulos, v.total, v.pagada_en, v.validada_en,
                           u.nombre, u.apellidos,
                           CONCAT_WS(' ', gu.nombre, gu.apellidos) AS validada_por
                    FROM ventas v
                    JOIN sucursales s ON s.id = v.sucursal_id
                    JOIN usuarios u   ON u.id = v.usuario_id
                    LEFT JOIN usuarios gu ON gu.id = v.validada_por
                    WHERE v.folio = %s""", (folio,), one=True)


def _resumen_venta(v, desfase):
    productos = query("""SELECT nombre, cantidad, tipo_venta FROM venta_detalle
                         WHERE venta_id = %s ORDER BY id""", (v["id"],))
    return {
        "folio": v["folio"],
        "cliente": _cliente_corto(v["nombre"], v["apellidos"]),
        "sucursal": v["sucursal"],
        "articulos": v["articulos"],
        "total": v["total"],
        "pagada_en": _hora_mx(v["pagada_en"], desfase),
        "validada_en": _hora_mx(v["validada_en"], desfase),
        "validada_por": v["validada_por"] or None,
        "productos": productos,
    }


# ------------------------------------------------------------------
# VALIDAR LA SALIDA
# ------------------------------------------------------------------
@bp.post("/validar")
@requiere_rol(*ROLES)
def validar():
    d = request.get_json(silent=True) or {}
    try:
        sucursal = _sucursal(int(d.get("sucursal_id")))
    except (TypeError, ValueError):
        sucursal = None
    if not sucursal:
        return _error("Elige la sucursal donde estás", 400, "SUCURSAL")

    if d.get("qr"):
        folio = leer_qr(str(d["qr"]))
        if not folio:
            return _error("QR no válido: no es de MARK'S o fue alterado", 400, "QR_INVALIDO")
        forma = "QR"
    else:
        folio = str(d.get("folio") or "").strip().upper()
        if not FOLIO_VALIDO.match(folio):
            return _error("Escribe el folio completo, por ejemplo MK-261027-000001",
                          400, "FOLIO_INVALIDO")
        forma = "FOLIO"

    desfase = _desfase_bd()
    v = _venta(folio)
    if not v:
        return _error(f"No existe una compra con el folio {folio}", 404, "NO_EXISTE")
    if v["sucursal_id"] != sucursal["id"]:
        return _error(f"Esta compra se pagó en {v['sucursal']}, no en esta sucursal",
                      409, "OTRA_SUCURSAL", venta=_resumen_venta(v, desfase))
    if v["estado"] == "CANCELADA":
        return _error("Esta compra fue cancelada", 409, "CANCELADA",
                      venta=_resumen_venta(v, desfase))
    if v["estado"] == "VALIDADA":
        return _error("Este QR ya se usó: la compra ya salió de la tienda", 409, "YA_VALIDADA",
                      venta=_resumen_venta(v, desfase))

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE ventas SET estado = 'VALIDADA', validada_en = NOW(),
                                             validada_por = %s
                           WHERE id = %s AND estado = 'PAGADA'""", (g.usuario_id, v["id"]))
            cambiadas = cur.rowcount
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    v = _venta(folio)
    if not cambiadas:
        # Otro guardia la validó un instante antes
        return _error("Este QR ya se usó: la compra ya salió de la tienda", 409, "YA_VALIDADA",
                      venta=_resumen_venta(v, desfase))
    return jsonify(mensaje="Compra validada: puede salir", forma=forma,
                   venta=_resumen_venta(v, desfase))


# ------------------------------------------------------------------
# RESUMEN DE HOY EN LA SUCURSAL
# ------------------------------------------------------------------
@bp.get("/resumen")
@requiere_rol(*ROLES)
def resumen():
    sucursales = query("SELECT id, nombre FROM sucursales WHERE activa = 1 ORDER BY id")
    sucursal = _sucursal(request.args.get("sucursal_id", type=int) or 0) or \
        (sucursales[0] if sucursales else None)
    if not sucursal:
        return _error("No hay sucursales activas", 404, "SUCURSAL")

    desfase = _desfase_bd()
    hoy = _inicio_periodo("hoy", desfase)
    conteo = query("""SELECT COALESCE(SUM(estado = 'VALIDADA' AND validada_en >= %s), 0) AS validadas,
                             COALESCE(SUM(estado = 'PAGADA'), 0) AS por_salir
                      FROM ventas WHERE sucursal_id = %s""", (hoy, sucursal["id"]), one=True)
    ultimas = query("""SELECT v.folio, v.articulos, v.total, v.validada_en, u.nombre, u.apellidos
                       FROM ventas v JOIN usuarios u ON u.id = v.usuario_id
                       WHERE v.sucursal_id = %s AND v.estado = 'VALIDADA' AND v.validada_en >= %s
                       ORDER BY v.validada_en DESC LIMIT 15""", (sucursal["id"], hoy))

    return jsonify(
        sucursal=sucursal,
        sucursales=sucursales,
        validadas_hoy=int(conteo["validadas"]),
        por_salir=int(conteo["por_salir"]),
        ultimas=[{"folio": u["folio"], "articulos": u["articulos"], "total": u["total"],
                  "cliente": _cliente_corto(u["nombre"], u["apellidos"]),
                  "hora": (_hora_mx(u["validada_en"], desfase) or "")[11:]} for u in ultimas],
    )