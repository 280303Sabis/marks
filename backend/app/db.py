"""Conexión a MySQL con PyMySQL.

Se abre UNA conexión por cada petición que llega a la API
y se cierra automáticamente al terminar la petición.
"""
import pymysql
from flask import current_app, g


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