"""
Pruebas del PASO 13: calificaciones, opiniones y fotos.

Cómo correrlo:
    cd backend
    python probar_opiniones.py

Crea tres clientes de prueba, hace compras reales en la sucursal 1,
opina con fotos, edita, reporta y borra. Al final BORRA todo lo que creó
(incluidas las fotos de la carpeta uploads) y DEVUELVE el stock.
"""
import os
import uuid
from io import BytesIO

from PIL import Image
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREOS = ["prueba.opina1@marks.test", "prueba.opina2@marks.test", "prueba.opina3@marks.test"]
PASSWORD_B = "Prueba#2026x"
SUCURSAL = 1
LECHE, CAFE = 1, 4
COD_LECHE, COD_CAFE = "7501000000012", "7501000000043"

app = create_app()
cliente = app.test_client()
CARPETA = app.config["UPLOADS_OPINIONES"]
resultados = []
ids_prueba = []


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


def stock(producto_id):
    return query("SELECT stock FROM inventario WHERE producto_id = %s AND sucursal_id = %s",
                 (producto_id, SUCURSAL), one=True)["stock"]


def crear_cliente(correo, password="sin-login"):
    uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash,
                                            rol_id, correo_verificado)
                      VALUES ('Prueba', 'Opina Test', %s, %s, 1, 1)""",
                   (correo, generate_password_hash(password)))
    ids_prueba.append(uid)
    token = crear_token({"id": uid, "rol": "CLIENTE", "token_version": 1})
    return uid, {"Authorization": f"Bearer {token}"}


def comprar(H, lineas):
    carrito = {"sucursal_id": SUCURSAL, "lineas": lineas}
    cot = cliente.post("/api/carrito/cotizar", json=carrito, headers=H).get_json()
    r = cliente.post("/api/compras/pagar", headers=H, json=dict(
        carrito, total_esperado=cot["total"], clave_pago=str(uuid.uuid4()),
        tarjeta={"marca": "VISA", "ultimos4": "4242"}))
    return r.get_json()["venta"]["folio"]


def imagen(formato="JPEG", ancho=4000, alto=3000, girada=False):
    """Crea una foto en memoria. 'girada' simula un celular (EXIF de orientación + marca)."""
    img = Image.new("RGBA" if formato == "PNG" else "RGB", (ancho, alto), (120, 180, 90, 255))
    buf = BytesIO()
    if girada:
        exif = Image.Exif()
        exif[0x0112] = 6                 # orientación: girar 90°
        exif[0x010F] = "CamaraDePrueba"  # marca de la cámara (metadato)
        img.save(buf, formato, exif=exif)
    else:
        img.save(buf, formato)
    buf.seek(0)
    return buf


def formulario(estrellas, comentario="", fotos=(), conservar=None):
    datos = {"estrellas": str(estrellas), "comentario": comentario}
    if conservar is not None:
        datos["conservar"] = conservar
    datos["fotos"] = [(f, nombre) for f, nombre in fotos]
    return datos


def archivos_en_carpeta():
    return set(os.listdir(CARPETA)) if os.path.isdir(CARPETA) else set()


def limpiar():
    """Borra todo lo de los clientes de prueba y devuelve el stock vendido."""
    filas = query("SELECT id FROM usuarios WHERE correo IN (%s, %s, %s)", tuple(CORREOS))
    ids = {f["id"] for f in filas} | set(ids_prueba)
    for uid in ids:
        fotos = query("""SELECT f.archivo FROM opinion_fotos f JOIN opiniones o ON o.id = f.opinion_id
                         WHERE o.usuario_id = %s""", (uid,))
        for f in fotos:
            try:
                os.remove(os.path.join(CARPETA, f["archivo"]))
            except FileNotFoundError:
                pass
        ejecutar("DELETE FROM reportes_opinion WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM opiniones WHERE usuario_id = %s", (uid,))
        for f in query("""SELECT m.producto_id, m.sucursal_id, SUM(m.cantidad) AS vendido
                          FROM movimientos_inventario m JOIN ventas v ON v.id = m.venta_id
                          WHERE v.usuario_id = %s GROUP BY m.producto_id, m.sucursal_id""", (uid,)):
            ejecutar("""UPDATE inventario SET stock = stock - %s
                        WHERE producto_id = %s AND sucursal_id = %s""",
                     (f["vendido"], f["producto_id"], f["sucursal_id"]))
        ejecutar("""DELETE m FROM movimientos_inventario m JOIN ventas v ON v.id = m.venta_id
                    WHERE v.usuario_id = %s""", (uid,))
        ejecutar("DELETE FROM movimientos_puntos WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM ventas WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM codigos_verificacion WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (uid,))
    ejecutar("UPDATE productos SET opiniones_activas = 1 WHERE id IN (%s, %s)", (LECHE, CAFE))


with app.app_context():
    limpiar()
    try:
        archivos_antes = archivos_en_carpeta()
        antes = {p: stock(p) for p in (LECHE, CAFE)}
        uid_a, A = crear_cliente(CORREOS[0])
        uid_b, B = crear_cliente(CORREOS[1], PASSWORD_B)
        _, C = crear_cliente(CORREOS[2])
        comprar(A, [{"codigo": COD_CAFE, "cantidad": 1}, {"codigo": COD_LECHE, "cantidad": 1}])
        comprar(B, [{"codigo": COD_CAFE, "cantidad": 1}])
        url = f"/api/productos/{CAFE}/opiniones"

        # ---------- Ver opiniones de un producto ----------
        # El producto puede tener opiniones reales de antes: se guardan como "base"
        # y las pruebas comparan contra ella (así no importa lo que ya haya en la base).
        r = cliente.get(url, headers=A)
        d = r.get_json()
        base = d["resumen"]["por_estrellas"]
        base_total = d["resumen"]["total"]
        base_suma = sum(int(e) * n for e, n in base.items())
        revisar("Ver opiniones: 200 con resumen (total, promedio y por estrellas)",
                r.status_code == 200 and set(base) == {"5", "4", "3", "2", "1"}
                and base_total == sum(base.values()), d)
        revisar("Quien compró puede opinar", d["puede_opinar"] is True, d)
        revisar("Quien no compró no puede opinar",
                cliente.get(url, headers=C).get_json()["puede_opinar"] is False)
        revisar("Sin sesión: 401", cliente.get(url).status_code == 401)

        # ---------- Validaciones al opinar ----------
        r = cliente.post(url, headers=C, data=formulario(5, "Hola"))
        revisar("No compró: 403", r.status_code == 403, r.get_json())
        r = cliente.post(url, headers=A, data=formulario(6))
        revisar("6 estrellas: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=A, data=formulario(5, "x" * 501))
        revisar("Comentario de 501 caracteres: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=A, data=formulario(
            5, fotos=[(imagen(ancho=50, alto=50), f"f{i}.jpg") for i in range(4)]))
        revisar("4 fotos: 400", r.status_code == 400, r.get_json())
        falso = BytesIO(b"esto no es una imagen, es texto con nombre .jpg")
        r = cliente.post(url, headers=A, data=formulario(5, fotos=[(falso, "falsa.jpg")]))
        revisar("Archivo falso con nombre .jpg: 400", r.status_code == 400, r.get_json())
        revisar("El intento fallido no guardó opinión ni archivos",
                not query("SELECT id FROM opiniones WHERE usuario_id = %s", (uid_a,))
                and archivos_en_carpeta() == archivos_antes)
        grande = BytesIO(os.urandom(5 * 1024 * 1024 + 10))
        r = cliente.post(url, headers=A, data=formulario(5, fotos=[(grande, "enorme.jpg")]))
        revisar("Foto de más de 5 MB: 400", r.status_code == 400, r.get_json())

        # ---------- Opinar con 2 fotos ----------
        r = cliente.post(url, headers=A, data=formulario(
            5, "  Muy rico, sabe artesanal  ",
            fotos=[(imagen(girada=True), "celular.jpg"), (imagen("PNG", 800, 600), "captura.png")]))
        d = r.get_json()
        revisar("Opinar con 2 fotos: 201", r.status_code == 201, d)
        op = d.get("opinion", {})
        revisar("Autor con inicial del apellido: 'Prueba O.'", op.get("autor") == "Prueba O.", op)
        revisar("Comentario sin espacios sobrantes", op.get("comentario") == "Muy rico, sabe artesanal")
        fotos = query("SELECT id, archivo, ancho, alto FROM opinion_fotos WHERE opinion_id = %s ORDER BY id",
                      (op.get("id"),))
        revisar("2 fotos guardadas en la base y en la carpeta",
                len(fotos) == 2 and all(os.path.isfile(os.path.join(CARPETA, f["archivo"])) for f in fotos))
        # "with" cierra el archivo al terminar (en Windows, un archivo abierto no se puede borrar)
        with Image.open(os.path.join(CARPETA, fotos[0]["archivo"])) as f1:
            tamano, exif, formato = (f1.width, f1.height), dict(f1.getexif()), f1.format
        revisar("Foto reducida a máx. 1280 px y girada (960x1280)", tamano == (960, 1280), tamano)
        revisar("Foto sin metadatos EXIF (sin GPS ni marca de cámara)", len(exif) == 0, exif)
        revisar("Foto guardada como JPG", formato == "JPEG", formato)

        r = cliente.post(url, headers=A, data=formulario(4))
        revisar("Opinar dos veces: 409 YA_OPINASTE",
                r.status_code == 409 and r.get_json().get("codigo") == "YA_OPINASTE", r.get_json())

        r = cliente.get(op["fotos"][0]["url"])
        revisar("La foto se puede ver (público): 200 image/jpeg",
                r.status_code == 200 and r.mimetype == "image/jpeg", r.status_code)
        revisar("Nombre de foto inventado: 404",
                cliente.get("/api/opiniones/fotos/../../.env").status_code == 404
                and cliente.get("/api/opiniones/fotos/" + "0" * 32 + ".jpg").status_code == 404)

        # ---------- Promedio con dos opiniones ----------
        op_b = cliente.post(url, headers=B, data=formulario(3, "Está bien")).get_json()["opinion"]
        d = cliente.get(url, headers=B).get_json()
        esperado = dict(base, **{"5": base["5"] + 1, "3": base["3"] + 1})
        revisar("Promedio y conteo suman el 5 y el 3 nuevos",
                d["resumen"]["total"] == base_total + 2
                and d["resumen"]["por_estrellas"] == esperado
                and d["resumen"]["promedio"] == round((base_suma + 8) / (base_total + 2), 1),
                d["resumen"])
        revisar("es_mia solo en la opinión propia",
                {o["id"]: o["es_mia"] for o in d["opiniones"] if o["id"] in (op["id"], op_b["id"])}
                == {op["id"]: False, op_b["id"]: True}, d["opiniones"])

        # ---------- Reportar ----------
        rid = f"/api/opiniones/{op['id']}/reportar"
        revisar("Reportar con motivo inválido: 400",
                cliente.post(rid, headers=B, json={"motivo": "FEA"}).status_code == 400)
        revisar("Reportar: 201", cliente.post(rid, headers=B, json={"motivo": "SPAM"}).status_code == 201)
        r = cliente.post(rid, headers=B, json={"motivo": "SPAM"})
        revisar("Reportar dos veces: 409", r.status_code == 409, r.get_json())
        revisar("No puedo reportar mi propia opinión: 400",
                cliente.post(rid, headers=A, json={"motivo": "SPAM"}).status_code == 400)
        revisar("El reporte NO oculta la opinión (solo avisa al admin)",
                query("SELECT estado FROM opiniones WHERE id = %s", (op["id"],), one=True)["estado"]
                == "PUBLICADA")

        # ---------- Editar ----------
        uop = f"/api/opiniones/{op['id']}"
        revisar("Otro cliente no puede editarla: 404",
                cliente.put(uop, headers=B, data=formulario(1)).status_code == 404)
        r = cliente.put(uop, headers=A, data=formulario(
            4, "Rico pero caro", conservar=str(fotos[0]["id"]),
            fotos=[(imagen(ancho=300, alto=300), "nueva.jpg")]))
        d = r.get_json()
        revisar("Editar: 200, 4 estrellas, marcada como editada",
                r.status_code == 200 and d["opinion"]["estrellas"] == 4 and d["opinion"]["editada"], d)
        nuevas = query("SELECT archivo FROM opinion_fotos WHERE opinion_id = %s", (op["id"],))
        revisar("Conserva 1 foto, agrega 1 y borra el archivo de la que quitó",
                len(nuevas) == 2 and fotos[0]["archivo"] in [n["archivo"] for n in nuevas]
                and not os.path.exists(os.path.join(CARPETA, fotos[1]["archivo"])))
        r = cliente.put(uop, headers=A, data=formulario(
            4, conservar=",".join(str(x["id"]) for x in query(
                "SELECT id FROM opinion_fotos WHERE opinion_id = %s", (op["id"],))),
            fotos=[(imagen(ancho=50, alto=50), "a.jpg"), (imagen(ancho=50, alto=50), "b.jpg")]))
        revisar("Editar dejando 4 fotos: 400", r.status_code == 400, r.get_json())

        # ---------- Mis opiniones y ticket ----------
        d = cliente.get("/api/opiniones/mias", headers=A).get_json()
        revisar("Mis opiniones: 1 publicada (café) y la leche pendiente",
                [o["producto_id"] for o in d["publicadas"]] == [CAFE] and d["publicadas"][0]["producto"]
                and [p["producto_id"] for p in d["pendientes"]] == [LECHE], d)
        folio = query("SELECT folio FROM ventas WHERE usuario_id = %s", (uid_a,), one=True)["folio"]
        lineas = cliente.get(f"/api/compras/{folio}", headers=A).get_json()["venta"]["lineas"]
        revisar("El ticket dice qué productos ya opinó",
                {l["producto_id"]: l["opinion_id"] is not None for l in lineas}
                == {CAFE: True, LECHE: False}, lineas)

        # ---------- Opiniones desactivadas ----------
        ejecutar("UPDATE productos SET opiniones_activas = 0 WHERE id = %s", (LECHE,))
        r = cliente.post(f"/api/productos/{LECHE}/opiniones", headers=A, data=formulario(5))
        revisar("Producto con opiniones apagadas: 403", r.status_code == 403, r.get_json())
        revisar("Y ya no sale en pendientes",
                cliente.get("/api/opiniones/mias", headers=A).get_json()["pendientes"] == [])
        ejecutar("UPDATE productos SET opiniones_activas = 1 WHERE id = %s", (LECHE,))

        # ---------- El admin oculta una opinión ----------
        ejecutar("UPDATE opiniones SET estado = 'OCULTA' WHERE id = %s", (op["id"],))
        d = cliente.get(url, headers=B).get_json()
        revisar("Oculta: los demás no la ven y ya no cuenta en el promedio",
                d["resumen"]["total"] == base_total + 1
                and d["resumen"]["por_estrellas"] == dict(base, **{"3": base["3"] + 1})
                and all(o["id"] != op["id"] for o in d["opiniones"]), d["resumen"])
        d = cliente.get(url, headers=A).get_json()
        revisar("Su autor sí la ve (como OCULTA)",
                d["mi_opinion"] and d["mi_opinion"]["estado"] == "OCULTA", d.get("mi_opinion"))
        revisar("Las fotos de una opinión oculta no se pueden ver",
                cliente.get(op["fotos"][0]["url"]).status_code == 404)

        # ---------- Exportar mis datos ----------
        d = cliente.get("/api/cuenta/exportar", headers=A).get_json()
        revisar("Exportar incluye compras, puntos y opiniones",
                len(d["compras"]) == 1 and len(d["movimientos_de_puntos"]) == 1
                and len(d["opiniones"]) == 1 and d["opiniones"][0]["fotos"] == 2, d.keys())

        # ---------- Borrar ----------
        archivos_a = [x["archivo"] for x in query(
            "SELECT archivo FROM opinion_fotos WHERE opinion_id = %s", (op["id"],))]
        revisar("Otro cliente no puede borrarla: 404",
                cliente.delete(uop, headers=B).status_code == 404)
        r = cliente.delete(uop, headers=A)
        revisar("Borrar mi opinión: 200", r.status_code == 200, r.get_json())
        revisar("Se borraron la opinión, sus fotos, sus archivos y sus reportes",
                not query("SELECT id FROM opiniones WHERE id = %s", (op["id"],))
                and not query("SELECT id FROM opinion_fotos WHERE opinion_id = %s", (op["id"],))
                and not query("SELECT id FROM reportes_opinion WHERE opinion_id = %s", (op["id"],))
                and not any(os.path.exists(os.path.join(CARPETA, a)) for a in archivos_a))

        # ---------- Eliminar cuenta borra sus opiniones ----------
        cliente.put(f"/api/opiniones/{query('SELECT id FROM opiniones WHERE usuario_id = %s', (uid_b,), one=True)['id']}",
                    headers=B, data=formulario(3, fotos=[(imagen(ancho=200, alto=200), "b.jpg")]))
        archivos_b = [x["archivo"] for x in query(
            """SELECT f.archivo FROM opinion_fotos f JOIN opiniones o ON o.id = f.opinion_id
               WHERE o.usuario_id = %s""", (uid_b,))]
        r = cliente.delete("/api/cuenta", headers=B,
                           json={"password": PASSWORD_B, "confirmacion": "ELIMINAR"})
        revisar("Eliminar cuenta: borra sus opiniones y sus fotos",
                r.status_code == 200
                and not query("SELECT id FROM opiniones WHERE usuario_id = %s", (uid_b,))
                and archivos_b and not any(os.path.exists(os.path.join(CARPETA, a)) for a in archivos_b),
                r.get_json())
    finally:
        limpiar()
        revisar("Limpieza: stock devuelto y sin fotos de prueba en la carpeta",
                all(stock(p) == antes[p] for p in antes) and archivos_en_carpeta() == archivos_antes
                if "antes" in dir() else True)

print(f"\n{sum(resultados)}/{len(resultados)} pruebas correctas")