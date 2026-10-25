"""
Envío de correos de MARK'S.

  MAIL_MODO=gmail   -> usa el servidor SMTP de Gmail con una contraseña de aplicación
  MAIL_MODO=brevo   -> usa la API de Brevo por HTTPS (para Render gratis, que
                       bloquea los puertos SMTP). Requiere BREVO_API_KEY.
  MAIL_MODO=consola -> no envía nada, imprime el correo en la terminal de Flask

  MAIL_PUERTO=465   -> conexión cifrada desde el inicio (SSL). Recomendado.
  MAIL_PUERTO=587   -> conexión que se cifra después (STARTTLS).

Seguridad: este módulo NUNCA imprime la contraseña, la API key ni la conversación con Gmail.
"""
import json
import smtplib
import ssl
import urllib.error
import urllib.request
from email.message import EmailMessage
from email.utils import formataddr

from flask import current_app

GMAIL_SERVIDOR = "smtp.gmail.com"
BREVO_URL = "https://api.brevo.com/v3/smtp/email"


def conectar(puerto):
    """Abre la conexión con Gmail ya cifrada y lista para iniciar sesión."""
    contexto = ssl.create_default_context()
    if puerto == 465:
        smtp = smtplib.SMTP_SSL(GMAIL_SERVIDOR, 465, timeout=20, context=contexto)
    else:
        smtp = smtplib.SMTP(GMAIL_SERVIDOR, puerto, timeout=20)
        smtp.ehlo()
        smtp.starttls(context=contexto)
    smtp.ehlo()
    return smtp


def iniciar_sesion(smtp, usuario, password):
    """
    Inicia sesión solo con el método PLAIN: si Gmail rechaza la contraseña,
    lanza SMTPAuthenticationError con un error claro
    (y no "Connection unexpectedly closed").
    """
    smtp.user, smtp.password = usuario, password
    return smtp.auth("PLAIN", smtp.auth_plain)


def crear_mensaje(destinatario, asunto, texto, html=None):
    cfg = current_app.config
    msg = EmailMessage()
    msg["Subject"] = asunto
    msg["From"] = formataddr((cfg["MAIL_NOMBRE_REMITENTE"], cfg["MAIL_USUARIO"]))
    msg["To"] = destinatario
    msg.set_content(texto)
    if html:
        msg.add_alternative(html, subtype="html")
    return msg


def enviar_con_brevo(destinatario, asunto, texto, html=None):
    """
    Manda el correo con la API de Brevo (HTTPS, puerto 443).
    El remitente (MAIL_USUARIO) debe estar verificado en Brevo como "sender".
    """
    cfg = current_app.config
    datos = {
        "sender": {"name": cfg["MAIL_NOMBRE_REMITENTE"], "email": cfg["MAIL_USUARIO"]},
        "to": [{"email": destinatario}],
        "subject": asunto,
        "textContent": texto,
    }
    if html:
        datos["htmlContent"] = html

    peticion = urllib.request.Request(
        BREVO_URL,
        data=json.dumps(datos).encode("utf-8"),
        headers={
            "api-key": cfg["BREVO_API_KEY"],
            "accept": "application/json",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(peticion, timeout=20):
            return True
    except urllib.error.HTTPError as e:
        # Brevo explica el problema en el cuerpo (API key mala, remitente sin verificar...)
        detalle = e.read().decode("utf-8", errors="replace")[:300]
        current_app.logger.error(f"Brevo rechazó el correo a {destinatario} "
                                 f"(HTTP {e.code}): {detalle}")
        return False
    except Exception as e:
        current_app.logger.error(f"No se pudo enviar el correo a {destinatario} con Brevo: {e}")
        return False


def enviar_correo(destinatario, asunto, texto, html=None):
    """Devuelve True si se envió (o se imprimió) y False si hubo un error."""
    cfg = current_app.config

    if cfg["MAIL_MODO"] == "brevo":
        return enviar_con_brevo(destinatario, asunto, texto, html)

    if cfg["MAIL_MODO"] != "gmail":
        print("\n" + "=" * 60)
        print(f"  CORREO (modo consola) para: {destinatario}")
        print(f"  Asunto: {asunto}")
        print("-" * 60)
        print(texto)
        print("=" * 60 + "\n", flush=True)
        return True

    try:
        with conectar(cfg["MAIL_PUERTO"]) as smtp:
            iniciar_sesion(smtp, cfg["MAIL_USUARIO"], cfg["MAIL_PASSWORD"])
            smtp.send_message(crear_mensaje(destinatario, asunto, texto, html))
        return True
    except smtplib.SMTPAuthenticationError:
        current_app.logger.error("Gmail rechazó el usuario o la contraseña de aplicación. "
                                 "Revisa MAIL_USUARIO y MAIL_PASSWORD en el .env")
        return False
    except Exception as e:
        current_app.logger.error(f"No se pudo enviar el correo a {destinatario} "
                                 f"(puerto {cfg['MAIL_PUERTO']}): {e}")
        return False


def plantilla_codigo(nombre, codigo, motivo, minutos):
    """Arma el texto y el HTML del correo con el código de 6 dígitos."""
    texto = (f"Hola {nombre}:\n\n"
             f"Tu código para {motivo} es: {codigo}\n\n"
             f"Vence en {minutos} minutos. Si tú no lo solicitaste, ignora este mensaje.\n\n"
             f"MARK'S - Compra sin filas")
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;border:1px solid #e3e8e6;border-radius:12px;overflow:hidden">
      <div style="background:#7ED957;padding:18px;text-align:center">
        <span style="color:#ffffff;font-size:26px;font-weight:bold">MARK'S</span>
      </div>
      <div style="padding:24px;color:#243E57">
        <p>Hola <b>{nombre}</b>:</p>
        <p>Tu código para <b>{motivo}</b> es:</p>
        <p style="font-size:34px;font-weight:bold;letter-spacing:8px;text-align:center;
                  background:#EFF3F2;border-radius:8px;padding:14px;margin:18px 0">{codigo}</p>
        <p>Vence en <b>{minutos} minutos</b>.</p>
        <p style="color:#777;font-size:13px">Si tú no solicitaste este código, ignora este mensaje.
           Nunca compartas tu código con nadie.</p>
      </div>
      <div style="background:#243E57;color:#ffffff;text-align:center;padding:10px;font-size:12px">
        MARK'S - Compra sin filas
      </div>
    </div>"""
    return texto, html