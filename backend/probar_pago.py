"""
Pruebas del PASO 10: pago y QR de salida.

Cómo correrlo (con la API detenida o corriendo, da igual):
    cd backend
    python probar_pago.py

Crea dos clientes de prueba, hace una compra real en la sucursal 1
y al final BORRA todo lo que creó y DEVUELVE el stock que descontó.
"""
import uuid
from decimal import Decimal

from app import create_app
from app.db import get_db, query
from app.utils.qr import leer_qr
from app.utils.seguridad import crear_token

CORREO_1 = "prueba.pago@marks.test"
CORREO_2 = "prueba.pago2@marks.test"
SUCURSAL = 1
LECHE, PAN, MANZANA = 1, 2, 6
ETIQUETA_MANZANA = "2140001012508"   # báscula: Manzana roja 1.250 kg

app = create_app()
cliente = app.test_client()
resultados = []


def revisar(nombre, condicion, extra=""):
    condicion = bool(condicion)
    resultados.append(condicion)
    print(f"{'OK   ' if condicion else 'FALLA'} {len(resultados):>2}. {nombre}"
          + (f"  -> {extra}" if extra and not condicion else ""))


def crear_cliente(correo):
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash, rol_id)
                       VALUES ('Prueba', 'Pago', %s, 'sin-login', 1)""", (correo,))
        uid = cur.lastrowid
    conn.commit()
    return uid, crear_token({"id": uid, "rol": "CLIENTE", "token_version": 1})


def stock(producto_id):
    return query("SELECT stock FROM inventario WHERE producto_id = %s AND sucursal_id = %s",
                 (producto_id, SUCURSAL), one=True)["stock"]


def limpiar():
    """Borra lo de los clientes de prueba y devuelve el stock vendido."""
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM usuarios WHERE correo IN (%s, %s)", (CORREO_1, CORREO_2))
        ids = [f["id"] for f in cur.fetchall()]
        if not ids:
            return
        marcas = ",".join(["%s"] * len(ids))
        cur.execute(f"""SELECT m.producto_id, m.sucursal_id, SUM(m.cantidad) AS vendido
                        FROM movimientos_inventario m JOIN ventas v ON v.id = m.venta_id
                        WHERE v.usuario_id IN ({marcas})
                        GROUP BY m.producto_id, m.sucursal_id""", ids)
        for f in cur.fetchall():   # vendido es negativo: se resta para devolverlo
            cur.execute("""UPDATE inventario SET stock = stock - %s
                           WHERE producto_id = %s AND sucursal_id = %s""",
                        (f["vendido"], f["producto_id"], f["sucursal_id"]))
        cur.execute(f"""DELETE m FROM movimientos_inventario m JOIN ventas v ON v.id = m.venta_id
                        WHERE v.usuario_id IN ({marcas})""", ids)
        cur.execute(f"DELETE FROM movimientos_puntos WHERE usuario_id IN ({marcas})", ids)
        cur.execute(f"DELETE FROM ventas WHERE usuario_id IN ({marcas})", ids)
        cur.execute(f"DELETE FROM bitacora_accesos WHERE usuario_id IN ({marcas})", ids)
        cur.execute(f"DELETE FROM usuarios WHERE id IN ({marcas})", ids)
    conn.commit()


with app.app_context():
    limpiar()   # por si una prueba anterior se interrumpió
    try:
        uid, token = crear_cliente(CORREO_1)
        _, token2 = crear_cliente(CORREO_2)
        H = {"Authorization": f"Bearer {token}"}
        H2 = {"Authorization": f"Bearer {token2}"}
        antes = {p: stock(p) for p in (LECHE, PAN, MANZANA)}

        carrito = {"sucursal_id": SUCURSAL, "lineas": [
            {"codigo": "7501000000012", "cantidad": 2},   # leche x2
            {"codigo": "7501000000029", "cantidad": 1},   # pan (con oferta)
            {"codigo": ETIQUETA_MANZANA},                 # manzana 1.250 kg
        ]}
        tarjeta = {"marca": "VISA", "ultimos4": "4242"}

        def pedido(**cambios):
            base = dict(carrito, total_esperado=total, clave_pago=str(uuid.uuid4()),
                        tarjeta=tarjeta)
            base.update(cambios)
            return base

        cot = cliente.post("/api/carrito/cotizar", json=carrito, headers=H).get_json()
        total = cot["total"]
        revisar("La cotización se puede pagar", cot["se_puede_pagar"], cot)

        r = cliente.post("/api/compras/pagar", json=pedido())
        revisar("Sin sesión: 401", r.status_code == 401, r.status_code)

        r = cliente.post("/api/compras/pagar", json=pedido(), headers=H)
        revisar("Correo sin confirmar: 403", r.status_code == 403
                and r.get_json().get("codigo") == "CORREO_NO_CONFIRMADO", r.get_json())

        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("UPDATE usuarios SET correo_verificado = 1 WHERE id = %s", (uid,))
        conn.commit()

        r = cliente.post("/api/compras/pagar", json=pedido(clave_pago="123"), headers=H)
        revisar("Clave de pago inválida: 400", r.status_code == 400, r.status_code)

        r = cliente.post("/api/compras/pagar", headers=H, json=pedido(
            tarjeta={"marca": "VISA", "ultimos4": "4242", "numero": "4242424242424242"}))
        revisar("Rechaza el número completo de la tarjeta: 400", r.status_code == 400, r.get_json())

        r = cliente.post("/api/compras/pagar", json=pedido(total_esperado=total + 10), headers=H)
        revisar("Total distinto al calculado: 409 TOTAL_CAMBIO", r.status_code == 409
                and r.get_json().get("codigo") == "TOTAL_CAMBIO", r.get_json())

        malo = {"sucursal_id": SUCURSAL, "lineas": [{"codigo": "7501000000012", "cantidad": 21}]}
        r = cliente.post("/api/compras/pagar", json=pedido(**malo), headers=H)
        revisar("Carrito con errores: 409 CARRITO_CON_ERRORES", r.status_code == 409
                and r.get_json().get("codigo") == "CARRITO_CON_ERRORES", r.get_json())

        revisar("Los intentos rechazados no guardaron ventas",
                query("SELECT COUNT(*) n FROM ventas WHERE usuario_id = %s", (uid,), one=True)["n"] == 0)

        # ---------- Pago correcto ----------
        clave = str(uuid.uuid4())
        r = cliente.post("/api/compras/pagar", json=pedido(clave_pago=clave), headers=H)
        datos = r.get_json()
        revisar("Pago correcto: 201", r.status_code == 201, datos)
        venta = datos.get("venta", {})
        folio = venta.get("folio", "")
        revisar("Folio con formato MK-AAMMDD-000000", len(folio) == 16 and folio.startswith("MK-"), folio)
        revisar("Total cobrado = total cotizado", venta.get("total") == total, venta.get("total"))
        revisar("Ticket con 3 productos", len(venta.get("lineas", [])) == 3)
        revisar("El QR es auténtico y trae el folio", leer_qr(venta.get("qr")) == folio, venta.get("qr"))

        revisar("Stock: leche -2, pan -1, manzana -1.250 kg",
                stock(LECHE) == antes[LECHE] - 2 and stock(PAN) == antes[PAN] - 1
                and stock(MANZANA) == antes[MANZANA] - Decimal("1.250"))
        movs = query("""SELECT COUNT(*) n FROM movimientos_inventario m JOIN ventas v ON v.id = m.venta_id
                        WHERE v.folio = %s AND m.tipo = 'SALIDA_VENTA'""", (folio,), one=True)["n"]
        revisar("Kárdex: 3 salidas ligadas a la venta", movs == 3, movs)
        guardada = query("SELECT tarjeta_ultimos4, tarjeta_marca FROM ventas WHERE folio = %s",
                         (folio,), one=True)
        revisar("Solo se guardó marca y últimos 4", guardada == {"tarjeta_ultimos4": "4242",
                                                                 "tarjeta_marca": "VISA"}, guardada)
        revisar("Bitácora: COMPRA_PAGADA", query(
            "SELECT id FROM bitacora_accesos WHERE usuario_id = %s AND evento = 'COMPRA_PAGADA'",
            (uid,), one=True))

        # ---------- Reintento con la misma clave ----------
        r = cliente.post("/api/compras/pagar", json=pedido(clave_pago=clave), headers=H)
        revisar("Misma clave: no cobra dos veces (200, misma venta)", r.status_code == 200
                and r.get_json().get("repetida") and r.get_json()["venta"]["folio"] == folio,
                r.get_json())
        revisar("El stock no cambió con el reintento", stock(LECHE) == antes[LECHE] - 2)

        # ---------- Ver la compra ----------
        r = cliente.get(f"/api/compras/{folio}", headers=H)
        revisar("Ver mi compra: 200 con QR", r.status_code == 200 and r.get_json()["venta"]["qr"])
        r = cliente.get(f"/api/compras/{folio}", headers=H2)
        revisar("Otro cliente no puede verla: 404", r.status_code == 404, r.status_code)

        # ---------- QR falso ----------
        falso = venta["qr"][:-1] + ("A" if venta["qr"][-1] != "A" else "B")
        revisar("QR alterado: no es válido", leer_qr(falso) is None)
        # Cambia el último dígito por otro distinto (si termina en 9, usa 8)
        otro_folio = venta["qr"].replace(folio, folio[:-1] + ("8" if folio[-1] == "9" else "9"))
        revisar("QR con otro folio: no es válido", leer_qr(otro_folio) is None)
    finally:
        limpiar()
        revisar("Limpieza: stock devuelto",
                all(stock(p) == antes[p] for p in antes) if "antes" in dir() else True)

print(f"\n{sum(resultados)}/{len(resultados)} pruebas correctas")