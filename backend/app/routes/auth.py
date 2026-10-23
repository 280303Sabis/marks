"""
AUTENTICACIÓN de MARK'S

  POST /api/auth/registro   crear cuenta de CLIENTE (requiere aceptar Aviso de Privacidad)
  POST /api/auth/login      iniciar sesión (bloqueo tras 3 intentos fallidos)
  GET  /api/auth/yo         datos del usuario con sesión activa
                            (incluye aviso_pendiente: debe aceptar el Aviso de Privacidad nuevo)
"""
from datetime import date

import pymysql
from flask import Blueprint, current_app, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from ..db import get_db, query
from ..utils.seguridad import (correo_valido, crear_token, registrar_bitacora,
                               requiere_rol, validar_password)

bp = Blueprint("auth", __name__)

# Hash falso: si el correo no existe, igual se "revisa" una contraseña.
# Así la respuesta tarda lo mismo y no se puede adivinar qué correos existen.
HASH_FALSO = generate_password_hash("contraseña-que-no-existe")

EDAD_MINIMA = 18                 # pagos con tarjeta y venta de productos para adultos
SEXOS_VALIDOS = ("F", "M", "N")  # F femenino, M masculino, N prefiere no decirlo


def _calcular_edad(nacimiento, hoy):
    """Años cumplidos a la fecha de hoy."""
    return hoy.year - nacimiento.year - ((hoy.month, hoy.day) < (nacimiento.month, nacimiento.day))


# ------------------------------------------------------------------
# REGISTRO
# ------------------------------------------------------------------
@bp.post("/registro")
def registro():
    """
    Body JSON:
    {
      "nombre": "Ana", "apellidos": "López", "correo": "ana@correo.com",
      "telefono": "8112345678", "password": "Marks#2026",
      "fecha_nacimiento": "2000-05-20", "sexo": "F",
      "acepta_privacidad": true
    }
    """
    d = request.get_json(silent=True) or {}
    nombre = (d.get("nombre") or "").strip()
    apellidos = (d.get("apellidos") or "").strip() or None
    correo = (d.get("correo") or "").strip().lower()
    telefono = (d.get("telefono") or "").strip() or None
    password = d.get("password") or ""
    fecha_txt = (d.get("fecha_nacimiento") or "").strip()
    sexo = (d.get("sexo") or "").strip().upper()

    # 1. Validaciones
    if len(nombre) < 2 or len(nombre) > 80:
        return jsonify(error="Escribe tu nombre (2 a 80 caracteres)"), 400
    if not correo_valido(correo) or len(correo) > 120:
        return jsonify(error="Escribe un correo válido"), 400
    if telefono and (not telefono.isdigit() or len(telefono) != 10):
        return jsonify(error="El teléfono debe tener 10 dígitos"), 400

    try:
        fecha_nacimiento = date.fromisoformat(fecha_txt)
    except ValueError:
        return jsonify(error="Escribe tu fecha de nacimiento"), 400
    hoy = date.today()
    edad = _calcular_edad(fecha_nacimiento, hoy)
    if fecha_nacimiento > hoy or edad > 120:
        return jsonify(error="La fecha de nacimiento no es válida"), 400
    if edad < EDAD_MINIMA:
        return jsonify(error=f"Debes tener al menos {EDAD_MINIMA} años para crear una cuenta"), 400
    if sexo not in SEXOS_VALIDOS:
        return jsonify(error="Selecciona una opción en sexo"), 400
    errores = validar_password(password, correo)
    if errores:
        return jsonify(error="La contraseña no es segura", detalles=errores), 400
    if d.get("acepta_privacidad") is not True:
        return jsonify(error="Debes aceptar el Aviso de Privacidad para registrarte"), 400

    # 2. Guardar (siempre como CLIENTE, rol 1)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO usuarios
                           (nombre, apellidos, correo, password_hash, telefono,
                            fecha_nacimiento, sexo, rol_id,
                            acepto_privacidad_en, version_aviso_privacidad)
                           VALUES (%s, %s, %s, %s, %s, %s, %s, 1, NOW(), %s)""",
                        (nombre, apellidos, correo, generate_password_hash(password), telefono,
                         fecha_nacimiento, sexo,
                         current_app.config["AVISO_PRIVACIDAD_VERSION"]))
            nuevo_id = cur.lastrowid
        conn.commit()
    except pymysql.err.IntegrityError:
        conn.rollback()
        return jsonify(error="Ese correo ya está registrado"), 409

    registrar_bitacora("REGISTRO", nuevo_id, correo,
                       f"Aviso de privacidad v{current_app.config['AVISO_PRIVACIDAD_VERSION']}")

    usuario = {"id": nuevo_id, "nombre": nombre, "rol": "CLIENTE", "token_version": 1}
    return jsonify(mensaje="Cuenta creada", token=crear_token(usuario),
                   usuario={"id": nuevo_id, "nombre": nombre, "correo": correo,
                            "rol": "CLIENTE", "puntos": 0}), 201


# ------------------------------------------------------------------
# LOGIN (con bloqueo)
# ------------------------------------------------------------------
@bp.post("/login")
def login():
    """Body JSON: {"correo": "ana@correo.com", "password": "Marks#2026"}"""
    d = request.get_json(silent=True) or {}
    correo = (d.get("correo") or "").strip().lower()
    password = d.get("password") or ""
    cfg = current_app.config

    u = query("""SELECT u.id, u.nombre, u.correo, u.password_hash, u.activo, u.puntos_saldo,
                        u.intentos_fallidos, u.token_version, r.nombre AS rol,
                        u.bloqueado_hasta > NOW() AS esta_bloqueado,
                        CEIL(TIMESTAMPDIFF(SECOND, NOW(), u.bloqueado_hasta) / 60) AS minutos_restantes
                 FROM usuarios u JOIN roles r ON r.id = u.rol_id
                 WHERE u.correo = %s""", (correo,), one=True)

    # 1. Correo no existe -> mismo mensaje que contraseña incorrecta
    if not u:
        check_password_hash(HASH_FALSO, password)
        registrar_bitacora("LOGIN_FALLIDO", None, correo, "Correo no registrado")
        return jsonify(error="Correo o contraseña incorrectos"), 401

    # 2. Cuenta desactivada
    if not u["activo"]:
        return jsonify(error="Esta cuenta está desactivada"), 403

    # 3. Cuenta bloqueada
    if u["esta_bloqueado"]:
        return jsonify(error=f"Cuenta bloqueada por seguridad. Intenta de nuevo en "
                             f"{u['minutos_restantes']} minuto(s)"), 423

    conn = get_db()

    # 4. Contraseña incorrecta -> sumar intento y bloquear si llega al máximo
    if not check_password_hash(u["password_hash"], password):
        intentos = u["intentos_fallidos"] + 1
        with conn.cursor() as cur:
            if intentos >= cfg["MAX_INTENTOS_LOGIN"]:
                cur.execute("""UPDATE usuarios
                               SET intentos_fallidos = 0,
                                   bloqueado_hasta = NOW() + INTERVAL %s MINUTE
                               WHERE id = %s""", (cfg["MINUTOS_BLOQUEO"], u["id"]))
            else:
                cur.execute("UPDATE usuarios SET intentos_fallidos = %s WHERE id = %s",
                            (intentos, u["id"]))
        conn.commit()

        if intentos >= cfg["MAX_INTENTOS_LOGIN"]:
            registrar_bitacora("CUENTA_BLOQUEADA", u["id"], correo,
                               f"{intentos} intentos fallidos")
            return jsonify(error=f"Demasiados intentos. Tu cuenta se bloqueó "
                                 f"{cfg['MINUTOS_BLOQUEO']} minutos"), 423

        registrar_bitacora("LOGIN_FALLIDO", u["id"], correo, f"Intento {intentos}")
        restantes = cfg["MAX_INTENTOS_LOGIN"] - intentos
        return jsonify(error="Correo o contraseña incorrectos",
                       intentos_restantes=restantes), 401

    # 5. Login correcto -> reiniciar contador y crear sesión
    with conn.cursor() as cur:
        cur.execute("""UPDATE usuarios
                       SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = NOW()
                       WHERE id = %s""", (u["id"],))
    conn.commit()
    registrar_bitacora("LOGIN_OK", u["id"], correo)

    return jsonify(token=crear_token(u),
                   usuario={"id": u["id"], "nombre": u["nombre"], "correo": u["correo"],
                            "rol": u["rol"], "puntos": u["puntos_saldo"]})


# ------------------------------------------------------------------
# PERFIL DEL USUARIO CON SESIÓN
# ------------------------------------------------------------------
@bp.get("/yo")
@requiere_rol()
def yo():
    u = query("""SELECT u.id, u.nombre, u.apellidos, u.correo, u.telefono,
                        u.fecha_nacimiento, u.sexo, u.puntos_saldo,
                        u.correo_verificado, u.ultimo_acceso, u.creado_en,
                        u.version_aviso_privacidad, r.nombre AS rol
                 FROM usuarios u JOIN roles r ON r.id = u.rol_id
                 WHERE u.id = %s""", (g.usuario_id,), one=True)
    # PASO 14: si el Aviso de Privacidad cambió desde que lo aceptó, la app
    # le muestra el nuevo y le pide aceptarlo (POST /api/cuenta/aceptar-aviso).
    vigente = current_app.config["AVISO_PRIVACIDAD_VERSION"]
    u["aviso_vigente"] = vigente
    u["aviso_pendiente"] = u["version_aviso_privacidad"] != vigente
    return jsonify(u)