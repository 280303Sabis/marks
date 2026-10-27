"""
Pruebas del PASO W11: moderación de opiniones en el portal del administrador.

Cómo correrlo:
    cd backend
    python probar_opiniones_admin.py

Crea un administrador, un cliente que opina (con una foto) y un cliente que
reporta. Prueba la lista de reportadas, ocultar, mostrar y marcar como revisada,
y revisa que la app deje de mostrar la opinión oculta.
Al final BORRA la opinión, la foto, los reportes y los usuarios de prueba.
"""
import os
import uuid

from PIL import Image
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREOS = ("prueba.admin.op@marks.test", "prueba.autor.op@marks.test",
           "prueba.reporta.op@marks.test")

app = create_app()
cliente = app.test_client()
CARPETA = app.config["UPLOADS_OPINIONES"]
resultados = []


def revisar(nombre, condicion, extra=""):
    condicion = bool(condicion)
    resultados.append(condicion)
    print(f"{'OK   ' if condicion else 'FALLA'} {len(resultados):>2}. {nombre}"
          + (f"  -> {extra}" if extra and not condicion else ""))


def ejecutar(sql, params=()):
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        nuevo_id = cur.lastrowid
    conn.commit()
    return nuevo_id


def limpiar():
    marcas = ",".join(["%s"] * len(CORREOS))
    for u in query(f"SELECT id FROM usuarios WHERE correo IN ({marcas})", CORREOS):
        for o in query("SELECT id FROM opiniones WHERE usuario_id = %s", (u["id"],)):
            for f in query("SELECT archivo FROM opinion_fotos WHERE opinion_id = %s", (o["id"],)):
                ruta = os.path.join(CARPETA, f["archivo"])
                if os.path.isfile(ruta):
                    os.remove(ruta)
            ejecutar("DELETE FROM opiniones WHERE id = %s", (o["id"],))   # fotos y reportes en cascada
        ejecutar("DELETE FROM reportes_opinion WHERE usuario_id = %s", (u["id"],))
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (u["id"],))
        ejecutar("UPDATE opiniones SET oculta_por = NULL WHERE oculta_por = %s", (u["id"],))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (u["id"],))


def crear_usuario(correo, rol_id, rol, nombre="Prueba", apellidos=None):
    uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash, rol_id,
                                            correo_verificado, acepto_privacidad_en,
                                            version_aviso_privacidad)
                      VALUES (%s, %s, %s, %s, %s, 1, NOW(), %s)""",
                   (nombre, apellidos, correo, generate_password_hash("sin-login"), rol_id,
                    app.config["AVISO_PRIVACIDAD_VERSION"]))
    return uid, {"Authorization": "Bearer " + crear_token({"id": uid, "rol": rol, "token_version": 1})}


with app.app_context():
    limpiar()
    producto = query("SELECT id FROM productos WHERE activo = 1 ORDER BY id LIMIT 1", one=True)["id"]
    try:
        _, ADMIN = crear_usuario(CORREOS[0], 2, "ADMIN")
        autor_id, AUTOR = crear_usuario(CORREOS[1], 1, "CLIENTE", "Autora", "Pruebas")
        reporta_id, REPORTA = crear_usuario(CORREOS[2], 1, "CLIENTE")

        # Opinión de 1 estrella con una foto (se crea directo en la base)
        opinion_id = ejecutar("""INSERT INTO opiniones (producto_id, usuario_id, estrellas, comentario)
                                 VALUES (%s, %s, 1, 'Comentario de prueba con groserías')""",
                              (producto, autor_id))
        os.makedirs(CARPETA, exist_ok=True)
        archivo = uuid.uuid4().hex + ".jpg"
        Image.new("RGB", (40, 30), (200, 80, 60)).save(os.path.join(CARPETA, archivo), "JPEG")
        ejecutar("""INSERT INTO opinion_fotos (opinion_id, archivo, ancho, alto, bytes)
                    VALUES (%s, %s, 40, 30, 1000)""", (opinion_id, archivo))

        # El otro cliente la reporta desde la app
        r = cliente.post(f"/api/opiniones/{opinion_id}/reportar", headers=REPORTA,
                         json={"motivo": "OFENSIVA"})
        revisar("Un cliente reporta la opinión desde la app", r.status_code in (200, 201), r.get_json())

        # ---------- Permisos ----------
        r = cliente.get("/api/admin/opiniones")
        revisar("Lista sin sesión: 401", r.status_code == 401, r.status_code)
        r = cliente.get("/api/admin/opiniones", headers=AUTOR)
        revisar("Lista con sesión de cliente: 403", r.status_code == 403, r.status_code)
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/ocultar", headers=AUTOR,
                         json={"motivo": "Yo misma"})
        revisar("Un cliente no puede ocultar opiniones: 403", r.status_code == 403, r.status_code)

        # ---------- Reportadas ----------
        r = cliente.get("/api/admin/opiniones", headers=ADMIN)
        d = r.get_json()
        o = next((x for x in d.get("opiniones", []) if x["id"] == opinion_id), None)
        revisar("Reportadas (filtro por defecto): aparece la opinión", r.status_code == 200 and o, d)
        revisar("Trae cliente completo, correo, motivo y 1 reporte pendiente",
                o and o["cliente"] == "Autora Pruebas" and o["correo"] == CORREOS[1]
                and o["reportes_pendientes"] == 1 and o["motivos"][0]["motivo"] == "Ofensiva", o)
        revisar("Trae la foto con la ruta del admin",
                o and len(o["fotos"]) == 1 and o["fotos"][0]["url"].startswith("/admin/opiniones/fotos/"), o)
        revisar("El resumen cuenta reportes pendientes",
                d["resumen"]["reportes_pendientes"] >= 1 and d["resumen"]["opiniones_reportadas"] >= 1,
                d["resumen"])
        r = cliente.get(f"/api/admin/opiniones?filtro=todas&estrellas=1&producto_id={producto}",
                        headers=ADMIN)
        revisar("Filtros de estrellas y producto",
                any(x["id"] == opinion_id for x in r.get_json()["opiniones"])
                and all(x["estrellas"] == 1 for x in r.get_json()["opiniones"]), r.get_json())
        r = cliente.get("/api/admin/opiniones?filtro=todas&buscar=groserías", headers=ADMIN)
        revisar("Buscar por texto del comentario",
                any(x["id"] == opinion_id for x in r.get_json()["opiniones"]), r.get_json())

        # ---------- Foto ----------
        url = "/api" + o["fotos"][0]["url"]
        r = cliente.get(url, headers=ADMIN)
        revisar("El admin ve la foto: 200 image/jpeg",
                r.status_code == 200 and r.mimetype == "image/jpeg", r.status_code)
        r = cliente.get(url)
        revisar("La foto del admin sin sesión: 401", r.status_code == 401, r.status_code)
        r = cliente.get("/api/admin/opiniones/fotos/../../app.py", headers=ADMIN)
        revisar("Nombre de archivo raro: 404", r.status_code == 404, r.status_code)

        # ---------- Ocultar ----------
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/ocultar", headers=ADMIN, json={"motivo": "x"})
        revisar("Ocultar sin motivo suficiente: 400", r.status_code == 400, r.get_json())
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/ocultar", headers=ADMIN,
                         json={"motivo": "Lenguaje ofensivo"})
        revisar("Ocultar con motivo: 200", r.status_code == 200, r.get_json())
        fila = query("""SELECT estado, motivo_oculta, oculta_por FROM opiniones WHERE id = %s""",
                     (opinion_id,), one=True)
        revisar("Quedó OCULTA con motivo y quién la ocultó",
                fila["estado"] == "OCULTA" and fila["motivo_oculta"] == "Lenguaje ofensivo"
                and fila["oculta_por"] is not None, fila)
        revisar("Sus reportes quedaron como revisados",
                not query("""SELECT 1 FROM reportes_opinion WHERE opinion_id = %s AND revisado = 0""",
                          (opinion_id,), one=True))
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/ocultar", headers=ADMIN,
                         json={"motivo": "Otra vez"})
        revisar("Ocultar una ya oculta: 409", r.status_code == 409, r.get_json())

        r = cliente.get(f"/api/productos/{producto}/opiniones", headers=REPORTA)
        revisar("La app ya no se la muestra a otros clientes",
                not any(x["id"] == opinion_id for x in r.get_json()["opiniones"]), r.get_json())
        r = cliente.get(f"/api/productos/{producto}/opiniones", headers=AUTOR)
        revisar("Su autora sí la sigue viendo como suya (OCULTA)",
                (r.get_json().get("mi_opinion") or {}).get("estado") == "OCULTA", r.get_json())
        r = cliente.get("/api/" + o["fotos"][0]["url"].replace("/admin/", "", 1))
        revisar("La foto pública de una opinión oculta: 404", r.status_code == 404, r.status_code)
        r = cliente.get("/api/admin/opiniones?filtro=ocultas", headers=ADMIN)
        oc = next((x for x in r.get_json()["opiniones"] if x["id"] == opinion_id), {})
        revisar("Filtro ocultas: aparece con motivo y quién la ocultó",
                oc.get("motivo_oculta") == "Lenguaje ofensivo" and oc.get("oculta_por"), oc)

        # ---------- Mostrar ----------
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/mostrar", headers=ADMIN)
        revisar("Volver a mostrar: 200", r.status_code == 200, r.get_json())
        fila = query("SELECT estado, motivo_oculta, oculta_por FROM opiniones WHERE id = %s",
                     (opinion_id,), one=True)
        revisar("Quedó PUBLICADA y sin motivo",
                fila["estado"] == "PUBLICADA" and fila["motivo_oculta"] is None
                and fila["oculta_por"] is None, fila)
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/mostrar", headers=ADMIN)
        revisar("Mostrar una ya publicada: 409", r.status_code == 409, r.get_json())

        # ---------- Revisar sin ocultar ----------
        ejecutar("UPDATE reportes_opinion SET revisado = 0 WHERE opinion_id = %s", (opinion_id,))
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/revisar", headers=ADMIN)
        revisar("Marcar reportes como revisados: 200 y sigue publicada",
                r.status_code == 200 and query("SELECT estado FROM opiniones WHERE id = %s",
                                               (opinion_id,), one=True)["estado"] == "PUBLICADA",
                r.get_json())
        r = cliente.get("/api/admin/opiniones", headers=ADMIN)
        revisar("Ya no sale en reportadas",
                not any(x["id"] == opinion_id for x in r.get_json()["opiniones"]), r.get_json())
        r = cliente.post(f"/api/admin/opiniones/{opinion_id}/revisar", headers=ADMIN)
        revisar("Revisar sin reportes pendientes: 409", r.status_code == 409, r.get_json())

        r = cliente.post("/api/admin/opiniones/999999/ocultar", headers=ADMIN, json={"motivo": "Prueba"})
        revisar("Opinión que no existe: 404", r.status_code == 404, r.status_code)

    finally:
        limpiar()

    revisar("Limpieza: no quedaron opiniones ni usuarios de prueba",
            not query("SELECT 1 FROM usuarios WHERE correo IN (%s, %s, %s)", CORREOS, one=True))

print(f"\n{sum(resultados)} de {len(resultados)} pruebas correctas")