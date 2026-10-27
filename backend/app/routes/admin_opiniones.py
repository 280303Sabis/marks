"""
ADMINISTRADOR (portal web) - Moderación de opiniones  (PASO W11)

  Solo usuarios con rol ADMIN:
    GET  /api/admin/opiniones?filtro=reportadas&producto_id=&estrellas=&buscar=
         filtro: reportadas (con reportes sin revisar, por defecto) | ocultas | todas
         Cada opinión trae el cliente, el producto, las fotos y sus reportes.
    POST /api/admin/opiniones/<id>/ocultar     {"motivo": "Lenguaje ofensivo"}
         La opinión deja de verse en la app (solo la ve su autor) y deja de
         contar en el promedio. Sus reportes quedan como revisados.
    POST /api/admin/opiniones/<id>/mostrar
         Vuelve a publicar una opinión oculta.
    POST /api/admin/opiniones/<id>/revisar
         Marca sus reportes como revisados y la deja publicada (no había problema).
    GET  /api/admin/opiniones/fotos/<archivo>
         Foto de cualquier opinión (también de las ocultas) para revisarla.
         La página la pide con el token y la muestra como imagen.
"""
import os

from flask import Blueprint, current_app, g, jsonify, request, send_from_directory

from ..db import get_db, query
from ..utils.fotos import NOMBRE_VALIDO
from ..utils.seguridad import requiere_rol
from .admin import _desfase_bd, _hora_mx

bp = Blueprint("admin_opiniones", __name__)

FILTROS = ("reportadas", "ocultas", "todas")
MOTIVOS_REPORTE = {
    "OFENSIVA": "Ofensiva",
    "SPAM": "Spam o publicidad",
    "FALSA": "Falsa o engañosa",
    "OTRO": "Otro",
}


def _error(mensaje, estado=400, **extra):
    return jsonify(error=mensaje, **extra), estado


def _opinion(opinion_id):
    return query("""SELECT o.id, o.estado, p.nombre AS producto
                    FROM opiniones o JOIN productos p ON p.id = o.producto_id
                    WHERE o.id = %s""", (opinion_id,), one=True)


def _ejecutar(sql, params):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            filas = cur.rowcount
        conn.commit()
        return filas
    except Exception:
        conn.rollback()
        raise


def _armar(filas, desfase):
    """Agrega fotos y reportes a cada opinión."""
    ids = [o["id"] for o in filas]
    fotos, reportes = {}, {}
    if ids:
        marcas = ",".join(["%s"] * len(ids))
        for f in query(f"""SELECT id, opinion_id, archivo FROM opinion_fotos
                           WHERE opinion_id IN ({marcas}) ORDER BY id""", tuple(ids)):
            fotos.setdefault(f["opinion_id"], []).append(
                {"id": f["id"], "url": f"/admin/opiniones/fotos/{f['archivo']}"})
        for r in query(f"""SELECT opinion_id, motivo, revisado, creado_en FROM reportes_opinion
                           WHERE opinion_id IN ({marcas}) ORDER BY creado_en DESC""", tuple(ids)):
            reportes.setdefault(r["opinion_id"], []).append({
                "motivo": r["motivo"],
                "motivo_texto": MOTIVOS_REPORTE.get(r["motivo"], r["motivo"]),
                "revisado": bool(r["revisado"]),
                "fecha": _hora_mx(r["creado_en"], desfase),
            })

    resultado = []
    for o in filas:
        lista = reportes.get(o["id"], [])
        pendientes = [r for r in lista if not r["revisado"]]
        motivos = {}
        for r in pendientes:
            motivos[r["motivo_texto"]] = motivos.get(r["motivo_texto"], 0) + 1
        resultado.append({
            "id": o["id"],
            "producto_id": o["producto_id"],
            "producto": o["producto"],
            "cliente": " ".join(x for x in (o["nombre"], o["apellidos"]) if x),
            "correo": o["correo"],
            "estrellas": o["estrellas"],
            "comentario": o["comentario"],
            "estado": o["estado"],
            "motivo_oculta": o["motivo_oculta"],
            "oculta_por": o["oculta_por_nombre"] or None,
            "creada_en": _hora_mx(o["creada_en"], desfase),
            "editada": o["editada_en"] is not None,
            "fotos": fotos.get(o["id"], []),
            "reportes_pendientes": len(pendientes),
            "reportes_total": len(lista),
            "motivos": [{"motivo": m, "veces": n} for m, n in motivos.items()],
        })
    return resultado


# ------------------------------------------------------------------
# LISTA DE OPINIONES
# ------------------------------------------------------------------
@bp.get("/opiniones")
@requiere_rol("ADMIN")
def opiniones():
    filtro = (request.args.get("filtro") or "reportadas").lower()
    if filtro not in FILTROS:
        filtro = "reportadas"

    condiciones, params = [], []
    if filtro == "reportadas":
        condiciones.append("""EXISTS (SELECT 1 FROM reportes_opinion r
                                      WHERE r.opinion_id = o.id AND r.revisado = 0)""")
    elif filtro == "ocultas":
        condiciones.append("o.estado = 'OCULTA'")

    producto_id = request.args.get("producto_id", type=int)
    if producto_id:
        condiciones.append("o.producto_id = %s")
        params.append(producto_id)
    estrellas = request.args.get("estrellas", type=int)
    if estrellas and 1 <= estrellas <= 5:
        condiciones.append("o.estrellas = %s")
        params.append(estrellas)
    buscar = (request.args.get("buscar") or "").strip()[:60]
    if buscar:
        condiciones.append("""(o.comentario LIKE %s OR u.correo LIKE %s
                               OR CONCAT_WS(' ', u.nombre, u.apellidos) LIKE %s)""")
        params += [f"%{buscar}%"] * 3

    where = ("WHERE " + " AND ".join(condiciones)) if condiciones else ""
    filas = query(f"""SELECT o.id, o.producto_id, p.nombre AS producto, o.estrellas, o.comentario,
                             o.estado, o.motivo_oculta, o.creada_en, o.editada_en,
                             u.nombre, u.apellidos, u.correo,
                             CONCAT_WS(' ', a.nombre, a.apellidos) AS oculta_por_nombre,
                             (SELECT COUNT(*) FROM reportes_opinion r
                              WHERE r.opinion_id = o.id AND r.revisado = 0) AS pendientes
                      FROM opiniones o
                      JOIN productos p ON p.id = o.producto_id
                      JOIN usuarios u  ON u.id = o.usuario_id
                      LEFT JOIN usuarios a ON a.id = o.oculta_por
                      {where}
                      ORDER BY pendientes DESC, o.creada_en DESC, o.id DESC
                      LIMIT 300""", params)

    resumen = query("""SELECT COUNT(*) AS total,
                              COALESCE(SUM(estado = 'PUBLICADA'), 0) AS publicadas,
                              COALESCE(SUM(estado = 'OCULTA'), 0) AS ocultas,
                              ROUND(AVG(CASE WHEN estado = 'PUBLICADA' THEN estrellas END), 1)
                                  AS promedio
                       FROM opiniones""", one=True)
    reportes = query("""SELECT COUNT(*) AS pendientes, COUNT(DISTINCT opinion_id) AS opiniones
                        FROM reportes_opinion WHERE revisado = 0""", one=True)

    return jsonify(
        filtro=filtro,
        resumen={
            "total": int(resumen["total"]),
            "publicadas": int(resumen["publicadas"]),
            "ocultas": int(resumen["ocultas"]),
            "promedio": float(resumen["promedio"] or 0),
            "reportes_pendientes": int(reportes["pendientes"]),
            "opiniones_reportadas": int(reportes["opiniones"]),
        },
        productos=query("""SELECT DISTINCT p.id, p.nombre FROM productos p
                           JOIN opiniones o ON o.producto_id = p.id ORDER BY p.nombre"""),
        opiniones=_armar(filas, _desfase_bd()),
        limite=len(filas) == 300,
    )


# ------------------------------------------------------------------
# OCULTAR, MOSTRAR Y MARCAR COMO REVISADA
# ------------------------------------------------------------------
@bp.post("/opiniones/<int:opinion_id>/ocultar")
@requiere_rol("ADMIN")
def ocultar(opinion_id):
    o = _opinion(opinion_id)
    if not o:
        return _error("Opinión no encontrada", 404)
    if o["estado"] == "OCULTA":
        return _error("Esta opinión ya está oculta", 409)
    d = request.get_json(silent=True) or {}
    motivo = " ".join(str(d.get("motivo") or "").split())
    if not 3 <= len(motivo) <= 200:
        return _error("Escribe el motivo para ocultarla (de 3 a 200 caracteres)")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE opiniones SET estado = 'OCULTA', motivo_oculta = %s,
                                                oculta_por = %s
                           WHERE id = %s""", (motivo, g.usuario_id, opinion_id))
            cur.execute("UPDATE reportes_opinion SET revisado = 1 WHERE opinion_id = %s",
                        (opinion_id,))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return jsonify(mensaje=f"Opinión ocultada ({o['producto']})")


@bp.post("/opiniones/<int:opinion_id>/mostrar")
@requiere_rol("ADMIN")
def mostrar(opinion_id):
    o = _opinion(opinion_id)
    if not o:
        return _error("Opinión no encontrada", 404)
    if o["estado"] == "PUBLICADA":
        return _error("Esta opinión ya está publicada", 409)
    _ejecutar("""UPDATE opiniones SET estado = 'PUBLICADA', motivo_oculta = NULL,
                                      oculta_por = NULL
                 WHERE id = %s""", (opinion_id,))
    return jsonify(mensaje=f"Opinión publicada de nuevo ({o['producto']})")


@bp.post("/opiniones/<int:opinion_id>/revisar")
@requiere_rol("ADMIN")
def revisar(opinion_id):
    o = _opinion(opinion_id)
    if not o:
        return _error("Opinión no encontrada", 404)
    marcados = _ejecutar("""UPDATE reportes_opinion SET revisado = 1
                            WHERE opinion_id = %s AND revisado = 0""", (opinion_id,))
    if not marcados:
        return _error("Esta opinión no tiene reportes pendientes", 409)
    return jsonify(mensaje=f"Reportes revisados: la opinión sigue publicada ({o['producto']})",
                   revisados=marcados)


# ------------------------------------------------------------------
# FOTOS (también de opiniones ocultas, solo para el admin)
# ------------------------------------------------------------------
@bp.get("/opiniones/fotos/<archivo>")
@requiere_rol("ADMIN")
def foto(archivo):
    carpeta = current_app.config["UPLOADS_OPINIONES"]
    if not NOMBRE_VALIDO.match(archivo):
        return _error("Foto no encontrada", 404)
    existe = query("SELECT 1 FROM opinion_fotos WHERE archivo = %s", (archivo,), one=True)
    if not existe or not os.path.isfile(os.path.join(carpeta, archivo)):
        return _error("Foto no encontrada", 404)
    respuesta = send_from_directory(carpeta, archivo, mimetype="image/jpeg")
    respuesta.headers["Cache-Control"] = "private, max-age=3600"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta