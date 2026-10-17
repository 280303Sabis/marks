"""Configuración de la API de MARK'S (lee los datos del archivo .env)."""
import os
from dotenv import load_dotenv

from .legal.aviso_privacidad import VERSION as VERSION_AVISO

load_dotenv()  # carga las variables del archivo .env


class Config:
    # ---------- Base de datos ----------
    DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
    DB_PORT = int(os.getenv("DB_PORT", 3306))
    DB_USER = os.getenv("DB_USER", "root")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "marks_db")

    # ---------- Sesión (token JWT) ----------
    JWT_SECRET = os.getenv("JWT_SECRET", "")
    JWT_HORAS_VIGENCIA = 12            # la sesión dura 12 horas

    # ---------- Reglas de seguridad ----------
    MAX_INTENTOS_LOGIN = 3             # intentos fallidos permitidos
    MINUTOS_BLOQUEO = 15               # minutos de bloqueo
    AVISO_PRIVACIDAD_VERSION = VERSION_AVISO  # se toma de app/legal/aviso_privacidad.py

    # ---------- Códigos de verificación (correo) ----------
    CODIGO_MINUTOS_VIGENCIA = 15       # el código caduca en 15 minutos
    CODIGO_MAX_INTENTOS = 5            # intentos para escribir el código
    CODIGO_SEGUNDOS_ESPERA = 60        # tiempo mínimo entre un envío y otro

    # ---------- Envío de correos ----------
    # MAIL_MODO = "gmail"   -> envía correos reales por Gmail
    # MAIL_MODO = "consola" -> solo imprime el correo en la terminal (pruebas)
    MAIL_MODO = os.getenv("MAIL_MODO", "consola").lower()
    MAIL_USUARIO = os.getenv("MAIL_USUARIO", "")
    MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "").replace(" ", "")
    MAIL_PUERTO = int(os.getenv("MAIL_PUERTO", 465))   # 465 = SSL (recomendado) | 587 = STARTTLS
    MAIL_NOMBRE_REMITENTE = "MARK'S"