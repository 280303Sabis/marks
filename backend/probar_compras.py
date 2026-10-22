"""
Pruebas del PASO 12: Mis compras y Mis puntos.

Cómo correrlo:
    cd backend
    python probar_compras.py

Crea dos clientes de prueba, hace dos compras reales en la sucursal 1
y al final BORRA todo lo que creó y DEVUELVE el stock que descontó.
"""
import uuid

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREO_1 = "prueba.compras@marks.test"
CORREO_2 = "prueba.compras2@marks.test"
SUCURSAL = 1
LECHE, CAFE = 1, 4

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


def stock(producto_id):
    return query("SELECT stock FROM inventario WHERE producto_id = %s AND sucursal_id = %s",
                 (producto_id, SUCURSAL), one=True)["stock"]


def crear_cliente(correo):
    uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash,
                                            rol_id, correo_verificado)
                      VALUES ('Prueba', 'Compras', %s, 'sin-login', 1, 1)""", (correo,))
    token = crear_token({"id": uid, "rol": "CLIENTE", "token_version": 1})
    return uid, {"Authorization": f"Bearer {token}"}


def limpiar():
    """Borra lo de los clientes de prueba y devuelve el stock vendido."""
    for u in query("SELECT id FROM usuarios WHERE correo IN (%s, %s)", (CORREO_1, CORREO_2)):
        uid = u["id"]
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
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (uid,))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (uid,))


def comprar(H, lineas, usar_puntos=False):
    carrito = {"sucursal_id": SUCURSAL, "lineas": lineas}
    cot = cliente.post("/api/carrito/cotizar", json=carrito, headers=H).get_json()
    total = cot["puntos"]["total_con_puntos"] if usar_puntos else cot["total"]
    r = cliente.post("/api/compras/pagar", headers=H, json=dict(
        carrito, usar_puntos=usar_puntos, total_esperado=total,
        clave_pago=str(uuid.uuid4()), tarjeta={"marca": "VISA", "ultimos4": "4242"}))
    return r.get_json()["venta"]["folio"]


with app.app_context():
    limpiar()
    try:
        uid, H = crear_cliente(CORREO_1)
        _, H2 = crear_cliente(CORREO_2)
        antes = {p: stock(p) for p in (LECHE, CAFE)}

        r = cliente.get("/api/compras")
        revisar("Sin sesión: 401", r.status_code == 401, r.status_code)

        r = cliente.get("/api/compras", headers=H)
        revisar("Cliente nuevo: lista vacía", r.status_code == 200
                and r.get_json() == {"compras": [], "por_salir": []}, r.get_json())

        folio1 = comprar(H, [{"codigo": "7501000000012", "cantidad": 1}])        # leche
        ejecutar("UPDATE usuarios SET puntos_saldo = puntos_saldo + 200 WHERE id = %s", (uid,))
        folio2 = comprar(H, [{"codigo": "7501000000043", "cantidad": 2}], usar_puntos=True)  # café x2

        # El guardia valida la primera compra (lo hará la web en W16)
        ejecutar("UPDATE ventas SET estado = 'VALIDADA', validada_en = NOW() WHERE folio = %s",
                 (folio1,))

        datos = cliente.get("/api/compras", headers=H).get_json()
        compras = datos["compras"]
        revisar("Mis compras: 2 compras", len(compras) == 2, compras)
        revisar("La más nueva va primero", [c["folio"] for c in compras] == [folio2, folio1],
                [c["folio"] for c in compras])
        revisar("Estados: PAGADA y VALIDADA",
                [c["estado"] for c in compras] == ["PAGADA", "VALIDADA"], compras)
        revisar("por_salir solo trae la compra sin validar", datos["por_salir"] == [folio2], datos)
        c = compras[0]
        revisar("Cada compra trae sucursal, fecha, artículos, total y puntos",
                c["sucursal"] and c["pagada_en"] and c["articulos"] == 2 and c["total"] > 0
                and c["puntos_usados"] == 200 and c["puntos_ganados"] > 0, c)
        revisar("La lista no trae datos de la tarjeta", "tarjeta" not in c and "tarjeta_ultimos4" not in c)

        r = cliente.get("/api/compras?limite=1", headers=H)
        revisar("limite=1 devuelve solo la más nueva",
                [x["folio"] for x in r.get_json()["compras"]] == [folio2], r.get_json())
        r = cliente.get("/api/compras?limite=500", headers=H)
        revisar("limite=500: 400", r.status_code == 400, r.status_code)

        r = cliente.get(f"/api/compras/{folio1}", headers=H)
        revisar("Ticket de una compra validada: sin QR",
                r.status_code == 200 and r.get_json()["venta"]["qr"] is None, r.get_json())
        r = cliente.get(f"/api/compras/{folio2.lower()}", headers=H)
        revisar("Ticket por folio (aunque venga en minúsculas): con QR",
                r.status_code == 200 and r.get_json()["venta"]["qr"], r.status_code)

        r = cliente.get("/api/compras", headers=H2)
        revisar("Otro cliente no ve mis compras", r.get_json()["compras"] == [], r.get_json())

        # ---------- Mis puntos ----------
        r = cliente.get("/api/puntos/movimientos", headers=H)
        datos = r.get_json()
        saldo = query("SELECT puntos_saldo FROM usuarios WHERE id = %s", (uid,), one=True)["puntos_saldo"]
        revisar("Mis puntos: el saldo coincide con el de la cuenta",
                r.status_code == 200 and datos["saldo"] == saldo, datos)
        revisar("Trae las reglas (1 por $10, x2 local, 100 = $10, hasta 50%)",
                datos["reglas"] == {"pesos_por_punto": 10, "multiplicador_local": 2,
                                    "puntos_por_bloque": 100, "valor_bloque": 10,
                                    "max_porcentaje_canje": 50}, datos["reglas"])
        tipos = [m["tipo"] for m in datos["movimientos"]]
        revisar("Estado de cuenta: GANADOS, CANJEADOS, GANADOS (del más nuevo al más viejo)",
                tipos == ["GANADOS", "CANJEADOS", "GANADOS"], tipos)
        revisar("Cada movimiento trae su folio",
                [m["folio"] for m in datos["movimientos"]] == [folio2, folio2, folio1],
                datos["movimientos"])
        revisar("El último saldo_final es el saldo actual",
                datos["movimientos"][0]["saldo_final"] == saldo)

        r = cliente.get("/api/puntos/movimientos", headers=H2)
        revisar("Otro cliente: saldo 0 y sin movimientos",
                r.get_json()["saldo"] == 0 and r.get_json()["movimientos"] == [], r.get_json())
    finally:
        limpiar()
        revisar("Limpieza: stock devuelto y clientes borrados",
                all(stock(p) == antes[p] for p in antes) if "antes" in dir() else True)

print(f"\n{sum(resultados)}/{len(resultados)} pruebas correctas")