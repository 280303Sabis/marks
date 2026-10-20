"""
Pruebas de PUT /api/cuenta/perfil (editar mis datos)
Crea un cliente de prueba, hace las pruebas y lo borra al final.
Uso (dentro de backend, con el venv activo):   python probar_perfil.py
"""
from datetime import date

from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db

app = create_app()
http = app.test_client()

CORREO = "prueba.perfil@marks.test"
PASSWORD = "Perfil#2026"
RUTA = "/api/cuenta/perfil"
resultados = []


def revisar(nombre, condicion, detalle=""):
    condicion = bool(condicion)          # True o False, aunque llegue un texto
    resultados.append(condicion)
    marca = "OK    " if condicion else "FALLA "
    print(f"{marca}{nombre}" + (f"   ->  {detalle}" if not condicion else ""))


def ejecutar(sql, params=()):
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(sql, params)
        conn.commit()


def borrar_usuario_prueba():
    with app.app_context():
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM usuarios WHERE correo = %s", (CORREO,))
            fila = cur.fetchone()
            if fila:
                uid = fila["id"]
                cur.execute("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (uid,))
                cur.execute("DELETE FROM codigos_verificacion WHERE usuario_id = %s", (uid,))
                cur.execute("DELETE FROM usuarios WHERE id = %s", (uid,))
        conn.commit()


def hace_anios(n):
    hoy = date.today()
    try:
        return hoy.replace(year=hoy.year - n).isoformat()
    except ValueError:           # 29 de febrero
        return hoy.replace(year=hoy.year - n, day=28).isoformat()


def datos(**cambios):
    base = {"nombre": "Prueba", "apellidos": "Perfil Uno", "telefono": "8111111111",
            "fecha_nacimiento": "2000-05-20", "sexo": "F"}
    base.update(cambios)
    return base


print("\n=== MARK'S - Pruebas de editar mis datos ===\n")

# Preparación: cliente verificado
borrar_usuario_prueba()
ejecutar("""INSERT INTO usuarios
            (nombre, apellidos, correo, password_hash, telefono, fecha_nacimiento, sexo,
             rol_id, correo_verificado, acepto_privacidad_en, version_aviso_privacidad)
            VALUES ('Prueba', NULL, %s, %s, NULL, '2000-05-20', 'F', 1, TRUE, NOW(), %s)""",
         (CORREO, generate_password_hash(PASSWORD), app.config["AVISO_PRIVACIDAD_VERSION"]))

try:
    # 1. Sin sesión
    r = http.put(RUTA, json=datos())
    revisar("1. Sin sesión -> 401", r.status_code == 401, r.status_code)

    # 2. Login
    r = http.post("/api/auth/login", json={"correo": CORREO, "password": PASSWORD})
    token = (r.get_json() or {}).get("token")
    revisar("2. Login del cliente de prueba", r.status_code == 200 and token, r.get_json())
    h = {"Authorization": f"Bearer {token}"}

    # 3. Cambio válido
    r = http.put(RUTA, json=datos(nombre="Ana María", telefono="8122334455", sexo="N"), headers=h)
    cuerpo = r.get_json() or {}
    revisar("3. Datos válidos -> 200", r.status_code == 200, cuerpo)
    revisar("4. Regresa el nombre nuevo", cuerpo.get("usuario", {}).get("nombre") == "Ana María", cuerpo)

    # 5. /auth/yo ya muestra los cambios
    yo = http.get("/api/auth/yo", headers=h).get_json() or {}
    revisar("5. /auth/yo refleja teléfono y sexo",
            yo.get("telefono") == "8122334455" and yo.get("sexo") == "N", yo)

    # Errores de validación
    r = http.put(RUTA, json=datos(nombre="A"), headers=h)
    revisar("6. Nombre de 1 letra -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(telefono="811111111"), headers=h)
    revisar("7. Teléfono de 9 dígitos -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(telefono="81111abcde"), headers=h)
    revisar("8. Teléfono con letras -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(fecha_nacimiento=hace_anios(17)), headers=h)
    revisar("9. Menor de 18 años -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(fecha_nacimiento="2099-01-01"), headers=h)
    revisar("10. Fecha en el futuro -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(fecha_nacimiento="ayer"), headers=h)
    revisar("11. Fecha que no es fecha -> 400", r.status_code == 400, r.get_json())

    r = http.put(RUTA, json=datos(sexo="X"), headers=h)
    revisar("12. Sexo inválido -> 400", r.status_code == 400, r.get_json())

    # 13. Quitar teléfono y apellidos (opcionales)
    r = http.put(RUTA, json=datos(telefono="", apellidos=""), headers=h)
    u = (r.get_json() or {}).get("usuario", {})
    revisar("13. Teléfono y apellidos vacíos quedan en NULL",
            r.status_code == 200 and u.get("telefono") is None and u.get("apellidos") is None,
            r.get_json())

    # 14. El correo no se puede cambiar por esta ruta
    r = http.put(RUTA, json=datos(correo="otro@marks.test"), headers=h)
    u = (r.get_json() or {}).get("usuario", {})
    revisar("14. El correo no cambia", u.get("correo") == CORREO, r.get_json())

finally:
    borrar_usuario_prueba()

print(f"\nResultado: {sum(resultados)} de {len(resultados)} pruebas correctas\n")