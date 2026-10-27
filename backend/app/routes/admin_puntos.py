"""
ADMINISTRADOR (portal web) - Puntos de los clientes  (PASO W13)

  Solo usuarios con rol ADMIN:
    GET  /api/admin/clientes?buscar=&orden=
         Clientes con su saldo de puntos, compras y última compra.
         orden: puntos (más puntos primero, por defecto) | recientes | nombre
    GET  /api/admin/clientes/<id>/puntos
         Datos del cliente y su estado de cuenta (últimos 50 movimientos).
    POST /api/admin/clientes/<id>/puntos     {"puntos": 50, "motivo": "Compensación por ..."}
         Ajuste manual: puntos positivos SUMAN, negativos RESTAN.
         El saldo nunca queda en negativo. Se guarda como movimiento AJUSTE
         y el cliente lo ve en "Mis puntos" de la app con el motivo.

  Reglas:
    - Solo a cuentas de CLIENTE activas.
    - De 1 a 5,000 puntos por ajuste (para evitar errores de dedo).
    - El motivo es obligatorio (5 a 150 letras): el cliente lo ve.
"""
from flask import Blueprint, jsonify, request

from ..db import get_db, query
from ..utils.seguridad import requiere_rol
from .admin import _desfase_bd, _hora_mx

bp = Blueprint("admin_puntos", __name__)

MAX_AJUSTE = 5000
MOTIVO_MIN, MOTIVO_MAX = 5, 150
ORDENES = {
    "puntos": "u.puntos_saldo DESC, u.id DESC",
    "recientes": "ultima_compra IS NULL, ultima_compra DESC, u.id DESC",
    "nombre": "u.nombre, u.apellidos, u.id",
}
TIPOS = {"GANADOS": "Ganados en compra", "CANJEADOS": "Usados en compra", "AJUSTE": "Ajuste manual"}


def _error(mensaje, estado=400, **extra):
    return jsonify(error=mensaje, **extra), estado


def _nombre(u):
    return " ".join(p for p in (u["nombre"], u.get("apellidos")) if p)


def _cliente(cliente_id):
    return query("""SELECT id, nombre, apellidos, correo, puntos_saldo, activo, creado_en
                    FROM usuarios WHERE id = %s AND rol_id = 1""", (cliente_id,), one=True)


# ------------------------------------------------------------------
# GET /api/admin/clientes
# ------------------------------------------------------------------
@bp.get("/clientes")
@requiere_rol("ADMIN")
def lista_clientes():
    buscar = (request.args.get("buscar") or "").strip()[:80]
    orden = request.args.get("orden", "puntos")
    if orden not in ORDENES:
        orden = "puntos"

    filtro, params = "", []
    if buscar:
        filtro = " AND (u.nombre LIKE %s OR u.apellidos LIKE %s OR u.correo LIKE %s)"
        params = [f"%{buscar}%"] * 3

    desfase = _desfase_bd()
    filas = query(f"""SELECT u.id, u.nombre, u.apellidos, u.correo, u.puntos_saldo, u.activo,
                             COUNT(v.id) AS compras, MAX(v.pagada_en) AS ultima_compra
                      FROM usuarios u
                      LEFT JOIN ventas v ON v.usuario_id = u.id AND v.estado <> 'CANCELADA'
                      WHERE u.rol_id = 1 {filtro}
                      GROUP BY u.id
                      ORDER BY {ORDENES[orden]}
                      LIMIT 100""", tuple(params))
    clientes = [{
        "id": f["id"],
        "nombre": _nombre(f),
        "correo": f["correo"],
        "puntos": int(f["puntos_saldo"]),
        "activo": bool(f["activo"]),
        "compras": int(f["compras"]),
        "ultima_compra": _hora_mx(f["ultima_compra"], desfase),
    } for f in filas]

    r = query("""SELECT COUNT(*) AS clientes,
                        COALESCE(SUM(puntos_saldo), 0) AS puntos,
                        SUM(puntos_saldo > 0) AS con_puntos
                 FROM usuarios WHERE rol_id = 1 AND activo = 1""", one=True)
    a = query("""SELECT COUNT(*) AS ajustes, COALESCE(SUM(puntos), 0) AS neto
                 FROM movimientos_puntos
                 WHERE tipo = 'AJUSTE' AND fecha >= NOW() - INTERVAL 30 DAY""", one=True)
    return jsonify(
        clientes=clientes,
        orden=orden,
        resumen={
            "clientes": int(r["clientes"]),
            "puntos_en_circulacion": int(r["puntos"]),
            "valor_en_pesos": int(r["puntos"]) // 100 * 10,   # 100 puntos = $10
            "con_puntos": int(r["con_puntos"] or 0),
            "ajustes_30_dias": int(a["ajustes"]),
            "ajustes_neto_30_dias": int(a["neto"]),
        },
    )


# ------------------------------------------------------------------
# GET /api/admin/clientes/<id>/puntos
# ------------------------------------------------------------------
@bp.get("/clientes/<int:cliente_id>/puntos")
@requiere_rol("ADMIN")
def puntos_cliente(cliente_id):
    c = _cliente(cliente_id)
    if not c:
        return _error("Cliente no encontrado", 404)
    desfase = _desfase_bd()
    movimientos = query("""SELECT m.id, m.tipo, m.puntos, m.saldo_final, m.nota, m.fecha, v.folio
                           FROM movimientos_puntos m
                           LEFT JOIN ventas v ON v.id = m.venta_id
                           WHERE m.usuario_id = %s
                           ORDER BY m.id DESC
                           LIMIT 50""", (cliente_id,))
    return jsonify(
        cliente={"id": c["id"], "nombre": _nombre(c), "correo": c["correo"],
                 "puntos": int(c["puntos_saldo"]), "activo": bool(c["activo"]),
                 "cliente_desde": _hora_mx(c["creado_en"], desfase)},
        movimientos=[{
            "id": m["id"],
            "tipo": m["tipo"],
            "tipo_texto": TIPOS.get(m["tipo"], m["tipo"]),
            "puntos": int(m["puntos"]),
            "saldo_final": int(m["saldo_final"]),
            "nota": m["nota"] or "",
            "folio": m["folio"],
            "fecha": _hora_mx(m["fecha"], desfase),
        } for m in movimientos],
    )


# ------------------------------------------------------------------
# POST /api/admin/clientes/<id>/puntos   (ajuste manual)
# ------------------------------------------------------------------
@bp.post("/clientes/<int:cliente_id>/puntos")
@requiere_rol("ADMIN")
def ajustar_puntos(cliente_id):
    datos = request.get_json(silent=True) or {}
    puntos = datos.get("puntos")
    motivo = " ".join(str(datos.get("motivo") or "").split())

    if isinstance(puntos, bool) or not isinstance(puntos, int):
        return _error("Escribe una cantidad de puntos (número entero)")
    if puntos == 0 or abs(puntos) > MAX_AJUSTE:
        return _error(f"La cantidad debe ser de 1 a {MAX_AJUSTE:,} puntos (para sumar o restar)")
    if not MOTIVO_MIN <= len(motivo) <= MOTIVO_MAX:
        return _error(f"Escribe el motivo ({MOTIVO_MIN} a {MOTIVO_MAX} letras). El cliente lo verá en su app")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Se bloquea la fila del cliente: si al mismo tiempo paga en la app,
            # uno espera al otro y el saldo no se descuadra.
            cur.execute("""SELECT id, nombre, apellidos, puntos_saldo, activo FROM usuarios
                           WHERE id = %s AND rol_id = 1 FOR UPDATE""", (cliente_id,))
            c = cur.fetchone()
            if not c:
                conn.rollback()
                return _error("Cliente no encontrado", 404)
            if not c["activo"]:
                conn.rollback()
                return _error("La cuenta de este cliente está desactivada", 409, codigo="CUENTA_INACTIVA")

            saldo = int(c["puntos_saldo"])
            nuevo = saldo + puntos
            if nuevo < 0:
                conn.rollback()
                return _error(f"El cliente solo tiene {saldo:,} puntos; no se le pueden quitar {-puntos:,}",
                              409, codigo="SALDO_INSUFICIENTE", saldo=saldo)

            cur.execute("UPDATE usuarios SET puntos_saldo = %s WHERE id = %s", (nuevo, cliente_id))
            cur.execute("""INSERT INTO movimientos_puntos (usuario_id, venta_id, tipo, puntos, saldo_final, nota)
                           VALUES (%s, NULL, 'AJUSTE', %s, %s, %s)""",
                        (cliente_id, puntos, nuevo, motivo))
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    accion = f"Se sumaron {puntos:,}" if puntos > 0 else f"Se quitaron {-puntos:,}"
    return jsonify(
        mensaje=f"{accion} puntos a {_nombre(c)}. Saldo nuevo: {nuevo:,} puntos",
        saldo_anterior=saldo,
        saldo=nuevo,
    )