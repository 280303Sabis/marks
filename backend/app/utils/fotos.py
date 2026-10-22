"""
FOTOS DE LAS OPINIONES (PASO 13)

  Reglas:
    - Solo JPG, PNG o WEBP de máximo 5 MB.
    - Se revisa que el archivo DE VERDAD sea una imagen (no basta la extensión).
    - Se vuelve a guardar como JPG de máximo 1280 px por lado:
        * ocupa mucho menos espacio
        * se le QUITAN los metadatos (EXIF), que pueden traer la ubicación GPS
          de donde se tomó la foto
    - El nombre del archivo es aleatorio (no se puede adivinar).
    - Se guardan en backend/uploads/opiniones (esa carpeta NO se sube a GitHub).
"""
import logging
import os
import re
import secrets
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

FORMATOS_PERMITIDOS = {"JPEG", "PNG", "WEBP"}
MAX_BYTES = 5 * 1024 * 1024        # 5 MB por foto
MAX_LADO = 1280                    # px
MAX_FOTOS = 3                      # por opinión
NOMBRE_VALIDO = re.compile(r"^[0-9a-f]{32}\.jpg$")

# Evita "bombas" de imagen (archivos chicos que al abrirse ocupan gigas de memoria)
Image.MAX_IMAGE_PIXELS = 40_000_000


class FotoInvalida(ValueError):
    """La foto no cumple las reglas; el mensaje se muestra al cliente."""


def guardar_foto(archivo, carpeta):
    """Revisa, limpia y guarda una foto subida. Devuelve sus datos para la base."""
    datos = archivo.read(MAX_BYTES + 1)
    if not datos:
        raise FotoInvalida("Una de las fotos está vacía")
    if len(datos) > MAX_BYTES:
        raise FotoInvalida("Cada foto puede pesar máximo 5 MB")

    try:
        with Image.open(BytesIO(datos)) as prueba:
            prueba.verify()                      # ¿de verdad es una imagen?
        imagen = Image.open(BytesIO(datos))
        if imagen.format not in FORMATOS_PERMITIDOS:
            raise FotoInvalida("Solo se aceptan fotos JPG, PNG o WEBP")
        imagen = ImageOps.exif_transpose(imagen)  # respeta la rotación del celular
        if imagen.mode in ("RGBA", "LA", "P"):    # PNG con transparencia: fondo blanco
            imagen = imagen.convert("RGBA")
            fondo = Image.new("RGB", imagen.size, (255, 255, 255))
            fondo.paste(imagen, mask=imagen.split()[-1])
            imagen = fondo
        else:
            imagen = imagen.convert("RGB")
        imagen.thumbnail((MAX_LADO, MAX_LADO))
    except FotoInvalida:
        raise
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError, SyntaxError):
        raise FotoInvalida("Uno de los archivos no es una imagen válida")

    os.makedirs(carpeta, exist_ok=True)
    nombre = f"{secrets.token_hex(16)}.jpg"
    ruta = os.path.join(carpeta, nombre)
    imagen.save(ruta, "JPEG", quality=85, optimize=True)   # sin exif: se quitan los metadatos
    return {"archivo": nombre, "ancho": imagen.width, "alto": imagen.height,
            "bytes": os.path.getsize(ruta)}


def borrar_fotos(carpeta, nombres):
    """Borra los archivos (si alguno ya no existe, no pasa nada)."""
    for nombre in nombres:
        if NOMBRE_VALIDO.match(nombre or ""):
            try:
                os.remove(os.path.join(carpeta, nombre))
            except FileNotFoundError:
                pass
            except OSError as e:
                # Ej. en Windows, si el archivo está abierto por otro programa.
                # La base ya se guardó: la foto ya no se puede ver (no está en la base),
                # solo queda el archivo en la carpeta. Se avisa en la consola y se sigue.
                logging.getLogger(__name__).warning("No se pudo borrar la foto %s: %s", nombre, e)