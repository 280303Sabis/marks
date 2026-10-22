"""
CALIFICACIONES Y OPINIONES (PASO 13)

  Requieren sesión:
    GET    /api/productos/<id>/opiniones        resumen (promedio) y opiniones de un producto
  Solo clientes:
    POST   /api/productos/<id>/opiniones        opinar (formulario con estrellas, comentario y fotos)
    PUT    /api/opiniones/<id>                  editar mi opinión
    DELETE /api/opiniones/<id>                  borrar mi opinión (y sus fotos)
    POST   /api/opiniones/<id>/reportar         {"motivo": "OFENSIVA|SPAM|FALSA|OTRO"}
    GET    /api/opiniones/mias                  Mis opiniones: pendientes y publicadas
  Público:
    GET    /api/opiniones/fotos/<archivo>       foto de una opinión publicada

  Reglas:
    - 1 a 5 estrellas; comentario opcional de hasta 500 caracteres; hasta 3 fotos.
    - Solo opina quien compró el producto (compra PAGADA o VALIDADA).
    - Una opinión por producto por cliente (se puede editar o borrar).
    - Se publica de inmediato; el admin puede ocultarla (en la web).
    - Si el admin apagó las opiniones del producto, no se puede opinar.
    - Los reportes solo avisan al admin: la opinión sigue visible.
    - Se muestra el nombre y la inicial del apellido (ej. "Sabina O.").

  Opinar y editar se mandan como multipart/form-data (porque llevan fotos):
    estrellas=5
    comentario=Muy rico
    fotos=<archivo>  (se puede repetir hasta 3 veces)
    conservar=12,15  (solo al editar: ids de las fotos que se quedan)
"""
import os

from flask import Blueprint, current_app, g, jsonify, request, send_from_directory

from ..db import get_db, query
from ..utils.fotos import (MAX_FOTOS, NOMBRE_VALIDO, FotoInvalida, borrar_fotos,
                           guardar_foto)
from ..utils.seguridad import requiere_rol

bp = Blueprint("opiniones", __name__)

MAX_COMENTARIO = 500
MOTIVOS = {"OFENSIVA", "SPAM", "FALSA", "OTRO"}


class OpinionInvalida(ValueError):
    """Datos de la opinión que no cumplen las reglas."""


# ------------------------------------------------------------------
# Ayudantes
# ------------------------------------------------------------------
def _carpeta():
    return current_app.config["UPLOADS_OPINIONES"]


def _url_foto(archivo):
    return f"/api/opiniones/fotos/{archivo}"


def _autor(nombre, apellidos):
    """'Sabina' + 'Ortega González' -> 'Sabina O.'"""
    nombre = (nombre or "").strip().split(" ")[0] or "Cliente"
    inicial = (apellidos or "").strip()[:1]
    return f"{nombre} {inicial.upper()}." if inicial else nombre


def _producto(producto_id):
    return query("""SELECT id, nombre, activo, opiniones_activas
                    FROM productos WHERE id = %s""", (producto_id,), one=True)


def _lo_compro(producto_id, usuario_id):
    return query("""SELECT 1 FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
                    WHERE d.producto_id = %s AND v.usuario_id = %s
                      AND v.estado IN ('PAGADA', 'VALIDADA')
                    LIMIT 1""", (producto_id, usuario_id), one=True) is not None


def _fotos_de(opinion_ids):
    """{opinion_id: [ {id, url, ancho, alto}, ... ]}"""
    if not opinion_ids:
        return {}
    marcas = ",".join(["%s"] * len(opinion_ids))
    filas = query(f"""SELECT id, opinion_id, archivo, ancho, alto FROM opinion_fotos
                      WHERE opinion_id IN ({marcas}) ORDER BY id""", tuple(opinion_ids))
    resultado = {}
    for f in filas:
        resultado.setdefault(f["opinion_id"], []).append(
            {"id": f["id"], "url": _url_foto(f["archivo"]), "ancho": f["ancho"], "alto": f["alto"]})
    return resultado


def _armar(filas):
    """Convierte filas de la base en opiniones listas para la app."""
    fotos = _fotos_de([o["id"] for o in filas])
    return [{
        "id": o["id"],
        "producto_id": o["producto_id"],
        "autor": _autor(o["nombre"], o["apellidos"]),
        "estrellas": o["estrellas"],
        "comentario": o["comentario"],
        "estado": o["estado"],
        "creada_en": o["creada_en"],
        "editada": o["editada_en"] is not None,
        "es_mia": o["usuario_id"] == g.usuario_id,
        "fotos": fotos.get(o["id"], []),
    } for o in filas]


SELECT_OPINION = """SELECT o.id, o.producto_id, o.usuario_id, o.estrellas, o.comentario,
                           o.estado, o.creada_en, o.editada_en, u.nombre, u.apellidos
                    FROM opiniones o JOIN usuarios u ON u.id = o.usuario_id"""


def _leer_formulario():
    """Valida estrellas y comentario. Devuelve (estrellas, comentario)."""
    try:
        estrellas = int(request.form.get("estrellas", ""))
    except ValueError:
        raise OpinionInvalida("Elige de 1 a 5 estrellas")
    if not 1 <= estrellas <= 5:
        raise OpinionInvalida("Elige de 1 a 5 estrellas")
    comentario = (request.form.get("comentario") or "").strip()
    if len(comentario) > MAX_COMENTARIO:
        raise OpinionInvalida(f"El comentario puede tener máximo {MAX_COMENTARIO} caracteres")
    return estrellas, (comentario or None)


def _fotos_nuevas():
    """Los archivos que vienen en el formulario (campo 'fotos')."""
    return [f for f in request.files.getlist("fotos") if f and f.filename]


def _guardar_fotos(cur, opinion_id, archivos):
    """Guarda los archivos y sus registros. Si algo falla, borra lo que ya guardó."""
    guardadas = []
    try:
        for archivo in archivos:
            datos = guardar_foto(archivo, _carpeta())
            guardadas.append(datos["archivo"])
            cur.execute("""INSERT INTO opinion_fotos (opinion_id, archivo, ancho, alto, bytes)
                           VALUES (%s, %s, %s, %s, %s)""",
                        (opinion_id, datos["archivo"], datos["ancho"], datos["alto"],
                         datos["bytes"]))
    except Exception:
        borrar_fotos(_carpeta(), guardadas)
        raise
    return guardadas


def _mi_opinion_de_producto(producto_id):
    return query("SELECT id FROM opiniones WHERE producto_id = %s AND usuario_id = %s",
                 (producto_id, g.usuario_id), one=True)


def _mi_opinion(opinion_id):
    return query("SELECT id, usuario_id, producto_id FROM opiniones WHERE id = %s",
                 (opinion_id,), one=True)


# ------------------------------------------------------------------
# GET /api/productos/<id>/opiniones
#   ?limite=20   cuántas opiniones devolver (1 a 50), de la más nueva a la más vieja
# ------------------------------------------------------------------
@bp.get("/productos/<int:producto_id>/opiniones")
@requiere_rol()
def opiniones_producto(producto_id):
    p = _producto(producto_id)
    if not p or not p["activo"]:
        return jsonify(error="Producto no encontrado"), 404
    limite = request.args.get("limite", default=20, type=int)
    if limite is None or not 1 <= limite <= 50:
        return jsonify(error="El límite debe ser de 1 a 50"), 400

    resumen = query("""SELECT COUNT(*) AS total, ROUND(AVG(estrellas), 1) AS promedio,
                              SUM(estrellas = 5) AS e5, SUM(estrellas = 4) AS e4,
                              SUM(estrellas = 3) AS e3, SUM(estrellas = 2) AS e2,
                              SUM(estrellas = 1) AS e1
                       FROM opiniones WHERE producto_id = %s AND estado = 'PUBLICADA'""",
                    (producto_id,), one=True)
    publicadas = query(f"""{SELECT_OPINION}
                           WHERE o.producto_id = %s AND o.estado = 'PUBLICADA'
                           ORDER BY o.creada_en DESC, o.id DESC LIMIT %s""",
                       (producto_id, limite))
    mia = query(f"{SELECT_OPINION} WHERE o.producto_id = %s AND o.usuario_id = %s",
                (producto_id, g.usuario_id), one=True)

    es_cliente = g.rol == "CLIENTE"
    return jsonify(
        producto_id=producto_id,
        producto=p["nombre"],
        activas=bool(p["opiniones_activas"]),
        resumen={
            "total": int(resumen["total"] or 0),
            "promedio": float(resumen["promedio"] or 0),
            "por_estrellas": {str(n): int(resumen[f"e{n}"] or 0) for n in range(5, 0, -1)},
        },
        opiniones=_armar(publicadas),
        mi_opinion=_armar([mia])[0] if mia else None,   # aunque el admin la haya ocultado
        puede_opinar=(es_cliente and bool(p["opiniones_activas"]) and mia is None
                      and _lo_compro(producto_id, g.usuario_id)),
    )


# ------------------------------------------------------------------
# POST /api/productos/<id>/opiniones   (opinar)
# ------------------------------------------------------------------
@bp.post("/productos/<int:producto_id>/opiniones")
@requiere_rol("CLIENTE")
def opinar(producto_id):
    p = _producto(producto_id)
    if not p or not p["activo"]:
        return jsonify(error="Producto no encontrado"), 404
    if not p["opiniones_activas"]:
        return jsonify(error="Las opiniones de este producto están desactivadas"), 403
    if not _lo_compro(producto_id, g.usuario_id):
        return jsonify(error="Solo puedes opinar sobre productos que compraste"), 403
    if _mi_opinion_de_producto(producto_id):
        return jsonify(error="Ya opinaste sobre este producto. Puedes editar tu opinión",
                       codigo="YA_OPINASTE"), 409

    try:
        estrellas, comentario = _leer_formulario()
        archivos = _fotos_nuevas()
        if len(archivos) > MAX_FOTOS:
            raise OpinionInvalida(f"Puedes subir máximo {MAX_FOTOS} fotos")
    except OpinionInvalida as e:
        return jsonify(error=str(e)), 400

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO opiniones (producto_id, usuario_id, estrellas, comentario)
                           VALUES (%s, %s, %s, %s)""",
                        (producto_id, g.usuario_id, estrellas, comentario))
            opinion_id = cur.lastrowid
            guardadas = _guardar_fotos(cur, opinion_id, archivos)
        conn.commit()
    except FotoInvalida as e:
        conn.rollback()
        return jsonify(error=str(e)), 400
    except Exception:
        conn.rollback()
        raise

    opinion = query(f"{SELECT_OPINION} WHERE o.id = %s", (opinion_id,), one=True)
    return jsonify(mensaje="Gracias por tu opinión", opinion=_armar([opinion])[0],
                   fotos_guardadas=len(guardadas)), 201


# ------------------------------------------------------------------
# PUT /api/opiniones/<id>   (editar mi opinión)
# ------------------------------------------------------------------
@bp.put("/opiniones/<int:opinion_id>")
@requiere_rol("CLIENTE")
def editar_opinion(opinion_id):
    o = _mi_opinion(opinion_id)
    if not o or o["usuario_id"] != g.usuario_id:   # no existe o es de otro: misma respuesta
        return jsonify(error="No encontramos esa opinión"), 404

    try:
        estrellas, comentario = _leer_formulario()
        actuales = query("SELECT id, archivo FROM opinion_fotos WHERE opinion_id = %s",
                         (opinion_id,))
        texto = request.form.get("conservar", "")
        try:
            conservar = {int(x) for x in texto.split(",") if x.strip()}
        except ValueError:
            raise OpinionInvalida("Las fotos a conservar no son válidas")
        quitar = [f for f in actuales if f["id"] not in conservar]
        archivos = _fotos_nuevas()
        if len(actuales) - len(quitar) + len(archivos) > MAX_FOTOS:
            raise OpinionInvalida(f"Puedes tener máximo {MAX_FOTOS} fotos")
    except OpinionInvalida as e:
        return jsonify(error=str(e)), 400

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE opiniones SET estrellas = %s, comentario = %s, editada_en = NOW()
                           WHERE id = %s""", (estrellas, comentario, opinion_id))
            for f in quitar:
                cur.execute("DELETE FROM opinion_fotos WHERE id = %s", (f["id"],))
            _guardar_fotos(cur, opinion_id, archivos)
        conn.commit()
    except FotoInvalida as e:
        conn.rollback()
        return jsonify(error=str(e)), 400
    except Exception:
        conn.rollback()
        raise
    # Los archivos viejos se borran hasta que la base ya quedó guardada
    borrar_fotos(_carpeta(), [f["archivo"] for f in quitar])

    opinion = query(f"{SELECT_OPINION} WHERE o.id = %s", (opinion_id,), one=True)
    return jsonify(mensaje="Tu opinión se actualizó", opinion=_armar([opinion])[0])


# ------------------------------------------------------------------
# DELETE /api/opiniones/<id>   (borrar mi opinión)
# ------------------------------------------------------------------
@bp.delete("/opiniones/<int:opinion_id>")
@requiere_rol("CLIENTE")
def borrar_opinion(opinion_id):
    o = _mi_opinion(opinion_id)
    if not o or o["usuario_id"] != g.usuario_id:
        return jsonify(error="No encontramos esa opinión"), 404

    archivos = [f["archivo"] for f in query(
        "SELECT archivo FROM opinion_fotos WHERE opinion_id = %s", (opinion_id,))]
    conn = get_db()
    with conn.cursor() as cur:
        # opinion_fotos y reportes_opinion se borran solos (ON DELETE CASCADE)
        cur.execute("DELETE FROM opiniones WHERE id = %s", (opinion_id,))
    conn.commit()
    borrar_fotos(_carpeta(), archivos)
    return jsonify(mensaje="Tu opinión se borró")


# ------------------------------------------------------------------
# POST /api/opiniones/<id>/reportar
# ------------------------------------------------------------------
@bp.post("/opiniones/<int:opinion_id>/reportar")
@requiere_rol("CLIENTE")
def reportar(opinion_id):
    motivo = str((request.get_json(silent=True) or {}).get("motivo", "")).upper()
    if motivo not in MOTIVOS:
        return jsonify(error="Elige un motivo válido"), 400
    o = query("SELECT usuario_id, estado FROM opiniones WHERE id = %s", (opinion_id,), one=True)
    if not o or o["estado"] != "PUBLICADA":
        return jsonify(error="No encontramos esa opinión"), 404
    if o["usuario_id"] == g.usuario_id:
        return jsonify(error="No puedes reportar tu propia opinión"), 400
    if query("SELECT 1 FROM reportes_opinion WHERE opinion_id = %s AND usuario_id = %s",
             (opinion_id, g.usuario_id), one=True):
        return jsonify(error="Ya reportaste esta opinión", codigo="YA_REPORTADA"), 409

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""INSERT INTO reportes_opinion (opinion_id, usuario_id, motivo)
                       VALUES (%s, %s, %s)""", (opinion_id, g.usuario_id, motivo))
    conn.commit()
    return jsonify(mensaje="Gracias. Revisaremos esta opinión"), 201


# ------------------------------------------------------------------
# GET /api/opiniones/mias   (Mis opiniones)
# ------------------------------------------------------------------
@bp.get("/opiniones/mias")
@requiere_rol("CLIENTE")
def mis_opiniones():
    # Pendientes: productos que compré y todavía no califico
    pendientes = query("""SELECT d.producto_id, p.nombre, MAX(v.pagada_en) AS comprado_en
                          FROM venta_detalle d
                          JOIN ventas v    ON v.id = d.venta_id
                          JOIN productos p ON p.id = d.producto_id
                          LEFT JOIN opiniones o ON o.producto_id = d.producto_id
                                               AND o.usuario_id = v.usuario_id
                          WHERE v.usuario_id = %s AND v.estado IN ('PAGADA', 'VALIDADA')
                            AND o.id IS NULL AND p.activo = 1 AND p.opiniones_activas = 1
                          GROUP BY d.producto_id, p.nombre
                          ORDER BY comprado_en DESC""", (g.usuario_id,))
    hechas = query(f"""SELECT o.id, o.producto_id, o.usuario_id, o.estrellas, o.comentario,
                              o.estado, o.creada_en, o.editada_en, u.nombre, u.apellidos,
                              p.nombre AS producto
                       FROM opiniones o
                       JOIN usuarios u  ON u.id = o.usuario_id
                       JOIN productos p ON p.id = o.producto_id
                       WHERE o.usuario_id = %s
                       ORDER BY COALESCE(o.editada_en, o.creada_en) DESC""", (g.usuario_id,))
    publicadas = _armar(hechas)
    for opinion, fila in zip(publicadas, hechas):
        opinion["producto"] = fila["producto"]
    return jsonify(pendientes=pendientes, publicadas=publicadas)


# ------------------------------------------------------------------
# GET /api/opiniones/fotos/<archivo>   (público; solo de opiniones publicadas)
# ------------------------------------------------------------------
@bp.get("/opiniones/fotos/<archivo>")
def ver_foto(archivo):
    if not NOMBRE_VALIDO.match(archivo):
        return jsonify(error="Foto no encontrada"), 404
    existe = query("""SELECT 1 FROM opinion_fotos f JOIN opiniones o ON o.id = f.opinion_id
                      WHERE f.archivo = %s AND o.estado = 'PUBLICADA'""", (archivo,), one=True)
    if not existe or not os.path.isfile(os.path.join(_carpeta(), archivo)):
        return jsonify(error="Foto no encontrada"), 404
    respuesta = send_from_directory(_carpeta(), archivo, mimetype="image/jpeg")
    respuesta.headers["Cache-Control"] = "public, max-age=86400"
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta