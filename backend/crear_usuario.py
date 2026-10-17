"""
Crea usuarios ADMIN o GUARDIA (no se pueden registrar desde la app).
Uso:   python crear_usuario.py
"""
from getpass import getpass

import pymysql
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db
from app.utils.seguridad import correo_valido, validar_password

ROLES = {"1": ("CLIENTE", 1), "2": ("ADMIN", 2), "3": ("GUARDIA", 3)}

app = create_app()

with app.app_context():
    print("\n=== MARK'S - Crear usuario ===")
    nombre = input("Nombre: ").strip()
    correo = input("Correo: ").strip().lower()
    print("Rol:  1) CLIENTE   2) ADMIN   3) GUARDIA")
    rol = ROLES.get(input("Elige 1, 2 o 3: ").strip())

    if not nombre or not correo_valido(correo) or not rol:
        raise SystemExit("ERROR: Datos inválidos")

    while True:
        password = getpass("Contraseña (no se ve al escribir): ")
        errores = validar_password(password, correo)
        if errores:
            print("ERROR: " + "\nERROR: ".join(errores))
            continue
        if getpass("Repite la contraseña: ") != password:
            print("ERROR: No coinciden")
            continue
        break

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO usuarios
                           (nombre, correo, password_hash, rol_id, correo_verificado,
                            acepto_privacidad_en, version_aviso_privacidad)
                           VALUES (%s, %s, %s, %s, TRUE, NOW(), %s)""",
                        (nombre, correo, generate_password_hash(password), rol[1],
                         app.config["AVISO_PRIVACIDAD_VERSION"]))
        conn.commit()
        print(f"OK: Usuario {correo} creado como {rol[0]}")
    except pymysql.err.IntegrityError:
        print("ERROR: Ese correo ya existe")