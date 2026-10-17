"""
Prueba de la API del CARRITO (PASO 9.1).
Uso (desde la carpeta backend):   python probar_carrito.py
Crea un cliente de prueba ya verificado y lo BORRA al final.
Usa las fechas fijas de database/utilidades/fechas_prueba.sql
(refresco de Santa Catarina caducado).
"""
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_carrito@marks.mx"
PASSWORD = "Marks#2026"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0

LECHE, PAN, REFRESCO = "7501000000012", "7501000000029", "7501000000036"
MANZANA_BASCULA = "2140001012508"   # 1.250 kg
MANZANA, CARNE = "GR-40001", "GR-20001"


def limpiar():
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("DELETE FROM usuarios WHERE correo = %s", (CORREO,))
        conn.commit()


def crear_cliente():
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO usuarios
                           (nombre, correo, password_hash, rol_id, correo_verificado,
                            acepto_privacidad_en, version_aviso_privacidad)
                           VALUES ('Prueba', %s, %s, 1, TRUE, NOW(), '1.1')""",
                        (CORREO, generate_password_hash(PASSWORD)))
        conn.commit()


def prueba(nombre, cuerpo, esperado, revisar=None, token=True):
    """Envía el carrito y revisa el código HTTP y, opcionalmente, la respuesta."""
    global ok_total
    headers = {"Authorization": f"Bearer {TOKEN}"} if token else {}
    resp = c.post("/api/carrito/cotizar", json=cuerpo, headers=headers)
    datos = resp.get_json() or {}
    bien = resp.status_code == esperado and (revisar is None or revisar(datos))
    if bien:
        ok_total += 1
        if "total" in datos:
            errores = [l["error"] for l in datos["lineas"] if "error" in l]
            detalle = (f"total ${datos['total']}  ahorro ${datos['ahorro']}  "
                       f"pagar: {datos['se_puede_pagar']}")
            if errores:
                detalle += f"  |  {errores[0]}"
        else:
            detalle = datos.get("error", "")
        print(f"{VERDE}[OK]{FIN} {nombre}  ->  {resp.status_code}  {detalle}")
    else:
        print(f"{ROJO}[FALLO] {nombre}  ->  esperaba {esperado}, llegó {resp.status_code}: {datos}{FIN}")
        limpiar()
        raise SystemExit(1)


def error_linea(datos, i):
    return datos["lineas"][i].get("error", "")


limpiar()
crear_cliente()
login = c.post("/api/auth/login", json={"correo": CORREO, "password": PASSWORD})
TOKEN = (login.get_json() or {}).get("token")
if not TOKEN:
    limpiar()
    raise SystemExit(f"{ROJO}No se pudo iniciar sesión: {login.get_json()}{FIN}")

S1 = 1  # Santa Catarina

print("\n--- PETICIONES NO VÁLIDAS ---")
prueba("Sin sesión", {"sucursal_id": S1, "lineas": []}, 401, token=False)
prueba("Sucursal que no existe", {"sucursal_id": 99, "lineas": []}, 400)
prueba("Líneas que no son una lista", {"sucursal_id": S1, "lineas": "hola"}, 400)
prueba("Más de 60 productos distintos",
       {"sucursal_id": S1, "lineas": [{"codigo": LECHE}] * 61}, 400)

print("\n--- CARRITO CORRECTO ---")
prueba("Carrito vacío no se puede pagar", {"sucursal_id": S1, "lineas": []}, 200,
       lambda d: d["total"] == 0 and d["se_puede_pagar"] is False)
prueba("Leche x2 + pan x1 + manzana báscula + manzana 0.850 kg",
       {"sucursal_id": S1, "lineas": [
           {"codigo": LECHE, "cantidad": 2},
           {"codigo": PAN, "cantidad": 1},
           {"codigo": MANZANA_BASCULA},
           {"codigo": MANZANA, "peso_kg": 0.85},
       ]}, 200,
       lambda d: d["total"] == 211.30 and d["subtotal"] == 224.30
       and d["ahorro"] == 13.00 and d["articulos"] == 5 and d["se_puede_pagar"])

print("\n--- LÍNEAS CON ERROR (se marcan y no suman) ---")
prueba("Refresco caducado en Santa Catarina",
       {"sucursal_id": S1, "lineas": [{"codigo": LECHE, "cantidad": 1}, {"codigo": REFRESCO, "cantidad": 1}]},
       200, lambda d: d["total"] == 28.50 and "caducado" in error_linea(d, 1)
       and d["se_puede_pagar"] is False)
prueba("Cantidad 0", {"sucursal_id": S1, "lineas": [{"codigo": LECHE, "cantidad": 0}]}, 200,
       lambda d: "de 1 a 20" in error_linea(d, 0))
prueba("Cantidad 21", {"sucursal_id": S1, "lineas": [{"codigo": LECHE, "cantidad": 21}]}, 200,
       lambda d: "de 1 a 20" in error_linea(d, 0))
prueba("Cantidad con decimales", {"sucursal_id": S1, "lineas": [{"codigo": LECHE, "cantidad": 1.5}]}, 200,
       lambda d: "entero" in error_linea(d, 0))
prueba("Granel de anaquel sin peso", {"sucursal_id": S1, "lineas": [{"codigo": MANZANA}]}, 200,
       lambda d: error_linea(d, 0) == "Falta el peso del producto")
prueba("Código que no existe", {"sucursal_id": S1, "lineas": [{"codigo": "7509999999997"}]}, 200,
       lambda d: "no está disponible" in error_linea(d, 0))
prueba("Carne 20 kg + 20 kg (solo hay 35 kg)",
       {"sucursal_id": S1, "lineas": [{"codigo": CARNE, "peso_kg": 20}, {"codigo": CARNE, "peso_kg": 20}]},
       200, lambda d: "Solo hay" in error_linea(d, 0) and "Solo hay" in error_linea(d, 1))
prueba("Pan en Valle Oriente (no lo venden)",
       {"sucursal_id": 2, "lineas": [{"codigo": PAN, "cantidad": 1}]}, 200,
       lambda d: "no está disponible" in error_linea(d, 0))

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuario de prueba eliminado){FIN}\n")