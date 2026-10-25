"""
VERIFICACIÓN POR CORREO

  Confirmar correo (requiere sesión iniciada):
    POST /api/auth/correo/enviar-codigo     envía el código al correo del usuario
    POST /api/auth/correo/confirmar         {"codigo": "123456"}

  Recuperar contraseña (sin sesión):
    POST /api/auth/recuperar/solicitar      {"correo": "ana@correo.com"}
    POST /api/auth/recuperar/restablecer    {"correo": "...", "codigo": "123456",
                                             "password_nueva": "Nueva#2026"}
"""
from flask import Blueprint, current_app, g, jsonify, request
from werkzeug.security import generate_password_hash

from ..db import get_db, query
from ..utils import correo as mail
from ..utils.codigos import generar_codigo, segundos_desde_ultimo_codigo, verificar_codigo
from ..utils.seguridad import registrar_bitacora, requiere_rol, validar_password

bp = Blueprint("verificacion", __name__)

MENSAJE_GENERICO = ("Si el correo está registrado, te enviamos un código. "
                    "Revisa tu bandeja de entrada o la carpeta de correo no deseado")


def _espera_restante(usuario_id, tipo):
    """Segundos que faltan para poder pedir otro código (0 = ya puede)."""
    seg = segundos_desde_ultimo_codigo(usuario_id, tipo)
    espera = current_app.config["CODIGO_SEGUNDOS_ESPERA"]
    return 0 if seg is None or seg >= espera else espera - seg


def _enviar(usuario, tipo, motivo):
    codigo = generar_codigo(usuario["id"], tipo)
    texto, html = mail.plantilla_codigo(usuario["nombre"], codigo, motivo,
                                        current_app.config["CODIGO_MINUTOS_VIGENCIA"])
    return mail.enviar_correo(usuario["correo"], f"MARK'S - Código para {motivo}", texto, html)


# ------------------------------------------------------------------
# CONFIRMAR CORREO
# ------------------------------------------------------------------
@bp.post("/correo/enviar-codigo")
@requiere_rol()
def enviar_codigo_confirmacion():
    u = query("SELECT id, nombre, correo, correo_verificado FROM usuarios WHERE id = %s",
              (g.usuario_id,), one=True)
    if u["correo_verificado"]:
        return jsonify(mensaje="Tu correo ya está confirmado"), 200

    espera = _espera_restante(u["id"], "CONFIRMAR_CORREO")
    if espera:
        return jsonify(error=f"Espera {espera} segundos para pedir otro código"), 429

    if not _enviar(u, "CONFIRMAR_CORREO", "confirmar tu correo"):
        return jsonify(error="No pudimos enviar el correo. Intenta más tarde"), 503
    return jsonify(mensaje=f"Te enviamos un código a {u['correo']}. "
                           "Revisa también la carpeta de correo no deseado")


@bp.post("/correo/confirmar")
@requiere_rol()
def confirmar_correo():
    codigo = (request.get_json(silent=True) or {}).get("codigo")
    ok, error = verificar_codigo(g.usuario_id, "CONFIRMAR_CORREO", codigo)
    if not ok:
        return jsonify(error=error), 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE usuarios SET correo_verificado = TRUE WHERE id = %s", (g.usuario_id,))
    conn.commit()
    u = query("SELECT correo FROM usuarios WHERE id = %s", (g.usuario_id,), one=True)
    registrar_bitacora("CORREO_CONFIRMADO", g.usuario_id, u["correo"])
    return jsonify(mensaje="Correo confirmado correctamente")


# ------------------------------------------------------------------
# RECUPERAR CONTRASEÑA
# ------------------------------------------------------------------
@bp.post("/recuperar/solicitar")
def solicitar_recuperacion():
    correo = ((request.get_json(silent=True) or {}).get("correo") or "").strip().lower()
    u = query("SELECT id, nombre, correo, activo FROM usuarios WHERE correo = %s",
              (correo,), one=True)

    # Siempre la misma respuesta: así no se puede saber qué correos existen
    if not u or not u["activo"]:
        return jsonify(mensaje=MENSAJE_GENERICO)

    if _espera_restante(u["id"], "RECUPERAR_PASSWORD"):
        return jsonify(mensaje=MENSAJE_GENERICO)

    _enviar(u, "RECUPERAR_PASSWORD", "restablecer tu contraseña")
    registrar_bitacora("RECUPERACION_SOLICITADA", u["id"], correo)
    return jsonify(mensaje=MENSAJE_GENERICO)


@bp.post("/recuperar/restablecer")
def restablecer_password():
    d = request.get_json(silent=True) or {}
    correo = (d.get("correo") or "").strip().lower()
    nueva = d.get("password_nueva") or ""

    u = query("SELECT id FROM usuarios WHERE correo = %s AND activo = 1", (correo,), one=True)
    if not u:
        return jsonify(error="Código inválido o expirado"), 400

    errores = validar_password(nueva, correo)
    if errores:
        return jsonify(error="La contraseña no es segura", detalles=errores), 400

    ok, error = verificar_codigo(u["id"], "RECUPERAR_PASSWORD", d.get("codigo"))
    if not ok:
        return jsonify(error=error), 400

    conn = get_db()
    with conn.cursor() as cur:
        # token_version + 1 -> se cierran todas las sesiones abiertas
        # se quita el bloqueo y, como recibió el código, el correo queda confirmado
        cur.execute("""UPDATE usuarios
                       SET password_hash = %s, token_version = token_version + 1,
                           password_actualizada_en = NOW(), intentos_fallidos = 0,
                           bloqueado_hasta = NULL, correo_verificado = TRUE
                       WHERE id = %s""", (generate_password_hash(nueva), u["id"]))
    conn.commit()
    registrar_bitacora("RECUPERACION_OK", u["id"], correo)
    return jsonify(mensaje="Contraseña actualizada. Ya puedes iniciar sesión")