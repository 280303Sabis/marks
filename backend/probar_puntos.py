"""
Pruebas del PASO 11: programa de lealtad (puntos).

Cómo correrlo:
    cd backend
    python probar_puntos.py

Crea un cliente de prueba, hace dos compras reales en la sucursal 1
(una sin usar puntos y otra usándolos) y al final BORRA todo lo que creó
y DEVUELVE el stock que descontó.
"""
import uuid
from decimal import Decimal

from app import create_app
from app.db import get_db, query
from app.utils.puntos import puntos_a_ganar, puntos_canjeables
from app.utils.seguridad import crear_token

CORREO = "prueba.puntos@marks.test"
SUCURSAL = 1
LECHE, CAFE = 1, 4   # el café de olla es producto LOCAL de NL

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


def saldo(uid):
    return query("SELECT puntos_saldo FROM usuarios WHERE id = %s", (uid,), one=True)["puntos_saldo"]


def limpiar():
    """Borra lo del cliente de prueba y devuelve el stock vendido."""
    u = query("SELECT id FROM usuarios WHERE correo = %s", (CORREO,), one=True)
    if not u:
        return
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


with app.app_context():
    # ---------- Reglas (sin base de datos) ----------
    revisar("Regla: $156.50 con $89 local = 24 puntos",
            puntos_a_ganar(Decimal("156.50"), Decimal("89"), Decimal("156.50")) == 24)
    revisar("Regla: sin locales, $156.50 = 15 puntos",
            puntos_a_ganar(Decimal("156.50"), Decimal("0"), Decimal("156.50")) == 15)
    revisar("Regla: 350 puntos en compra de $156.50 -> usa 300 ($30)",
            puntos_canjeables(350, Decimal("156.50")) == (300, Decimal("30.00")))
    revisar("Regla: tope de 50% (10,000 puntos en $28.50 -> solo 100)",
            puntos_canjeables(10000, Decimal("28.50")) == (100, Decimal("10.00")))
    revisar("Regla: con 99 puntos no alcanza para canjear",
            puntos_canjeables(99, Decimal("500")) == (0, Decimal("0.00")))

    limpiar()
    try:
        uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash,
                                                rol_id, correo_verificado)
                          VALUES ('Prueba', 'Puntos', %s, 'sin-login', 1, 1)""", (CORREO,))
        H = {"Authorization": f"Bearer {crear_token({'id': uid, 'rol': 'CLIENTE', 'token_version': 1})}"}
        antes = {p: stock(p) for p in (LECHE, CAFE)}

        carrito = {"sucursal_id": SUCURSAL, "lineas": [
            {"codigo": "7501000000012", "cantidad": 2},   # leche x2 = $57.00
            {"codigo": "7501000000043", "cantidad": 1},   # café LOCAL = $89.00
        ]}

        def pagar(**extra):
            datos = dict(carrito, clave_pago=str(uuid.uuid4()),
                         tarjeta={"marca": "VISA", "ultimos4": "4242"})
            datos.update(extra)
            return cliente.post("/api/compras/pagar", json=datos, headers=H)

        # ---------- Compra 1: sin puntos ----------
        cot = cliente.post("/api/carrito/cotizar", json=carrito, headers=H).get_json()
        p = cot.get("puntos", {})
        revisar("Cotizar trae el bloque de puntos", p.get("saldo") == 0, cot)
        revisar("Con 0 puntos no puede canjear", p.get("puntos_usables") == 0, p)
        revisar("Ganaría 23 puntos ($146 + $89 local = 235)", p.get("ganarias") == 23, p)

        r = pagar(total_esperado=cot["total"])
        venta = r.get_json().get("venta", {})
        revisar("Compra 1 pagada: 201", r.status_code == 201, r.get_json())
        revisar("Compra 1: ganó 23 puntos", venta.get("puntos_ganados") == 23, venta)
        revisar("Saldo: 23 puntos", saldo(uid) == 23 and r.get_json().get("puntos_saldo") == 23)
        mov = query("SELECT tipo, puntos, saldo_final FROM movimientos_puntos WHERE usuario_id = %s",
                    (uid,))
        revisar("Estado de cuenta: 1 movimiento GANADOS +23",
                mov == [{"tipo": "GANADOS", "puntos": 23, "saldo_final": 23}], mov)

        r = pagar(total_esperado=cot["total"], usar_puntos=True)
        revisar("Con 23 puntos no puede usar puntos: 409 PUNTOS_CAMBIARON",
                r.status_code == 409 and r.get_json().get("codigo") == "PUNTOS_CAMBIARON", r.get_json())

        # ---------- Compra 2: usando puntos ----------
        ejecutar("UPDATE usuarios SET puntos_saldo = 350 WHERE id = %s", (uid,))
        cot = cliente.post("/api/carrito/cotizar", json=carrito, headers=H).get_json()
        p = cot["puntos"]
        revisar("Con 350 puntos puede usar 300 ($30)",
                p["puntos_usables"] == 300 and p["descuento"] == 30, p)
        revisar("Total con puntos: $116.00", p["total_con_puntos"] == 116, p)
        revisar("Ganaría 18 puntos sobre lo pagado con tarjeta", p["ganarias_con_puntos"] == 18, p)

        r = pagar(total_esperado=146, usar_puntos=True)
        revisar("Usar puntos pero mandar el total sin descuento: 409 TOTAL_CAMBIO",
                r.status_code == 409 and r.get_json().get("codigo") == "TOTAL_CAMBIO", r.get_json())

        clave = str(uuid.uuid4())
        r = pagar(total_esperado=116, usar_puntos=True, clave_pago=clave)
        datos = r.get_json()
        venta = datos.get("venta", {})
        revisar("Compra 2 pagada con puntos: 201", r.status_code == 201, datos)
        revisar("Ticket: usó 300 puntos, -$30, cobró $116",
                venta.get("puntos_usados") == 300 and venta.get("descuento_puntos") == 30
                and venta.get("total") == 116, venta)
        revisar("Ticket: ganó 18 puntos", venta.get("puntos_ganados") == 18, venta)
        revisar("Cuadra: subtotal - ahorro - descuento = total",
                round(venta["subtotal"] - venta["ahorro"] - venta["descuento_puntos"], 2)
                == venta["total"], venta)
        revisar("Saldo: 350 - 300 + 18 = 68", saldo(uid) == 68 and datos.get("puntos_saldo") == 68,
                saldo(uid))
        mov = query("""SELECT tipo, puntos, saldo_final FROM movimientos_puntos
                       WHERE usuario_id = %s ORDER BY id DESC LIMIT 2""", (uid,))
        revisar("Estado de cuenta: CANJEADOS -300 (saldo 50) y GANADOS +18 (saldo 68)",
                mov == [{"tipo": "GANADOS", "puntos": 18, "saldo_final": 68},
                        {"tipo": "CANJEADOS", "puntos": -300, "saldo_final": 50}], mov)

        r = pagar(total_esperado=116, usar_puntos=True, clave_pago=clave)
        revisar("Reintento con la misma clave: no vuelve a usar ni dar puntos",
                r.status_code == 200 and r.get_json().get("repetida") and saldo(uid) == 68,
                r.get_json())

        revisar("Stock: leche -4, café -2 (dos compras)",
                stock(LECHE) == antes[LECHE] - 4 and stock(CAFE) == antes[CAFE] - 2)
    finally:
        limpiar()
        revisar("Limpieza: stock devuelto y cliente borrado",
                all(stock(p) == antes[p] for p in antes) if "antes" in dir() else True)

print(f"\n{sum(resultados)}/{len(resultados)} pruebas correctas")