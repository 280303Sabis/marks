"""
MI CUENTA (perfil del cliente) y DOCUMENTOS LEGALES

  Público:
    GET    /api/legal/aviso-privacidad        texto vigente del Aviso de Privacidad

  Requieren sesión:
    POST   /api/cuenta/cambiar-password       {"password_actual", "password_nueva"}
    POST   /api/cuenta/cerrar-sesiones        cierra la sesión en todos los dispositivos
    GET    /api/cuenta/exportar               copia de mis datos (derecho de Acceso)
    DELETE /api/cuenta                        {"password", "confirmacion": "ELIMINAR"}  (Cancelación)
"""
import secrets
from datetime import datetime

from flask import Blueprint, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from ..db import get_db, query
from ..legal import aviso_privacidad
from ..utils import correo as mail
from ..utils.seguridad import crear_token, registrar_bitacora, requiere_rol, validar_password

bp = Blueprint("cuenta", __name__)


def _usuario_actual():
    return query("""SELECT u.id, u.nombre, u.correo, u.password_hash, u.token_version,
                           r.nombre AS rol
                    FROM usuarios u JOIN roles r ON r.id = u.rol_id
                    WHERE u.id = %s""", (g.usuario_id,), one=True)


# ------------------------------------------------------------------
# AVISO DE PRIVACIDAD (público: se muestra antes de registrarse)
# ------------------------------------------------------------------
@bp.get("/legal/aviso-privacidad")
def ver_aviso():
    return jsonify(aviso_privacidad.como_diccionario())


# ------------------------------------------------------------------
# CAMBIAR CONTRASEÑA
# ------------------------------------------------------------------
@bp.post("/cuenta/cambiar-password")
@requiere_rol()
def cambiar_password():
    d = request.get_json(silent=True) or {}
    actual = d.get("password_actual") or ""
    nueva = d.get("password_nueva") or ""
    u = _usuario_actual()

    if not check_password_hash(u["password_hash"], actual):
        return jsonify(error="Tu contraseña actual no es correcta"), 400
    if check_password_hash(u["password_hash"], nueva):
        return jsonify(error="La nueva contraseña debe ser diferente a la actual"), 400
    errores = validar_password(nueva, u["correo"])
    if errores:
        return jsonify(error="La contraseña no es segura", detalles=errores), 400

    conn = get_db()
    with conn.cursor() as cur:
        # token_version + 1 -> se cierran las sesiones en los demás dispositivos
        cur.execute("""UPDATE usuarios
                       SET password_hash = %s, token_version = token_version + 1,
                           password_actualizada_en = NOW()
                       WHERE id = %s""", (generate_password_hash(nueva), u["id"]))
    conn.commit()
    registrar_bitacora("CAMBIO_PASSWORD", u["id"], u["correo"])

    # Aviso por correo: si no fue el usuario, se entera de inmediato
    mail.enviar_correo(
        u["correo"], "MARK'S - Tu contraseña fue cambiada",
        f"Hola {u['nombre']}:\n\nTu contraseña de MARK'S se cambió el "
        f"{datetime.now():%d/%m/%Y a las %H:%M}.\n\nSi no fuiste tú, usa la opción "
        f"'Olvidé mi contraseña' en la app para recuperar tu cuenta.\n\nMARK'S - Compra sin filas")

    # Este dispositivo recibe un token nuevo para seguir con la sesión abierta
    u["token_version"] += 1
    return jsonify(mensaje="Contraseña actualizada. Se cerró la sesión en tus otros dispositivos",
                   token=crear_token(u))


# ------------------------------------------------------------------
# CERRAR SESIÓN EN TODOS LOS DISPOSITIVOS
# ------------------------------------------------------------------
@bp.post("/cuenta/cerrar-sesiones")
@requiere_rol()
def cerrar_sesiones():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE usuarios SET token_version = token_version + 1 WHERE id = %s",
                    (g.usuario_id,))
    conn.commit()
    return jsonify(mensaje="Se cerró la sesión en todos tus dispositivos. Inicia sesión de nuevo")


# ------------------------------------------------------------------
# EXPORTAR MIS DATOS (derecho de Acceso)
# ------------------------------------------------------------------
@bp.get("/cuenta/exportar")
@requiere_rol()
def exportar_datos():
    perfil = query("""SELECT u.nombre, u.apellidos, u.correo, u.telefono, u.fecha_nacimiento, u.sexo, r.nombre AS rol,
                             u.puntos_saldo, u.correo_verificado, u.creado_en, u.ultimo_acceso,
                             u.password_actualizada_en
                      FROM usuarios u JOIN roles r ON r.id = u.rol_id
                      WHERE u.id = %s""", (g.usuario_id,), one=True)
    consentimiento = query("""SELECT acepto_privacidad_en AS fecha_aceptacion,
                                     version_aviso_privacidad AS version
                              FROM usuarios WHERE id = %s""", (g.usuario_id,), one=True)
    accesos = query("""SELECT evento, ip, fecha FROM bitacora_accesos
                       WHERE usuario_id = %s ORDER BY fecha DESC LIMIT 100""", (g.usuario_id,))

    registrar_bitacora("DATOS_EXPORTADOS", g.usuario_id, perfil["correo"])
    return jsonify(
        generado_en=datetime.now(),
        aviso="Esta es una copia de los datos personales que MARK'S tiene sobre ti.",
        perfil=perfil,
        aviso_privacidad_aceptado=consentimiento,
        historial_de_accesos=accesos,
        compras=[],          # se llenará en el PASO 9
        puntos_y_cupones=[], # se llenará en el PASO 11
    )


# ------------------------------------------------------------------
# ELIMINAR MI CUENTA (derecho de Cancelación)
# ------------------------------------------------------------------
@bp.delete("/cuenta")
@requiere_rol("CLIENTE")
def eliminar_cuenta():
    d = request.get_json(silent=True) or {}
    u = _usuario_actual()

    if not check_password_hash(u["password_hash"], d.get("password") or ""):
        return jsonify(error="Contraseña incorrecta"), 400
    if d.get("confirmacion") != "ELIMINAR":
        return jsonify(error='Para confirmar escribe la palabra ELIMINAR'), 400

    registrar_bitacora("CUENTA_ELIMINADA", u["id"], None, "Solicitada por el titular")

    # Se ANONIMIZA en lugar de borrar la fila: así las compras futuras (PASO 9)
    # se conservan para contabilidad, pero ya sin datos que identifiquen a la persona.
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""UPDATE usuarios
                       SET nombre = 'Usuario eliminado', apellidos = NULL, telefono = NULL, fecha_nacimiento = NULL, sexo = NULL,
                           correo = %s, password_hash = %s, activo = FALSE,
                           correo_verificado = FALSE, puntos_saldo = 0,
                           token_version = token_version + 1,
                           intentos_fallidos = 0, bloqueado_hasta = NULL
                       WHERE id = %s""",
                    (f"eliminado_{u['id']}@marks.invalid",
                     generate_password_hash(secrets.token_hex(32)), u["id"]))
        cur.execute("DELETE FROM codigos_verificacion WHERE usuario_id = %s", (u["id"],))
        cur.execute("UPDATE bitacora_accesos SET correo = NULL WHERE usuario_id = %s", (u["id"],))
    conn.commit()

    return jsonify(mensaje="Tu cuenta fue eliminada. Gracias por usar MARK'S")