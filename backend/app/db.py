"""Conexión a MySQL con PyMySQL (local o Aiven con SSL).

Se abre UNA conexión por cada petición que llega a la API
y se cierra automáticamente al terminar la petición.
"""
import os

import pymysql
from flask import current_app, g


def _ssl_config(cfg):
    """Devuelve la configuración SSL si hay certificado CA en el .env."""
    ca = cfg.get("DB_SSL_CA", "")
    if not ca:
        return None  # MySQL local, sin SSL
    if not os.path.isabs(ca):
        # ruta relativa -> se busca dentro de la carpeta backend
        backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        ca = os.path.join(backend, ca)
    if not os.path.isfile(ca):
        raise RuntimeError(f"No se encontró el certificado CA en: {ca}")
    return {"ca": ca}


def get_db():
    """Devuelve la conexión de la petición actual (la crea si no existe)."""
    if "db" not in g:
        cfg = current_app.config
        g.db = pymysql.connect(
            host=cfg["DB_HOST"],
            port=cfg["DB_PORT"],
            user=cfg["DB_USER"],
            password=cfg["DB_PASSWORD"],
            database=cfg["DB_NAME"],
            charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,  # filas como diccionarios
            autocommit=False,
            ssl=_ssl_config(cfg),
        )
    return g.db


def close_db(_error=None):
    """Cierra la conexión al terminar la petición."""
    db = g.pop("db", None)
    if db is not None:
        db.close()


def query(sql, params=None, one=False):
    """Ejecuta un SELECT. Usa SIEMPRE %s para los valores (evita inyección SQL)."""
    with get_db().cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchone() if one else cur.fetchall()


def init_app(app):
    app.teardown_appcontext(close_db)