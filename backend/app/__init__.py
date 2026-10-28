"""Fábrica de la aplicación Flask de MARK'S."""
from datetime import date, datetime
from decimal import Decimal

from flask import Flask, jsonify
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS

from . import db
from .config import Config
from .utils.fechas import a_hora_mx   # PASO W14: fechas con la hora de Monterrey


class MarksJSON(DefaultJSONProvider):
    """Convierte Decimal a número y fechas a texto ISO (fácil de leer en Flutter).
       Las fechas con hora salen con la hora de Monterrey (PASO W14, utils/fechas.py)."""
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, datetime):
            return a_hora_mx(o).isoformat()
        if isinstance(o, date):
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

    CORS(app)          # permite peticiones desde la app Flutter y la página web
    db.init_app(app)   # registra el cierre automático de la conexión

    # Rutas (blueprints)
    from .routes.productos import bp as productos_bp
    from .routes.carrito import bp as carrito_bp
    from .routes.auth import bp as auth_bp
    from .routes.verificacion import bp as verificacion_bp
    from .routes.cuenta import bp as cuenta_bp
    from .routes.compras import bp as compras_bp
    from .routes.opiniones import bp as opiniones_bp          # PASO 13
    from .routes.admin import bp as admin_bp                  # portal web del administrador
    from .routes.admin_inventario import bp as admin_inventario_bp  # PASO W9: inventario y kárdex
    from .routes.admin_productos import bp as admin_productos_bp    # PASO W10: productos
    from .routes.admin_opiniones import bp as admin_opiniones_bp    # PASO W11: moderación de opiniones
    from .routes.guardia import bp as guardia_bp                    # PASO W12: guardia (QR de salida)
    from .routes.admin_puntos import bp as admin_puntos_bp          # PASO W13: puntos de los clientes
    app.register_blueprint(productos_bp, url_prefix="/api")
    app.register_blueprint(carrito_bp, url_prefix="/api")
    app.register_blueprint(auth_bp, url_prefix="/api/auth")
    app.register_blueprint(verificacion_bp, url_prefix="/api/auth")
    app.register_blueprint(cuenta_bp, url_prefix="/api")
    app.register_blueprint(compras_bp, url_prefix="/api")
    app.register_blueprint(opiniones_bp, url_prefix="/api")    # PASO 13
    app.register_blueprint(admin_bp, url_prefix="/api/admin")
    app.register_blueprint(admin_inventario_bp, url_prefix="/api/admin")   # PASO W9
    app.register_blueprint(admin_productos_bp, url_prefix="/api/admin")    # PASO W10
    app.register_blueprint(admin_opiniones_bp, url_prefix="/api/admin")    # PASO W11
    app.register_blueprint(guardia_bp, url_prefix="/api/guardia")          # PASO W12
    app.register_blueprint(admin_puntos_bp, url_prefix="/api/admin")      # PASO W13

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