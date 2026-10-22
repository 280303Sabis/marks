"""
QR DE SALIDA FIRMADO

  El QR que muestra la app al pagar contiene un texto como:
      MARKS1.MK-261022-000001.k3Jf9...Qw
      |      |                └─ firma (HMAC-SHA256, 22 caracteres)
      |      └─ folio de la venta
      └─ versión del formato

  La firma se calcula con una clave secreta que solo conoce la API.
  Si alguien cambia el folio o inventa un QR, la firma ya no coincide
  y el guardia lo verá como QR no válido.

  La clave se deriva de JWT_SECRET con un propósito distinto ("qr-salida"),
  así no se necesita otra variable en el .env y un token de sesión
  nunca sirve como QR (ni al revés).
"""
import base64
import hashlib
import hmac
import re

from flask import current_app

VERSION = "MARKS1"
FOLIO_VALIDO = re.compile(r"^MK-\d{6}-\d{6}$")


def _clave():
    secreto = current_app.config["JWT_SECRET"].encode()
    return hmac.new(secreto, b"qr-salida", hashlib.sha256).digest()


def _firma(folio):
    digest = hmac.new(_clave(), f"{VERSION}.{folio}".encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest[:16]).decode().rstrip("=")


def texto_qr(folio):
    """Texto que se dibuja en el QR."""
    return f"{VERSION}.{folio}.{_firma(folio)}"


def leer_qr(texto):
    """Devuelve el folio si el QR es auténtico; si no, None.
       (Lo usará el guardia en la web, PASO W16.)"""
    partes = (texto or "").strip().split(".")
    if len(partes) != 3 or partes[0] != VERSION or not FOLIO_VALIDO.match(partes[1]):
        return None
    if not hmac.compare_digest(partes[2], _firma(partes[1])):
        return None
    return partes[1]