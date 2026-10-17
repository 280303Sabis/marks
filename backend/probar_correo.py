"""
Prueba automática del PASO 4.3 (confirmar correo y recuperar contraseña).
Actualizada en el PASO 5.10: el registro incluye fecha de nacimiento y sexo.
Uso:   python probar_correo.py
No envía correos reales: atrapa los códigos para poder probarlos.
Crea un cliente de prueba y lo BORRA al final.
"""
import re

import app.utils.correo as correo_mod
from app import create_app
from app.db import get_db

app = create_app()
c = app.test_client()
CORREO = "prueba_correo@marks.mx"
PASS1, PASS2 = "Marks#2026", "Nueva#2027"
VERDE, ROJO, FIN = "\033[92m", "\033[91m", "\033[0m"
ok_total = 0
codigos = []


def correo_falso(destinatario, asunto, texto, html=None):
    """Reemplaza el envío real: guarda el código de 6 dígitos."""
    codigos.append(re.search(r"\b(\d{6})\b", texto).group(1))
    return True


correo_mod.enviar_correo = correo_falso


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
datos = c.post("/api/auth/registro", json={"nombre": "Prueba", "correo": CORREO,
                                           "password": PASS1, "acepta_privacidad": True,
                                           "fecha_nacimiento": "2000-01-15", "sexo": "F"}).get_json()
H = {"Authorization": f"Bearer {datos['token']}"}

print("\n--- CONFIRMAR CORREO ---")
prueba("Enviar código de confirmación", c.post("/api/auth/correo/enviar-codigo", headers=H), 200)
prueba("Pedir otro código de inmediato (espera 60 s)", c.post("/api/auth/correo/enviar-codigo", headers=H), 429)
prueba("Código incorrecto", c.post("/api/auth/correo/confirmar", headers=H, json={"codigo": "000000"}), 400)
prueba("Código correcto", c.post("/api/auth/correo/confirmar", headers=H, json={"codigo": codigos[-1]}), 200)
prueba("El mismo código ya no sirve", c.post("/api/auth/correo/confirmar", headers=H, json={"codigo": codigos[-1]}), 400)
yo = prueba("Perfil muestra correo confirmado", c.get("/api/auth/yo", headers=H), 200)
assert yo["correo_verificado"] == 1

print("\n--- RECUPERAR CONTRASEÑA ---")
r1 = prueba("Solicitar con correo NO registrado", c.post("/api/auth/recuperar/solicitar", json={"correo": "nadie@marks.mx"}), 200)
r2 = prueba("Solicitar con correo registrado", c.post("/api/auth/recuperar/solicitar", json={"correo": CORREO}), 200)
assert r1["mensaje"] == r2["mensaje"], "Los mensajes deben ser iguales"
print("       (los dos mensajes son idénticos: no se revela qué correos existen)")
codigo_rec = codigos[-1]
prueba("Contraseña nueva débil", c.post("/api/auth/recuperar/restablecer",
       json={"correo": CORREO, "codigo": codigo_rec, "password_nueva": "abc"}), 400)
prueba("Código equivocado", c.post("/api/auth/recuperar/restablecer",
       json={"correo": CORREO, "codigo": "111111", "password_nueva": PASS2}), 400)
prueba("Restablecer con código correcto", c.post("/api/auth/recuperar/restablecer",
       json={"correo": CORREO, "codigo": codigo_rec, "password_nueva": PASS2}), 200)
prueba("La sesión anterior se cerró", c.get("/api/auth/yo", headers=H), 401)
prueba("Login con la contraseña VIEJA falla", c.post("/api/auth/login", json={"correo": CORREO, "password": PASS1}), 401)
prueba("Login con la contraseña NUEVA funciona", c.post("/api/auth/login", json={"correo": CORREO, "password": PASS2}), 200)
prueba("Reusar el código de recuperación", c.post("/api/auth/recuperar/restablecer",
       json={"correo": CORREO, "codigo": codigo_rec, "password_nueva": "Otra#2028x"}), 400)

limpiar()
print(f"\n{VERDE}{ok_total} pruebas pasaron  (usuario de prueba eliminado){FIN}\n")