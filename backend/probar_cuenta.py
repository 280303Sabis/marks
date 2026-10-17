"""
Prueba automática del PASO 4.4 (Mi cuenta y Aviso de Privacidad).
Actualizada en el PASO 5.10: fecha de nacimiento y sexo (se exportan y se borran
al eliminar la cuenta).
Uso:   python probar_cuenta.py
No envía correos reales. Crea un cliente de prueba y lo BORRA al final.
"""
import app.utils.correo as correo_mod
from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_cuenta@marks.mx"
PASS1, PASS2 = "Marks#2026", "Nueva#2027"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0
ids_prueba = []
correo_mod.enviar_correo = lambda *a, **k: True   # no enviar correos reales en la prueba

DATOS_REGISTRO = {"nombre": "Prueba", "correo": CORREO, "password": PASS1,
                  "acepta_privacidad": True, "fecha_nacimiento": "2000-01-15", "sexo": "F"}


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


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def limpiar():
    """Borra solo los usuarios que creó esta prueba."""
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("DELETE FROM usuarios WHERE correo = %s", (CORREO,))
            for uid in ids_prueba:
                cur.execute("DELETE FROM usuarios WHERE id = %s", (uid,))
        conn.commit()


limpiar()

print("\n--- AVISO DE PRIVACIDAD ---")
aviso = prueba("Consultar aviso sin iniciar sesión", c.get("/api/legal/aviso-privacidad"), 200)
print(f"       versión {aviso['version']}, {len(aviso['secciones'])} secciones")

r = prueba("Registro (acepta aviso)", c.post("/api/auth/registro", json=DATOS_REGISTRO), 201)
token1 = r["token"]
ids_prueba.append(r["usuario"]["id"])

print("\n--- CAMBIAR CONTRASEÑA ---")
prueba("Contraseña actual incorrecta", c.post("/api/cuenta/cambiar-password", headers=auth(token1),
       json={"password_actual": "Mala#2026", "password_nueva": PASS2}), 400)
prueba("Nueva igual a la actual", c.post("/api/cuenta/cambiar-password", headers=auth(token1),
       json={"password_actual": PASS1, "password_nueva": PASS1}), 400)
prueba("Nueva contraseña débil", c.post("/api/cuenta/cambiar-password", headers=auth(token1),
       json={"password_actual": PASS1, "password_nueva": "abc"}), 400)
r = prueba("Cambio correcto", c.post("/api/cuenta/cambiar-password", headers=auth(token1),
           json={"password_actual": PASS1, "password_nueva": PASS2}), 200)
token2 = r["token"]
prueba("Token viejo (otro celular) ya no sirve", c.get("/api/auth/yo", headers=auth(token1)), 401)
prueba("Token nuevo (este celular) sigue funcionando", c.get("/api/auth/yo", headers=auth(token2)), 200)

print("\n--- CERRAR SESIÓN EN TODOS LOS DISPOSITIVOS ---")
prueba("Cerrar todas las sesiones", c.post("/api/cuenta/cerrar-sesiones", headers=auth(token2)), 200)
prueba("El token ya no sirve", c.get("/api/auth/yo", headers=auth(token2)), 401)
token3 = prueba("Iniciar sesión de nuevo", c.post("/api/auth/login",
                json={"correo": CORREO, "password": PASS2}), 200)["token"]

print("\n--- EXPORTAR MIS DATOS (ARCO: Acceso) ---")
datos = prueba("Exportar datos", c.get("/api/cuenta/exportar", headers=auth(token3)), 200)
perfil = datos["perfil"]
print(f"       incluye: perfil ({perfil['correo']}, nacimiento {perfil['fecha_nacimiento']}, "
      f"sexo {perfil['sexo']}), aviso v{datos['aviso_privacidad_aceptado']['version']}, "
      f"{len(datos['historial_de_accesos'])} accesos registrados")
prueba("Exportar sin sesión", c.get("/api/cuenta/exportar"), 401)

print("\n--- ELIMINAR CUENTA (ARCO: Cancelación) ---")
prueba("Contraseña incorrecta", c.delete("/api/cuenta", headers=auth(token3),
       json={"password": "Mala#2026", "confirmacion": "ELIMINAR"}), 400)
prueba("Sin escribir ELIMINAR", c.delete("/api/cuenta", headers=auth(token3),
       json={"password": PASS2, "confirmacion": "si"}), 400)
prueba("Eliminación correcta", c.delete("/api/cuenta", headers=auth(token3),
       json={"password": PASS2, "confirmacion": "ELIMINAR"}), 200)
with app.app_context():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""SELECT nombre, correo, telefono, fecha_nacimiento, sexo, activo
                       FROM usuarios WHERE id = %s""", (ids_prueba[0],))
        fila = cur.fetchone()
        cur.execute("SELECT COUNT(*) n FROM bitacora_accesos WHERE usuario_id = %s AND correo IS NOT NULL",
                    (ids_prueba[0],))
        con_correo = cur.fetchone()["n"]
print(f"       así quedó la cuenta: {fila['nombre']} | {fila['correo']} | activo={fila['activo']}")
print(f"       fecha de nacimiento: {fila['fecha_nacimiento']} | sexo: {fila['sexo']}")
print(f"       registros de su bitácora que aún muestran su correo: {con_correo}")
assert fila["correo"] != CORREO and con_correo == 0
assert fila["fecha_nacimiento"] is None and fila["sexo"] is None, "Debe borrar nacimiento y sexo"
prueba("La sesión se cerró", c.get("/api/auth/yo", headers=auth(token3)), 401)
prueba("Ya no puede iniciar sesión", c.post("/api/auth/login",
       json={"correo": CORREO, "password": PASS2}), 401)

r = prueba("El correo queda libre para registrarse otra vez",
           c.post("/api/auth/registro", json=DATOS_REGISTRO), 201)
ids_prueba.append(r["usuario"]["id"])

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuarios de prueba eliminados){FIN}\n")