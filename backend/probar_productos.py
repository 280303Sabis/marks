"""
Prueba automática del PASO 7.1 (consulta de productos para el escáner).
Uso:   python probar_productos.py
Crea un cliente de prueba y lo BORRA al final.
"""
from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_productos@marks.mx"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0


def prueba(nombre, resp, esperado):
    global ok_total
    datos = resp.get_json()
    if resp.status_code == esperado:
        ok_total += 1
        detalle = datos.get("error") or datos.get("nombre") or "" if isinstance(datos, dict) else f"{len(datos)} productos"
        print(f"{VERDE}[OK]{FIN} {nombre}  ->  {resp.status_code}  {detalle}")
    else:
        print(f"{ROJO}[FALLO] {nombre}  ->  esperaba {esperado}, llegó {resp.status_code}: {datos}{FIN}")
        raise SystemExit(1)
    return datos


def limpiar():
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("DELETE FROM usuarios WHERE correo = %s", (CORREO,))
        conn.commit()


limpiar()

print("\n--- SIN SESIÓN ---")
prueba("Escanear sin iniciar sesión", c.get("/api/productos/escanear/7501000000012?sucursal_id=1"), 401)
prueba("Catálogo sin iniciar sesión", c.get("/api/productos?sucursal_id=1"), 401)
prueba("Sucursales es pública", c.get("/api/sucursales"), 200)

datos = c.post("/api/auth/registro", json={
    "nombre": "Prueba", "correo": CORREO, "password": "Marks#2026",
    "acepta_privacidad": True, "fecha_nacimiento": "2000-01-15", "sexo": "F"}).get_json()
H = {"Authorization": f"Bearer {datos['token']}"}

print("\n--- ESCANEAR (sucursal 1: Santa Catarina) ---")
p = prueba("Leche (sin oferta)", c.get("/api/productos/escanear/7501000000012?sucursal_id=1", headers=H), 200)
print(f"       precio {p['precio']}  ->  paga {p['precio_final']}  |  agotado: {p['agotado']}")
p = prueba("Pan (con oferta)", c.get("/api/productos/escanear/7501000000029?sucursal_id=1", headers=H), 200)
print(f"       precio {p['precio']}  ->  paga {p['precio_final']}")
assert float(p["precio_final"]) < float(p["precio"])
p = prueba("Café local de NL", c.get("/api/productos/escanear/7501000000043?sucursal_id=1", headers=H), 200)
print(f"       producto local: {bool(p['es_local'])}  |  productor: {p['productor']}")
p = prueba("Manzana a granel", c.get("/api/productos/escanear/GR-40001?sucursal_id=1", headers=H), 200)
print(f"       tipo de venta: {p['tipo_venta']}  |  ${p['precio']} por kg")

print("\n--- ERRORES ---")
prueba("Código que no existe", c.get("/api/productos/escanear/7509999999999?sucursal_id=1", headers=H), 404)
prueba("Código con caracteres no válidos", c.get("/api/productos/escanear/abc!@?sucursal_id=1", headers=H), 400)
prueba("Sin sucursal", c.get("/api/productos/escanear/7501000000012", headers=H), 400)
prueba("Sucursal que no existe", c.get("/api/productos/escanear/7501000000012?sucursal_id=99", headers=H), 400)
prueba("Pan en Valle Oriente (no lo venden ahí)", c.get("/api/productos/escanear/7501000000029?sucursal_id=2", headers=H), 404)

print("\n--- CATÁLOGO ---")
prueba("Catálogo de Santa Catarina", c.get("/api/productos?sucursal_id=1", headers=H), 200)
prueba("Catálogo de Valle Oriente", c.get("/api/productos?sucursal_id=2", headers=H), 200)

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuario de prueba eliminado){FIN}\n")