"""
Utilidades de seguridad de MARK'S
  - Validación de contraseña segura
  - Creación y verificación del token de sesión (JWT)
  - Decorador @requiere_rol para proteger rutas
  - Bitácora de accesos
"""
import re
from datetime import datetime, timedelta, timezone
from functools import wraps

import jwt
from flask import current_app, g, jsonify, request

from ..db import get_db, query

CORREO_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")


# ------------------------------------------------------------------
# 1. CONTRASEÑA SEGURA
# ------------------------------------------------------------------
def validar_password(password, correo=""):
    """Devuelve una lista de errores. Lista vacía = contraseña segura."""
    errores = []
    if len(password) < 8:
        errores.append("Debe tener al menos 8 caracteres")
    if len(password) > 64:
        errores.append("Debe tener máximo 64 caracteres")
    if not re.search(r"[A-Z]", password):
        errores.append("Debe incluir al menos una letra MAYÚSCULA")
    if not re.search(r"[a-z]", password):
        errores.append("Debe incluir al menos una letra minúscula")
    if not re.search(r"\d", password):
        errores.append("Debe incluir al menos un número")
    if not re.search(r"[^A-Za-z0-9]", password):
        errores.append("Debe incluir al menos un símbolo (ej. ! # $ % & *)")
    usuario_correo = correo.split("@")[0].lower()
    if len(usuario_correo) >= 4 and usuario_correo in password.lower():
        errores.append("No debe contener tu correo")
    return errores


def correo_valido(correo):
    return bool(CORREO_RE.match(correo or ""))


# ------------------------------------------------------------------
# 2. TOKEN DE SESIÓN (JWT)
# ------------------------------------------------------------------
def crear_token(usuario):
    """usuario debe traer: id, rol, token_version"""
    ahora = datetime.now(timezone.utc)
    payload = {
        "sub": str(usuario["id"]),
        "rol": usuario["rol"],
        "tv": usuario["token_version"],   # si cambia la contraseña, el token viejo deja de servir
        "iat": ahora,
        "exp": ahora + timedelta(hours=current_app.config["JWT_HORAS_VIGENCIA"]),
    }
    return jwt.encode(payload, current_app.config["JWT_SECRET"], algorithm="HS256")


def requiere_rol(*roles):
    """
    Protege una ruta:
        @requiere_rol()                    -> cualquier usuario con sesión
        @requiere_rol("CLIENTE")           -> solo clientes
        @requiere_rol("ADMIN", "GUARDIA")  -> admin o guardia
    Si todo está bien, deja en g.usuario_id y g.rol los datos del usuario.
    """
    def decorador(fn):
        @wraps(fn)
        def envoltura(*args, **kwargs):
            encabezado = request.headers.get("Authorization", "")
            if not encabezado.startswith("Bearer "):
                return jsonify(error="Debes iniciar sesión"), 401
            try:
                datos = jwt.decode(encabezado[7:], current_app.config["JWT_SECRET"],
                                   algorithms=["HS256"])
            except jwt.ExpiredSignatureError:
                return jsonify(error="Tu sesión expiró, inicia sesión de nuevo"), 401
            except jwt.InvalidTokenError:
                return jsonify(error="Sesión inválida"), 401

            # Se revisa en la BD: cuenta activa, rol actual y versión del token
            u = query("""SELECT u.id, u.activo, u.token_version, r.nombre AS rol
                         FROM usuarios u JOIN roles r ON r.id = u.rol_id
                         WHERE u.id = %s""", (datos["sub"],), one=True)
            if not u or not u["activo"]:
                return jsonify(error="Cuenta no disponible"), 401
            if u["token_version"] != datos.get("tv"):
                return jsonify(error="Tu sesión se cerró. Inicia sesión de nuevo"), 401
            if roles and u["rol"] not in roles:
                return jsonify(error="No tienes permiso para esta acción"), 403

            g.usuario_id = u["id"]
            g.rol = u["rol"]
            return fn(*args, **kwargs)
        return envoltura
    return decorador


# ------------------------------------------------------------------
# 3. BITÁCORA DE ACCESOS
# ------------------------------------------------------------------
def ip_cliente():
    return (request.headers.get("X-Forwarded-For", request.remote_addr or "")
            .split(",")[0].strip())[:45]


def registrar_bitacora(evento, usuario_id=None, correo=None, detalle=None):
    """Guarda un evento de seguridad. Nunca debe romper la petición principal."""
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO bitacora_accesos (usuario_id, correo, evento, ip, detalle)
                           VALUES (%s, %s, %s, %s, %s)""",
                        (usuario_id, correo, evento, ip_cliente(), (detalle or "")[:200]))
        conn.commit()
    except Exception:
        pass