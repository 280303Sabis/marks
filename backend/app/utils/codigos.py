"""
Códigos de verificación de 6 dígitos (confirmar correo y recuperar contraseña).

Reglas de seguridad:
  - Se guarda el HASH del código, nunca el código en texto plano.
  - Caduca en CODIGO_MINUTOS_VIGENCIA minutos.
  - Máximo CODIGO_MAX_INTENTOS intentos para escribirlo.
  - Solo sirve una vez.
  - Al pedir uno nuevo, los anteriores del mismo tipo quedan inválidos.
"""
import secrets

from flask import current_app
from werkzeug.security import check_password_hash, generate_password_hash

from ..db import get_db, query


def segundos_desde_ultimo_codigo(usuario_id, tipo):
    """Para evitar que alguien pida códigos sin parar."""
    fila = query("""SELECT TIMESTAMPDIFF(SECOND, MAX(creado_en), NOW()) AS seg
                    FROM codigos_verificacion WHERE usuario_id = %s AND tipo = %s""",
                 (usuario_id, tipo), one=True)
    return fila["seg"] if fila and fila["seg"] is not None else None


def generar_codigo(usuario_id, tipo):
    """Crea un código nuevo, invalida los anteriores y devuelve el código en texto."""
    codigo = f"{secrets.randbelow(1_000_000):06d}"
    minutos = current_app.config["CODIGO_MINUTOS_VIGENCIA"]
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""UPDATE codigos_verificacion SET usado_en = NOW()
                       WHERE usuario_id = %s AND tipo = %s AND usado_en IS NULL""",
                    (usuario_id, tipo))
        cur.execute("""INSERT INTO codigos_verificacion (usuario_id, tipo, codigo_hash, expira_en)
                       VALUES (%s, %s, %s, NOW() + INTERVAL %s MINUTE)""",
                    (usuario_id, tipo, generate_password_hash(codigo), minutos))
    conn.commit()
    return codigo


def verificar_codigo(usuario_id, tipo, codigo):
    """Devuelve (True, None) si es correcto o (False, 'mensaje de error')."""
    fila = query("""SELECT id, codigo_hash, intentos, expira_en > NOW() AS vigente
                    FROM codigos_verificacion
                    WHERE usuario_id = %s AND tipo = %s AND usado_en IS NULL
                    ORDER BY id DESC LIMIT 1""", (usuario_id, tipo), one=True)
    if not fila:
        return False, "No hay un código activo. Solicita uno nuevo"
    if not fila["vigente"]:
        return False, "El código expiró. Solicita uno nuevo"
    if fila["intentos"] >= current_app.config["CODIGO_MAX_INTENTOS"]:
        return False, "Demasiados intentos. Solicita un código nuevo"

    conn = get_db()
    codigo = (codigo or "").strip()
    if not (codigo.isdigit() and len(codigo) == 6 and check_password_hash(fila["codigo_hash"], codigo)):
        with conn.cursor() as cur:
            cur.execute("UPDATE codigos_verificacion SET intentos = intentos + 1 WHERE id = %s",
                        (fila["id"],))
        conn.commit()
        restantes = current_app.config["CODIGO_MAX_INTENTOS"] - fila["intentos"] - 1
        return False, f"Código incorrecto. Te quedan {max(restantes, 0)} intento(s)"

    with conn.cursor() as cur:
        cur.execute("UPDATE codigos_verificacion SET usado_en = NOW() WHERE id = %s", (fila["id"],))
    conn.commit()
    return True, None