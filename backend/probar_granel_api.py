"""
Prueba de la API de GRANEL (PASO 8.2).
Uso (desde la carpeta backend):   python probar_granel_api.py
Crea un cliente de prueba ya verificado y lo BORRA al final.
No necesita que la API esté corriendo: usa el cliente de pruebas de Flask.
"""
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_granel@marks.mx"
PASSWORD = "Marks#2026"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0


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


def prueba(nombre, url, esperado, importe=None, peso=None, token=True):
    """Llama a la API y revisa el código HTTP (y el importe/peso si se indican)."""
    global ok_total
    headers = {"Authorization": f"Bearer {TOKEN}"} if token else {}
    resp = c.get(url, headers=headers)
    datos = resp.get_json() or {}
    bien = resp.status_code == esperado
    if importe is not None:
        bien = bien and datos.get("importe") == importe
    if peso is not None:
        bien = bien and datos.get("peso_kg") == peso
    if bien:
        ok_total += 1
        detalle = datos.get("error") or datos.get("nombre", "")
        if "importe" in datos:
            detalle += f"  |  {datos['peso_kg']} kg x ${datos['precio_final']} = ${datos['importe']}"
        print(f"{VERDE}[OK]{FIN} {nombre}  ->  {resp.status_code}  {detalle}")
    else:
        print(f"{ROJO}[FALLO] {nombre}  ->  esperaba {esperado} "
              f"(importe {importe}, peso {peso}), llegó {resp.status_code}: {datos}{FIN}")
        limpiar()
        raise SystemExit(1)


limpiar()
crear_cliente()
login = c.post("/api/auth/login", json={"correo": CORREO, "password": PASSWORD})
TOKEN = (login.get_json() or {}).get("token")
if not TOKEN:
    limpiar()
    raise SystemExit(f"{ROJO}No se pudo iniciar sesión: {login.get_json()}{FIN}")

E = "/api/productos/escanear"

print("\n--- A) ETIQUETA DE BÁSCULA (sucursal 1) ---")
prueba("Sin sesión", f"{E}/2140001012508?sucursal_id=1", 401, token=False)
prueba("Manzana 1.250 kg", f"{E}/2140001012508?sucursal_id=1", 200, importe=68.63, peso=1.25)
prueba("Plátano 0.850 kg", f"{E}/2140002008500?sucursal_id=1", 200, importe=20.83, peso=0.85)
prueba("Carne 0.500 kg", f"{E}/2120001005007?sucursal_id=1", 200, importe=94.5, peso=0.5)
prueba("Etiqueta con dígito alterado", f"{E}/2140001012509?sucursal_id=1", 400)
prueba("PLU que no existe", f"{E}/2199999010003?sucursal_id=1", 404)
prueba("Manzana en Valle Oriente (no la venden)", f"{E}/2140001012508?sucursal_id=2", 404)

print("\n--- B) PESO ESCRITO (sucursal 1) ---")
prueba("Manzana sin peso (solo la ficha)", f"{E}/GR-40001?sucursal_id=1", 200)
prueba("Manzana 850 g", f"{E}/GR-40001?sucursal_id=1&peso=850&unidad=g", 200, importe=46.67, peso=0.85)
prueba("Plátano 1,5 kg (coma)", f"{E}/GR-40002?sucursal_id=1&peso=1,5", 200, importe=36.75, peso=1.5)
prueba("Peso en producto por pieza", f"{E}/7501000000012?sucursal_id=1&peso=1", 400)
prueba("Menos de 10 g", f"{E}/GR-40001?sucursal_id=1&peso=5&unidad=g", 400)
prueba("Más de 25 kg", f"{E}/GR-20001?sucursal_id=1&peso=30", 400)
prueba("Unidad no válida", f"{E}/GR-40001?sucursal_id=1&peso=2&unidad=lb", 400)
prueba("Peso que no es número", f"{E}/GR-40001?sucursal_id=1&peso=abc", 400)

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuario de prueba eliminado){FIN}\n")