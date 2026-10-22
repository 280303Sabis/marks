"""Fábrica de la aplicación Flask de MARK'S."""
from datetime import date, datetime
from decimal import Decimal

from flask import Flask, jsonify
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS

from . import db
from .config import Config


class MarksJSON(DefaultJSONProvider):
    """Convierte Decimal a número y fechas a texto ISO (fácil de leer en Flutter)."""
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, (datetime, date)):
            return o.isoformat()
        return super().default(o)


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    if not app.config["JWT_SECRET"]:
        raise RuntimeError("Falta JWT_SECRET en el archivo .env")
    app.json = MarksJSON(app)
    app.json.ensure_ascii = False  # muestra acentos y ñ correctamente
    app.json.sort_keys = False     # respeta el orden en que se escriben los datos

    CORS(app)          # permite peticiones desde la app Flutter
    db.init_app(app)   # registra el cierre automático de la conexión

    # Rutas (blueprints)
    from .routes.productos import bp as productos_bp
    from .routes.carrito import bp as carrito_bp
    from .routes.auth import bp as auth_bp
    from .routes.verificacion import bp as verificacion_bp
    from .routes.cuenta import bp as cuenta_bp
    from .routes.compras import bp as compras_bp
    from .routes.opiniones import bp as opiniones_bp          # PASO 13
    app.register_blueprint(productos_bp, url_prefix="/api")
    app.register_blueprint(carrito_bp, url_prefix="/api")
    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    app.register_blueprint(verificacion_bp, url_prefix="/api/auth")
    app.register_blueprint(cuenta_bp, url_prefix="/api")
    app.register_blueprint(compras_bp, url_prefix="/api")
    app.register_blueprint(opiniones_bp, url_prefix="/api")    # PASO 13

    @app.get("/")
    def inicio():
        """Página de bienvenida: muestra todas las rutas disponibles de la API."""
        rutas = sorted(
            f"{', '.join(sorted(r.methods - {'HEAD', 'OPTIONS'}))}  {r.rule}"
            for r in app.url_map.iter_rules()
            if r.rule.startswith("/api")
        )
        return jsonify(api="MARK'S - Compra sin filas", estado="en línea",
                       total_rutas=len(rutas), rutas=rutas)

    @app.get("/api/salud")
    def salud():
        """Prueba rápida: ¿la API responde y la base de datos conecta?"""
        try:
            fila = db.query("SELECT DATABASE() AS base, VERSION() AS version_mysql", one=True)
            return jsonify(ok=True, api="MARK'S", base_datos=fila["base"],
                           mysql=fila["version_mysql"])
        except Exception as e:
            return jsonify(ok=False, error=str(e)), 500

    @app.errorhandler(404)
    def no_encontrado(_e):
        return jsonify(error="Ruta no encontrada"), 404

    @app.errorhandler(413)
    def demasiado_grande(_e):
        """Cuando la petición pasa de MAX_CONTENT_LENGTH (fotos muy pesadas)."""
        return jsonify(error="Las fotos pesan demasiado. Máximo 5 MB cada una"), 413

    return app