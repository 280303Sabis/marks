"""
Pruebas del PASO W10: productos en el portal del administrador.

Cómo correrlo:
    cd backend
    python probar_productos_admin.py

Crea un administrador y un cliente de prueba, cambia precio, oferta,
productor, nombre y los interruptores de un producto, y revisa que la app
(escaneo y opiniones) vea los cambios.
Al final DEJA el producto como estaba y borra los usuarios de prueba.
"""
from decimal import Decimal

from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREO_ADMIN = "prueba.admin.prod@marks.test"
CORREO_CLIENTE = "prueba.cliente.prod@marks.test"
CODIGO = "7501000000012"          # Leche entera 1 L (por pieza)

app = create_app()
cliente = app.test_client()
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


def limpiar_usuarios():
    for f in query("SELECT id FROM usuarios WHERE correo IN (%s, %s)",
                   (CORREO_ADMIN, CORREO_CLIENTE)):
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (f["id"],))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (f["id"],))


def crear_usuario(correo, rol_id, rol):
    uid = ejecutar("""INSERT INTO usuarios (nombre, correo, password_hash, rol_id,
                                            correo_verificado, acepto_privacidad_en,
                                            version_aviso_privacidad)
                      VALUES ('Prueba', %s, %s, %s, 1, NOW(), %s)""",
                   (correo, generate_password_hash("sin-login"), rol_id,
                    app.config["AVISO_PRIVACIDAD_VERSION"]))
    return {"Authorization": "Bearer " + crear_token({"id": uid, "rol": rol, "token_version": 1})}


with app.app_context():
    limpiar_usuarios()
    original = query("""SELECT id, nombre, descripcion, categoria_id, precio, precio_oferta,
                               productor_id, activo, opiniones_activas
                        FROM productos WHERE codigo_barras = %s""", (CODIGO,), one=True)
    pid = original["id"]
    otro = query("SELECT nombre FROM productos WHERE id <> %s ORDER BY id LIMIT 1",
                 (pid,), one=True)["nombre"]
    productor = query("SELECT id FROM productores_locales ORDER BY id LIMIT 1", one=True)
    URL = f"/api/admin/productos/{pid}"

    def editar(headers, **datos):
        return cliente.put(URL, headers=headers, json=datos)

    try:
        ADMIN = crear_usuario(CORREO_ADMIN, 2, "ADMIN")
        CLIENTE = crear_usuario(CORREO_CLIENTE, 1, "CLIENTE")

        # ---------- Permisos ----------
        r = cliente.get("/api/admin/productos")
        revisar("Catálogo sin sesión: 401", r.status_code == 401, r.status_code)
        r = cliente.get("/api/admin/productos", headers=CLIENTE)
        revisar("Catálogo con sesión de cliente: 403", r.status_code == 403, r.status_code)
        r = editar(CLIENTE, precio="1.00")
        revisar("Un cliente no puede cambiar precios: 403", r.status_code == 403, r.status_code)

        # ---------- Catálogo ----------
        r = cliente.get("/api/admin/productos", headers=ADMIN)
        d = r.get_json()
        revisar("Catálogo como admin: 200 con productos, categorías y productores",
                r.status_code == 200 and d["productos"] and d["categorias"]
                and "productores" in d, d)
        p = next((x for x in d["productos"] if x["id"] == pid), {})
        revisar("Cada producto trae opiniones, reportes y existencias",
                {"opiniones", "promedio", "reportes_pendientes", "stock_total"} <= set(p), p)

        # ---------- Precio y oferta ----------
        r = editar(ADMIN, precio="31.90", precio_oferta="27.50")
        p = r.get_json().get("producto", {})
        revisar("Cambiar precio a $31.90 con oferta $27.50: 200",
                r.status_code == 200 and p.get("precio") == 31.9 and p.get("precio_oferta") == 27.5,
                r.get_json())
        r = cliente.get(f"/api/productos/escanear/{CODIGO}?sucursal_id=1", headers=CLIENTE)
        revisar("La app ya cobra el precio de oferta",
                r.status_code == 200 and r.get_json().get("precio_final") == 27.5, r.get_json())

        r = editar(ADMIN, precio_oferta="31.90")
        revisar("Oferta igual al precio: 400 OFERTA_INVALIDA",
                r.status_code == 400 and r.get_json().get("codigo") == "OFERTA_INVALIDA", r.get_json())
        r = editar(ADMIN, precio="20.00")
        revisar("Bajar el precio por debajo de la oferta: 400",
                r.status_code == 400, r.get_json())
        r = editar(ADMIN, precio="0")
        revisar("Precio cero: 400", r.status_code == 400, r.get_json())
        r = editar(ADMIN, precio="12.345")
        revisar("Precio con 3 decimales: 400", r.status_code == 400, r.get_json())
        r = editar(ADMIN, precio="abc")
        revisar("Precio que no es número: 400", r.status_code == 400, r.get_json())
        revisar("Los intentos rechazados no cambiaron el precio",
                query("SELECT precio FROM productos WHERE id = %s", (pid,), one=True)["precio"]
                == Decimal("31.90"))

        r = editar(ADMIN, precio_oferta="")
        revisar("Quitar la oferta (vacío): 200 y sin oferta",
                r.status_code == 200 and r.get_json()["producto"]["precio_oferta"] is None,
                r.get_json())

        # ---------- Producto local ----------
        if productor:
            r = editar(ADMIN, productor_id=productor["id"])
            revisar("Marcar como producto local de NL: 200",
                    r.status_code == 200 and r.get_json()["producto"]["productor_id"] == productor["id"],
                    r.get_json())
            r = cliente.get(f"/api/productos/escanear/{CODIGO}?sucursal_id=1", headers=CLIENTE)
            revisar("La app lo muestra como local", r.get_json().get("es_local") in (1, True),
                    r.get_json())
        r = editar(ADMIN, productor_id=999999)
        revisar("Productor que no existe: 400", r.status_code == 400, r.get_json())
        r = editar(ADMIN, productor_id=None)
        revisar("Quitar el productor: 200",
                r.status_code == 200 and r.get_json()["producto"]["productor_id"] is None,
                r.get_json())

        # ---------- Nombre y categoría ----------
        r = editar(ADMIN, nombre="  Leche   entera  1 L  deslactosada ")
        revisar("Cambiar nombre (se limpian espacios): 200",
                r.status_code == 200
                and r.get_json()["producto"]["nombre"] == "Leche entera 1 L deslactosada",
                r.get_json())
        r = editar(ADMIN, nombre="Le")
        revisar("Nombre de 2 letras: 400", r.status_code == 400, r.get_json())
        r = editar(ADMIN, nombre=otro)
        revisar("Nombre repetido de otro producto: 400", r.status_code == 400, r.get_json())
        r = editar(ADMIN, categoria_id=999)
        revisar("Categoría que no existe: 400", r.status_code == 400, r.get_json())

        # ---------- Interruptores ----------
        r = editar(ADMIN, opiniones_activas=False)
        revisar("Apagar opiniones: 200", r.status_code == 200
                and r.get_json()["producto"]["opiniones_activas"] in (0, False), r.get_json())
        r = cliente.get(f"/api/productos/{pid}/opiniones", headers=CLIENTE)
        revisar("La app ve las opiniones apagadas (activas = false)",
                r.status_code == 200 and r.get_json()["activas"] is False, r.get_json())
        r = editar(ADMIN, opiniones_activas="tal vez")
        revisar("Valor que no es verdadero/falso: 400", r.status_code == 400, r.get_json())

        r = editar(ADMIN, activo=False)
        revisar("Desactivar el producto: 200", r.status_code == 200, r.get_json())
        r = cliente.get(f"/api/productos/escanear/{CODIGO}?sucursal_id=1", headers=CLIENTE)
        revisar("La app ya no lo encuentra al escanear: 404", r.status_code == 404, r.status_code)
        d = cliente.get("/api/admin/productos", headers=ADMIN).get_json()
        revisar("El admin sí lo sigue viendo (inactivo)",
                any(x["id"] == pid and not x["activo"] for x in d["productos"]))

        r = editar(ADMIN)
        revisar("Sin datos para cambiar: 400", r.status_code == 400, r.get_json())
        r = cliente.put("/api/admin/productos/999999", headers=ADMIN, json={"precio": "10"})
        revisar("Producto que no existe: 404", r.status_code == 404, r.status_code)

    finally:
        # Dejar el producto como estaba
        ejecutar("""UPDATE productos SET nombre = %s, descripcion = %s, categoria_id = %s,
                           precio = %s, precio_oferta = %s, productor_id = %s,
                           activo = %s, opiniones_activas = %s
                    WHERE id = %s""",
                 (original["nombre"], original["descripcion"], original["categoria_id"],
                  original["precio"], original["precio_oferta"], original["productor_id"],
                  original["activo"], original["opiniones_activas"], pid))
        limpiar_usuarios()

    ahora = query("""SELECT nombre, precio, precio_oferta, productor_id, activo, opiniones_activas
                     FROM productos WHERE id = %s""", (pid,), one=True)
    revisar("Limpieza: el producto quedó como estaba",
            all(ahora[k] == original[k] for k in ahora), ahora)

print(f"\n{sum(resultados)} de {len(resultados)} pruebas correctas")