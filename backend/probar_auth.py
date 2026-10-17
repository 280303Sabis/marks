"""
Prueba automática del PASO 4.2 (registro, login, bloqueo, roles).
Actualizada en el PASO 5.10: fecha de nacimiento (18+) y sexo.
Uso:   python probar_auth.py
Crea un cliente de prueba y lo BORRA al final.
"""
from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_auth@marks.mx"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0


def prueba(nombre, resp, esperado):
    global ok_total
    datos = resp.get_json()
    if resp.status_code == esperado:
        ok_total += 1
        print(f"{VERDE}[OK]{FIN} {nombre}  ->  {resp.status_code}  {datos.get('error') or datos.get('mensaje') or ''}")
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
print("\n--- REGISTRO ---")
base = {"nombre": "Prueba", "correo": CORREO, "password": "Marks#2026", "acepta_privacidad": True, "fecha_nacimiento": "2000-01-15", "sexo": "F"}
prueba("Contraseña débil es rechazada", c.post("/api/auth/registro", json={**base, "password": "hola123"}), 400)
prueba("Sin aceptar Aviso de Privacidad es rechazado", c.post("/api/auth/registro", json={**base, "acepta_privacidad": False}), 400)
prueba("Correo inválido es rechazado", c.post("/api/auth/registro", json={**base, "correo": "no-es-correo"}), 400)
prueba("Menor de 18 años es rechazado", c.post("/api/auth/registro", json={**base, "fecha_nacimiento": "2015-06-01"}), 400)
prueba("Sin fecha de nacimiento es rechazado", c.post("/api/auth/registro", json={**base, "fecha_nacimiento": ""}), 400)
prueba("Sexo inválido es rechazado", c.post("/api/auth/registro", json={**base, "sexo": "X"}), 400)
prueba("Registro correcto", c.post("/api/auth/registro", json=base), 201)
prueba("Correo repetido es rechazado", c.post("/api/auth/registro", json=base), 409)

print("\n--- LOGIN ---")
datos = prueba("Login correcto", c.post("/api/auth/login", json={"correo": CORREO, "password": "Marks#2026"}), 200)
token = datos["token"]
yo = prueba("Ruta protegida CON token", c.get("/api/auth/yo", headers={"Authorization": f"Bearer {token}"}), 200)
print(f"       perfil: nacimiento {yo['fecha_nacimiento']}, sexo {yo['sexo']}")
prueba("Ruta protegida SIN token", c.get("/api/auth/yo"), 401)
prueba("Token alterado", c.get("/api/auth/yo", headers={"Authorization": f"Bearer {token}x"}), 401)
prueba("Correo inexistente (mismo mensaje)", c.post("/api/auth/login", json={"correo": "nadie@marks.mx", "password": "x"}), 401)

print("\n--- BLOQUEO (3 intentos) ---")
mal = {"correo": CORREO, "password": "Incorrecta#1"}
prueba("Intento fallido 1", c.post("/api/auth/login", json=mal), 401)
prueba("Intento fallido 2", c.post("/api/auth/login", json=mal), 401)
prueba("Intento fallido 3 -> se bloquea", c.post("/api/auth/login", json=mal), 423)
prueba("Bloqueada aunque la contraseña sea correcta", c.post("/api/auth/login", json={"correo": CORREO, "password": "Marks#2026"}), 423)

with app.app_context():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""SELECT evento, COUNT(*) n FROM bitacora_accesos
                       WHERE correo = %s GROUP BY evento""", (CORREO,))
        print("\n--- BITÁCORA ---")
        for fila in cur.fetchall():
            print(f"   {fila['evento']:<18} {fila['n']}")

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuario de prueba eliminado){FIN}\n")