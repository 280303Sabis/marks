"""
MI CUENTA (perfil del cliente) y DOCUMENTOS LEGALES

  Público:
    GET    /api/legal/aviso-privacidad        texto vigente del Aviso de Privacidad

    Requieren sesión:
    POST   /api/cuenta/aceptar-aviso          {"version": "1.2"}  aceptar el Aviso de Privacidad nuevo
    PUT    /api/cuenta/perfil                editar mis datos (solo CLIENTE, Rectificación)
    POST   /api/cuenta/cambiar-password       {"password_actual", "password_nueva"}
    POST   /api/cuenta/cerrar-sesiones        cierra la sesión en todos los dispositivos
    GET    /api/cuenta/exportar               copia de mis datos: perfil, compras, puntos y opiniones (Acceso)
    DELETE /api/cuenta                        {"password", "confirmacion": "ELIMINAR"}  (Cancelación)
                                              anonimiza la cuenta y BORRA sus opiniones y fotos
"""
import secrets
from datetime import date, datetime

from flask import Blueprint, current_app, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from ..db import get_db, query
from ..legal import aviso_privacidad
from ..utils import correo as mail
from ..utils.fotos import borrar_fotos
from ..utils.seguridad import crear_token, registrar_bitacora, requiere_rol, validar_password
from .auth import EDAD_MINIMA, SEXOS_VALIDOS, _calcular_edad

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
# ACEPTAR EL AVISO DE PRIVACIDAD NUEVO (PASO 14)
# ------------------------------------------------------------------
@bp.post("/cuenta/aceptar-aviso")
@requiere_rol()
def aceptar_aviso():
    """
    Body JSON: {"version": "1.2"}
    La app manda la versión que el usuario LEYÓ. Si no es la vigente
    (el aviso cambió mientras lo leía), se rechaza para que lea el nuevo.
    """
    d = request.get_json(silent=True) or {}
    leida = str(d.get("version") or "").strip()
    vigente = current_app.config["AVISO_PRIVACIDAD_VERSION"]
    if leida != vigente:
        return jsonify(error="El Aviso de Privacidad cambió. Vuelve a leerlo",
                       codigo="AVISO_CAMBIO", vigente=vigente), 409

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""UPDATE usuarios
                       SET acepto_privacidad_en = NOW(), version_aviso_privacidad = %s
                       WHERE id = %s""", (vigente, g.usuario_id))
    conn.commit()
    registrar_bitacora("AVISO_ACEPTADO", g.usuario_id, None, f"Aviso de privacidad v{vigente}")
    return jsonify(mensaje="Gracias. Aceptaste el Aviso de Privacidad", version=vigente)


# ------------------------------------------------------------------
# EDITAR MIS DATOS (derecho de Rectificación)
# ------------------------------------------------------------------
@bp.put("/cuenta/perfil")
@requiere_rol("CLIENTE")
def editar_perfil():
    """
    Body JSON (se envían todos; apellidos y teléfono pueden ir vacíos):
    {
      "nombre": "Ana", "apellidos": "López", "telefono": "8112345678",
      "fecha_nacimiento": "2000-05-20", "sexo": "F"
    }
    El correo NO se cambia aquí.
    """
    d = request.get_json(silent=True) or {}
    nombre = (d.get("nombre") or "").strip()
    apellidos = (d.get("apellidos") or "").strip() or None
    telefono = (d.get("telefono") or "").strip() or None
    fecha_txt = (d.get("fecha_nacimiento") or "").strip()
    sexo = (d.get("sexo") or "").strip().upper()

    # 1. Validaciones (las mismas reglas del registro)
    if len(nombre) < 2 or len(nombre) > 80:
        return jsonify(error="Escribe tu nombre (2 a 80 caracteres)"), 400
    if apellidos and len(apellidos) > 80:
        return jsonify(error="Los apellidos pueden tener máximo 80 caracteres"), 400
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
        return jsonify(error=f"Debes tener al menos {EDAD_MINIMA} años"), 400
    if sexo not in SEXOS_VALIDOS:
        return jsonify(error="Selecciona una opción en sexo"), 400

    # 2. Guardar
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""UPDATE usuarios
                       SET nombre = %s, apellidos = %s, telefono = %s,
                           fecha_nacimiento = %s, sexo = %s
                       WHERE id = %s""",
                    (nombre, apellidos, telefono, fecha_nacimiento, sexo, g.usuario_id))
    conn.commit()
    registrar_bitacora("PERFIL_ACTUALIZADO", g.usuario_id)

    # 3. Regresar los datos como quedaron
    perfil = query("""SELECT nombre, apellidos, correo, telefono, fecha_nacimiento, sexo
                      FROM usuarios WHERE id = %s""", (g.usuario_id,), one=True)
    return jsonify(mensaje="Tus datos se actualizaron", usuario=perfil)


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

    compras = query("""SELECT v.folio, v.estado, s.nombre AS sucursal, v.pagada_en, v.articulos,
                              v.subtotal, v.ahorro, v.puntos_usados, v.descuento_puntos,
                              v.total, v.puntos_ganados, v.tarjeta_marca, v.tarjeta_ultimos4
                       FROM ventas v JOIN sucursales s ON s.id = v.sucursal_id
                       WHERE v.usuario_id = %s ORDER BY v.pagada_en DESC""", (g.usuario_id,))
    puntos = query("""SELECT tipo, puntos, saldo_final, nota, fecha FROM movimientos_puntos
                      WHERE usuario_id = %s ORDER BY id DESC""", (g.usuario_id,))
    opiniones = query("""SELECT p.nombre AS producto, o.estrellas, o.comentario, o.estado,
                                o.creada_en, o.editada_en,
                                (SELECT COUNT(*) FROM opinion_fotos f
                                 WHERE f.opinion_id = o.id) AS fotos
                         FROM opiniones o JOIN productos p ON p.id = o.producto_id
                         WHERE o.usuario_id = %s ORDER BY o.creada_en DESC""", (g.usuario_id,))

    registrar_bitacora("DATOS_EXPORTADOS", g.usuario_id, perfil["correo"])
    return jsonify(
        generado_en=datetime.now(),
        aviso="Esta es una copia de los datos personales que MARK'S tiene sobre ti.",
        perfil=perfil,
        aviso_privacidad_aceptado=consentimiento,
        historial_de_accesos=accesos,
        compras=compras,                 # PASO 10
        movimientos_de_puntos=puntos,    # PASO 11
        opiniones=opiniones,             # PASO 13
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

    # Sus opiniones y fotos se BORRAN (son contenido público que escribió el titular)
    fotos = [f["archivo"] for f in query(
        """SELECT f.archivo FROM opinion_fotos f JOIN opiniones o ON o.id = f.opinion_id
           WHERE o.usuario_id = %s""", (u["id"],))]

    # Se ANONIMIZA en lugar de borrar la fila: así las compras (PASO 10)
    # se conservan para contabilidad, pero ya sin datos que identifiquen a la persona.
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM opiniones WHERE usuario_id = %s", (u["id"],))
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
    borrar_fotos(current_app.config["UPLOADS_OPINIONES"], fotos)

    return jsonify(mensaje="Tu cuenta fue eliminada. Gracias por usar MARK'S")