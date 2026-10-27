"""
Pruebas del PASO W9: inventario y kárdex del portal del administrador.

Cómo correrlo:
    cd backend
    python probar_inventario.py

Crea un administrador y un cliente de prueba, registra entradas, mermas y
ajustes en la sucursal 1 y revisa el kárdex.
Al final DEJA el inventario como estaba (stock, mínimo y caducidad),
borra los movimientos de prueba y los usuarios de prueba.
"""
from datetime import date, timedelta
from decimal import Decimal

from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREO_ADMIN = "prueba.admin.inv@marks.test"
CORREO_CLIENTE = "prueba.cliente.inv@marks.test"
SUCURSAL = 1

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
        ejecutar("DELETE FROM movimientos_inventario WHERE usuario_id = %s", (f["id"],))
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


def stock(producto_id):
    return query("SELECT stock FROM inventario WHERE producto_id = %s AND sucursal_id = %s",
                 (producto_id, SUCURSAL), one=True)["stock"]


def mover(headers, **datos):
    datos.setdefault("sucursal_id", SUCURSAL)
    return cliente.post("/api/admin/inventario/movimiento", headers=headers, json=datos)


with app.app_context():
    limpiar_usuarios()

    # Un producto por pieza y uno a granel de la sucursal 1
    pieza = query("""SELECT producto_id AS id, stock, stock_minimo, fecha_caducidad FROM v_inventario
                     WHERE sucursal_id = %s AND tipo_venta = 'UNIDAD' AND activo = 1
                     ORDER BY producto_id LIMIT 1""", (SUCURSAL,), one=True)
    granel = query("""SELECT producto_id AS id, stock, stock_minimo, fecha_caducidad FROM v_inventario
                      WHERE sucursal_id = %s AND tipo_venta = 'GRANEL' AND activo = 1
                      ORDER BY producto_id LIMIT 1""", (SUCURSAL,), one=True)
    originales = [pieza, granel]

    try:
        ADMIN = crear_usuario(CORREO_ADMIN, 2, "ADMIN")
        CLIENTE = crear_usuario(CORREO_CLIENTE, 1, "CLIENTE")

        # ---------- Permisos ----------
        r = cliente.get(f"/api/admin/inventario?sucursal_id={SUCURSAL}")
        revisar("Inventario sin sesión: 401", r.status_code == 401, r.status_code)
        r = cliente.get(f"/api/admin/inventario?sucursal_id={SUCURSAL}", headers=CLIENTE)
        revisar("Inventario con sesión de cliente: 403", r.status_code == 403, r.status_code)
        r = mover(CLIENTE, tipo="ENTRADA", producto_id=pieza["id"], cantidad=5)
        revisar("Un cliente no puede registrar entradas: 403", r.status_code == 403, r.status_code)

        # ---------- Existencias ----------
        r = cliente.get(f"/api/admin/inventario?sucursal_id={SUCURSAL}", headers=ADMIN)
        d = r.get_json()
        revisar("Inventario como admin: 200 con productos y resumen",
                r.status_code == 200 and d["productos"] and "por_caducar" in d["resumen"], d)
        revisar("Cada producto trae stock, mínimo y alertas",
                all({"stock", "stock_minimo", "caducado", "caducidad_proxima"} <= set(p)
                    for p in d["productos"]))

        # ---------- Entrada ----------
        antes = stock(pieza["id"])
        cad = (date.today() + timedelta(days=20)).isoformat()
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=12,
                  fecha_caducidad=cad, nota="Pedido del proveedor")
        revisar("Entrada de 12 piezas: 201", r.status_code == 201, r.get_json())
        revisar("El stock subió 12", stock(pieza["id"]) == antes + 12, stock(pieza["id"]))
        revisar("La caducidad cambió al lote nuevo",
                str(r.get_json()["producto"]["fecha_caducidad"])[:10] == cad, r.get_json())
        m = query("""SELECT tipo, cantidad, stock_final, usuario_id FROM movimientos_inventario
                     WHERE producto_id = %s ORDER BY id DESC LIMIT 1""", (pieza["id"],), one=True)
        revisar("Kárdex: ENTRADA +12 con el stock final y el administrador",
                m["tipo"] == "ENTRADA" and m["cantidad"] == 12 and m["stock_final"] == antes + 12
                and m["usuario_id"] is not None, m)

        # ---------- Validaciones ----------
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=1.5)
        revisar("Pieza con decimales: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=0)
        revisar("Cantidad cero: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=-3)
        revisar("Cantidad negativa: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=10000)
        revisar("Más de 9999: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="ENTRADA", producto_id=pieza["id"], cantidad=1,
                  fecha_caducidad=(date.today() - timedelta(days=1)).isoformat())
        revisar("Entrada con caducidad vencida: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="REGALO", producto_id=pieza["id"], cantidad=1)
        revisar("Tipo que no existe: 400", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="ENTRADA", producto_id=999999, cantidad=1)
        revisar("Producto que no está en la sucursal: 404", r.status_code == 404, r.get_json())
        r = mover(ADMIN, tipo="MERMA", producto_id=pieza["id"], cantidad=1)
        revisar("Merma sin motivo: 400", r.status_code == 400, r.get_json())
        revisar("Los intentos rechazados no movieron el stock", stock(pieza["id"]) == antes + 12)

        # ---------- Merma ----------
        r = mover(ADMIN, tipo="MERMA", producto_id=pieza["id"], cantidad=2, nota="Empaque roto")
        revisar("Merma de 2: 201", r.status_code == 201, r.get_json())
        revisar("El stock bajó 2", stock(pieza["id"]) == antes + 10)
        actual = stock(pieza["id"])
        r = mover(ADMIN, tipo="MERMA", producto_id=pieza["id"], cantidad=int(actual) + 1,
                  nota="Prueba de más")
        revisar("Merma mayor que el stock: 409 STOCK_INSUFICIENTE",
                r.status_code == 409 and r.get_json().get("codigo") == "STOCK_INSUFICIENTE",
                r.get_json())

        # ---------- Granel ----------
        antes_g = stock(granel["id"])
        r = mover(ADMIN, tipo="ENTRADA", producto_id=granel["id"], cantidad="2.375")
        revisar("Granel: entrada de 2.375 kg: 201", r.status_code == 201, r.get_json())
        revisar("Granel: el stock subió 2.375", stock(granel["id"]) == antes_g + Decimal("2.375"))
        r = mover(ADMIN, tipo="ENTRADA", producto_id=granel["id"], cantidad="1.2345")
        revisar("Granel con 4 decimales: 400", r.status_code == 400, r.get_json())

        # ---------- Ajuste (conteo físico) ----------
        r = mover(ADMIN, tipo="AJUSTE", producto_id=pieza["id"], stock_real=int(actual),
                  nota="Conteo")
        revisar("Ajuste igual al stock: 400 (nada que ajustar)", r.status_code == 400, r.get_json())
        r = mover(ADMIN, tipo="AJUSTE", producto_id=pieza["id"], stock_real=int(actual) - 3,
                  nota="Conteo físico")
        revisar("Ajuste a 3 piezas menos: 201", r.status_code == 201, r.get_json())
        m = query("""SELECT tipo, cantidad, stock_final FROM movimientos_inventario
                     WHERE producto_id = %s ORDER BY id DESC LIMIT 1""", (pieza["id"],), one=True)
        revisar("Kárdex: AJUSTE -3 y el stock quedó en el conteo",
                m["tipo"] == "AJUSTE" and m["cantidad"] == -3
                and stock(pieza["id"]) == actual - 3, m)

        # ---------- Stock mínimo y caducidad ----------
        r = cliente.put(f"/api/admin/inventario/{pieza['id']}", headers=ADMIN,
                        json={"sucursal_id": SUCURSAL, "stock_minimo": 7, "fecha_caducidad": ""})
        p = r.get_json().get("producto", {})
        revisar("Cambiar mínimo a 7 y quitar caducidad: 200",
                r.status_code == 200 and p.get("stock_minimo") == 7
                and p.get("fecha_caducidad") is None, r.get_json())
        r = cliente.put(f"/api/admin/inventario/{pieza['id']}", headers=ADMIN,
                        json={"sucursal_id": SUCURSAL, "stock_minimo": -1})
        revisar("Mínimo negativo: 400", r.status_code == 400, r.get_json())

        # ---------- Kárdex ----------
        r = cliente.get(f"/api/admin/kardex?sucursal_id={SUCURSAL}&producto_id={pieza['id']}"
                        "&periodo=hoy", headers=ADMIN)
        d = r.get_json()
        tipos = [m["tipo"] for m in d.get("movimientos", [])]
        revisar("Kárdex de hoy del producto: ENTRADA, MERMA y AJUSTE",
                r.status_code == 200 and {"ENTRADA", "MERMA", "AJUSTE"} <= set(tipos), d)
        revisar("Totales: 12 de entrada (o más) y 2 de merma (o más)",
                d["totales"]["entradas"] >= 12 and d["totales"]["mermas"] >= 2, d.get("totales"))
        revisar("Cada movimiento trae fecha con hora de Monterrey y quién lo hizo",
                all(len(m["fecha"]) == 16 and m["usuario"] for m in d["movimientos"]))
        r = cliente.get(f"/api/admin/kardex?sucursal_id={SUCURSAL}&tipo=merma&periodo=hoy",
                        headers=ADMIN)
        revisar("Filtro por tipo: solo mermas",
                all(m["tipo"] == "MERMA" for m in r.get_json()["movimientos"]), r.get_json())

    finally:
        # Dejar el inventario como estaba
        for o in originales:
            ejecutar("""UPDATE inventario SET stock = %s, stock_minimo = %s, fecha_caducidad = %s
                        WHERE producto_id = %s AND sucursal_id = %s""",
                     (o["stock"], o["stock_minimo"], o["fecha_caducidad"], o["id"], SUCURSAL))
        limpiar_usuarios()

    revisar("Limpieza: el inventario quedó como estaba",
            all(stock(o["id"]) == o["stock"] for o in originales))

print(f"\n{sum(resultados)} de {len(resultados)} pruebas correctas")