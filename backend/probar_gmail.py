"""
Diagnóstico y prueba de envío REAL por Gmail.
Uso:   python probar_gmail.py

1. Revisa que el .env tenga los datos (la contraseña nunca se muestra).
2. Prueba si la red deja conectar a Gmail por los puertos 465 y 587.
3. Envía un correo de prueba mostrando cada paso, sin mostrar datos sensibles.
"""
import smtplib
import socket
import ssl

from app import create_app
from app.utils.correo import conectar, crear_mensaje, iniciar_sesion, plantilla_codigo

app = create_app()


def ocultar(texto):
    """Muestra solo el inicio y el final: abcd********mnop"""
    if len(texto) <= 4:
        return "*" * len(texto)
    return texto[:2] + "*" * (len(texto) - 4) + texto[-2:]


def revisar_puerto(puerto):
    """Abre una conexión de prueba y revisa que quien responde sea Gmail."""
    try:
        with socket.create_connection(("smtp.gmail.com", puerto), timeout=8) as s:
            s.settimeout(8)
            if puerto == 465:
                with ssl.create_default_context().wrap_socket(s, server_hostname="smtp.gmail.com") as ss:
                    saludo = ss.recv(200).decode(errors="ignore").strip()
            else:
                saludo = s.recv(200).decode(errors="ignore").strip()
        if saludo.startswith("220") and "smtp.gmail.com" in saludo:
            return True, "Gmail respondió correctamente"
        return False, f"respondió algo inesperado: {saludo[:50] or '(nada)'}"
    except Exception as e:
        return False, f"no se pudo conectar ({e})"


def paso(texto):
    print(f"  {texto:<48}", end="", flush=True)


with app.app_context():
    cfg = app.config

    print("\n=== 1. Configuración (.env) ===")
    print(f"  Modo:        {cfg['MAIL_MODO']}")
    print(f"  Remitente:   {cfg['MAIL_USUARIO'] or '(vacío)'}")
    print(f"  Puerto:      {cfg['MAIL_PUERTO']}")
    print(f"  Contraseña:  {ocultar(cfg['MAIL_PASSWORD'])}  ({len(cfg['MAIL_PASSWORD'])} caracteres, deben ser 16)")
    if cfg["MAIL_MODO"] != "gmail":
        raise SystemExit("\nAVISO: MAIL_MODO no es 'gmail'. Cámbialo en el .env para enviar correos reales.")
    if not cfg["MAIL_USUARIO"] or len(cfg["MAIL_PASSWORD"]) != 16:
        raise SystemExit("\nERROR: revisa MAIL_USUARIO y MAIL_PASSWORD (16 letras) en el .env")

    print("\n=== 2. ¿La red deja conectar a Gmail? ===")
    for puerto in (465, 587):
        ok, detalle = revisar_puerto(puerto)
        print(f"  Puerto {puerto}:  {'OK   ' if ok else 'FALLA'} {detalle}")

    print("\n=== 3. Envío de prueba ===")
    destino = input("  Correo de destino (Gmail, Outlook, iCloud...): ").strip()
    texto, html = plantilla_codigo("Prueba", "123456", "probar la configuración", 15)
    print()

    try:
        paso(f"Conectando a smtp.gmail.com:{cfg['MAIL_PUERTO']} (cifrado)...")
        smtp = conectar(cfg["MAIL_PUERTO"])
        print("OK")

        paso("Iniciando sesión (contraseña oculta)...")
        codigo, _ = iniciar_sesion(smtp, cfg["MAIL_USUARIO"], cfg["MAIL_PASSWORD"])
        print(f"OK  (Gmail respondió {codigo}: sesión aceptada)")

        paso(f"Enviando correo a {destino}...")
        smtp.send_message(crear_mensaje(destino, "MARK'S - Correo de prueba", texto, html))
        print("OK  (Gmail aceptó el correo)")
        smtp.quit()

        print("\nRESULTADO: correo enviado. Revisa la bandeja de entrada y la de correo no deseado.")

    except smtplib.SMTPAuthenticationError as e:
        print(f"ERROR {e.smtp_code}")
        print("\nRESULTADO: Gmail rechazó el usuario o la contraseña de aplicación.")
        print("  - Revisa que la contraseña de aplicación sea de la cuenta", cfg["MAIL_USUARIO"])
        print("  - Revisa que la verificación en 2 pasos siga activa")
    except smtplib.SMTPRecipientsRefused:
        print("ERROR")
        print(f"\nRESULTADO: Gmail rechazó el correo de destino '{destino}'. Revisa que esté bien escrito.")
    except Exception as e:
        print("ERROR")
        print(f"\nRESULTADO: no se pudo completar el envío: {e}")