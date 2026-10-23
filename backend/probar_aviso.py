"""
Pruebas del PASO 14.1: aceptar el Aviso de Privacidad nuevo.

Cómo correrlo:
    cd backend
    python probar_aviso.py

Crea un cliente de prueba que aceptó una versión vieja del aviso,
revisa que /api/auth/yo diga que falta aceptar el nuevo y lo acepta.
Al final BORRA el cliente de prueba.
"""
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREO = "prueba.aviso@marks.test"

app = create_app()
cliente = app.test_client()
VIGENTE = app.config["AVISO_PRIVACIDAD_VERSION"]
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


def limpiar():
    for f in query("SELECT id FROM usuarios WHERE correo = %s", (CORREO,)):
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (f["id"],))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (f["id"],))


with app.app_context():
    limpiar()
    try:
        # Cliente que aceptó una versión vieja (como todos los que se registraron antes)
        uid = ejecutar("""INSERT INTO usuarios (nombre, correo, password_hash, rol_id,
                                                correo_verificado, acepto_privacidad_en,
                                                version_aviso_privacidad)
                          VALUES ('Prueba', %s, %s, 1, 1, NOW() - INTERVAL 30 DAY, '0.9')""",
                       (CORREO, generate_password_hash("sin-login")))
        H = {"Authorization": "Bearer " + crear_token({"id": uid, "rol": "CLIENTE", "token_version": 1})}

        d = cliente.get("/api/auth/yo", headers=H).get_json()
        revisar(f"/yo: versión vieja -> aviso_pendiente y vigente {VIGENTE}",
                d["aviso_pendiente"] is True and d["aviso_vigente"] == VIGENTE, d)

        r = cliente.post("/api/cuenta/aceptar-aviso", json={"version": VIGENTE})
        revisar("Aceptar sin sesión: 401", r.status_code == 401, r.status_code)

        r = cliente.post("/api/cuenta/aceptar-aviso", headers=H, json={"version": "0.9"})
        revisar("Aceptar una versión que no es la vigente: 409 AVISO_CAMBIO",
                r.status_code == 409 and r.get_json().get("codigo") == "AVISO_CAMBIO", r.get_json())
        r = cliente.post("/api/cuenta/aceptar-aviso", headers=H, json={})
        revisar("Aceptar sin decir la versión: 409", r.status_code == 409, r.get_json())
        revisar("Los intentos rechazados no cambiaron nada",
                query("SELECT version_aviso_privacidad AS v FROM usuarios WHERE id = %s",
                      (uid,), one=True)["v"] == "0.9")

        r = cliente.post("/api/cuenta/aceptar-aviso", headers=H, json={"version": VIGENTE})
        revisar("Aceptar la versión vigente: 200", r.status_code == 200, r.get_json())
        u = query("""SELECT version_aviso_privacidad AS v,
                            acepto_privacidad_en > NOW() - INTERVAL 1 MINUTE AS reciente
                     FROM usuarios WHERE id = %s""", (uid,), one=True)
        revisar("Se guardó la versión nueva y la fecha de hoy",
                u["v"] == VIGENTE and u["reciente"], u)
        revisar("Bitácora: AVISO_ACEPTADO",
                query("""SELECT 1 FROM bitacora_accesos
                         WHERE usuario_id = %s AND evento = 'AVISO_ACEPTADO'""", (uid,), one=True))

        d = cliente.get("/api/auth/yo", headers=H).get_json()
        revisar("/yo: ya no está pendiente", d["aviso_pendiente"] is False, d)

        d = cliente.get("/api/cuenta/exportar", headers=H).get_json()
        revisar("Exportar mis datos muestra la versión aceptada",
                d["aviso_privacidad_aceptado"]["version"] == VIGENTE, d["aviso_privacidad_aceptado"])
    finally:
        limpiar()
        revisar("Limpieza: cliente de prueba borrado",
                not query("SELECT id FROM usuarios WHERE correo = %s", (CORREO,)))

print(f"\n{sum(resultados)}/{len(resultados)} pruebas correctas")