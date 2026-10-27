"""
Pruebas del PASO W13: ajuste manual de puntos en el portal del administrador.

IMPORTANTE: córrelo SOLO con tu base LOCAL (.env.local), nunca con Aiven:
    cd backend
    Copy-Item .env.local .env -Force
    python probar_puntos_admin.py
    Copy-Item .env.aiven .env -Force

Crea un administrador y dos clientes de prueba. Prueba la lista de clientes,
el estado de cuenta, sumar y quitar puntos, los errores y que el cliente vea
el ajuste en "Mis puntos" de la app.
Al final BORRA los movimientos y los usuarios de prueba.
"""
from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.seguridad import crear_token

CORREOS = ("prueba.admin.pts@marks.test", "prueba.cliente.pts@marks.test",
           "prueba.inactivo.pts@marks.test")

app = create_app()
cliente = app.test_client()
resultados = []


def revisar(nombre, condicion, extra=""):
    condicion = bool(condicion)
    resultados.append(condicion)
    print(f"{'OK   ' if condicion else 'FALLA'} {len(resultados):>2}. {nombre}"
          + (f"  -> {extra}" if extra and not condicion else ""))


def ejecutar(sql, params=()):
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(sql, params)
        nuevo_id = cur.lastrowid
    conn.commit()
    return nuevo_id


def limpiar():
    marcas = ",".join(["%s"] * len(CORREOS))
    for u in query(f"SELECT id FROM usuarios WHERE correo IN ({marcas})", CORREOS):
        ejecutar("DELETE FROM movimientos_puntos WHERE usuario_id = %s", (u["id"],))
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (u["id"],))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (u["id"],))


def crear_usuario(correo, rol_id, rol, nombre="Prueba", apellidos=None, puntos=0, activo=1):
    uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash, rol_id,
                                            puntos_saldo, activo, correo_verificado,
                                            acepto_privacidad_en, version_aviso_privacidad)
                      VALUES (%s, %s, %s, %s, %s, %s, %s, 1, NOW(), %s)""",
                   (nombre, apellidos, correo, generate_password_hash("sin-login"), rol_id,
                    puntos, activo, app.config["AVISO_PRIVACIDAD_VERSION"]))
    return uid, {"Authorization": "Bearer " + crear_token({"id": uid, "rol": rol, "token_version": 1})}


def saldo(uid):
    return query("SELECT puntos_saldo FROM usuarios WHERE id = %s", (uid,), one=True)["puntos_saldo"]


with app.app_context():
    limpiar()
    try:
        admin_id, ADMIN = crear_usuario(CORREOS[0], 2, "ADMIN")
        cli_id, CLIENTE = crear_usuario(CORREOS[1], 1, "CLIENTE", "Pruebita", "Puntos", puntos=120)
        inactivo_id, _ = crear_usuario(CORREOS[2], 1, "CLIENTE", "Inactivo", puntos=10, activo=0)
        url = f"/api/admin/clientes/{cli_id}/puntos"

        # ---------- Permisos ----------
        r = cliente.get("/api/admin/clientes")
        revisar("Lista sin sesión: 401", r.status_code == 401, r.status_code)
        r = cliente.get("/api/admin/clientes", headers=CLIENTE)
        revisar("Lista con sesión de cliente: 403", r.status_code == 403, r.status_code)
        r = cliente.post(url, headers=CLIENTE, json={"puntos": 1000, "motivo": "Me los regalo"})
        revisar("Un cliente no puede darse puntos: 403", r.status_code == 403, r.status_code)

        # ---------- Lista ----------
        r = cliente.get("/api/admin/clientes?buscar=pts@marks.test", headers=ADMIN)
        d = r.get_json()
        c = next((x for x in d.get("clientes", []) if x["id"] == cli_id), None)
        revisar("Buscar por correo: aparece el cliente", r.status_code == 200 and c, d)
        revisar("Trae nombre completo, puntos y compras",
                c and c["nombre"] == "Pruebita Puntos" and c["puntos"] == 120 and c["compras"] == 0, c)
        revisar("No lista al administrador", all(x["id"] != admin_id for x in d["clientes"]), d)
        revisar("Resumen con clientes y puntos en circulación",
                d["resumen"]["clientes"] >= 1 and d["resumen"]["puntos_en_circulacion"] >= 120, d["resumen"])
        r = cliente.get("/api/admin/clientes?buscar=Pruebita&orden=nombre", headers=ADMIN)
        revisar("Buscar por nombre y ordenar por nombre",
                r.get_json()["orden"] == "nombre"
                and any(x["id"] == cli_id for x in r.get_json()["clientes"]), r.get_json())
        r = cliente.get("/api/admin/clientes?orden=hackeo", headers=ADMIN)
        revisar("Orden inválido: usa 'puntos'", r.get_json()["orden"] == "puntos", r.get_json())

        # ---------- Errores del ajuste ----------
        r = cliente.post(url, headers=ADMIN, json={"puntos": 0, "motivo": "Prueba de cero"})
        revisar("Cero puntos: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": 5001, "motivo": "Demasiados puntos"})
        revisar("Más de 5,000: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": "50", "motivo": "Texto en vez de número"})
        revisar("Puntos como texto: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": 10.5, "motivo": "Con decimales"})
        revisar("Puntos con decimales: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": True, "motivo": "Booleano raro"})
        revisar("Puntos true/false: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": 50, "motivo": "  ok "})
        revisar("Motivo muy corto: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": 50, "motivo": "x" * 151})
        revisar("Motivo de 151 letras: 400", r.status_code == 400, r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": -121, "motivo": "Quitar de más"})
        revisar("Quitar más de lo que tiene: 409 SALDO_INSUFICIENTE",
                r.status_code == 409 and r.get_json().get("codigo") == "SALDO_INSUFICIENTE"
                and r.get_json().get("saldo") == 120, r.get_json())
        r = cliente.post(f"/api/admin/clientes/{inactivo_id}/puntos", headers=ADMIN,
                         json={"puntos": 10, "motivo": "Cuenta desactivada"})
        revisar("Cuenta desactivada: 409 CUENTA_INACTIVA",
                r.status_code == 409 and r.get_json().get("codigo") == "CUENTA_INACTIVA", r.get_json())
        r = cliente.post(f"/api/admin/clientes/{admin_id}/puntos", headers=ADMIN,
                         json={"puntos": 10, "motivo": "Al administrador"})
        revisar("A un administrador: 404 (solo clientes)", r.status_code == 404, r.status_code)
        r = cliente.post("/api/admin/clientes/999999999/puntos", headers=ADMIN,
                         json={"puntos": 10, "motivo": "No existe"})
        revisar("Cliente que no existe: 404", r.status_code == 404, r.status_code)
        revisar("Los intentos fallidos no cambiaron el saldo ni crearon movimientos",
                saldo(cli_id) == 120 and not query("SELECT id FROM movimientos_puntos WHERE usuario_id = %s",
                                                   (cli_id,)), saldo(cli_id))

        # ---------- Sumar ----------
        r = cliente.post(url, headers=ADMIN,
                         json={"puntos": 50, "motivo": "  Compensación   por producto dañado  "})
        d = r.get_json()
        revisar("Sumar 50 puntos: 200", r.status_code == 200 and d["saldo"] == 170
                and d["saldo_anterior"] == 120, d)
        revisar("El saldo quedó en 170 en la base", saldo(cli_id) == 170, saldo(cli_id))
        m = query("""SELECT tipo, puntos, saldo_final, nota, venta_id FROM movimientos_puntos
                     WHERE usuario_id = %s ORDER BY id DESC LIMIT 1""", (cli_id,), one=True)
        revisar("Movimiento AJUSTE +50, saldo final 170 y motivo sin espacios de más",
                m and m["tipo"] == "AJUSTE" and m["puntos"] == 50 and m["saldo_final"] == 170
                and m["nota"] == "Compensación por producto dañado" and m["venta_id"] is None, m)

        # ---------- Quitar ----------
        r = cliente.post(url, headers=ADMIN, json={"puntos": -70, "motivo": "Corrección de puntos duplicados"})
        revisar("Quitar 70 puntos: 200 y saldo 100", r.status_code == 200 and r.get_json()["saldo"] == 100,
                r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": -100, "motivo": "Dejar en cero"})
        revisar("Quitar todo: el saldo puede quedar en 0", r.status_code == 200 and saldo(cli_id) == 0,
                r.get_json())
        r = cliente.post(url, headers=ADMIN, json={"puntos": 100, "motivo": "Regresar los puntos"})
        revisar("Volver a sumar 100", r.status_code == 200 and saldo(cli_id) == 100, r.get_json())

        # ---------- Estado de cuenta (admin) ----------
        r = cliente.get(url, headers=ADMIN)
        d = r.get_json()
        revisar("Estado de cuenta: 200 con el cliente y su saldo",
                r.status_code == 200 and d["cliente"]["puntos"] == 100
                and d["cliente"]["correo"] == CORREOS[1], d.get("cliente"))
        revisar("4 movimientos, el más nuevo primero",
                [x["puntos"] for x in d["movimientos"]] == [100, -100, -70, 50], d["movimientos"])
        revisar("Cada movimiento trae tipo en texto y fecha",
                all(x["tipo_texto"] == "Ajuste manual" and x["fecha"] for x in d["movimientos"]),
                d["movimientos"])
        r = cliente.get("/api/admin/clientes/999999999/puntos", headers=ADMIN)
        revisar("Estado de cuenta de un cliente que no existe: 404", r.status_code == 404, r.status_code)

        # ---------- Lo que ve el cliente en la app ----------
        r = cliente.get("/api/puntos/movimientos", headers=CLIENTE)
        d = r.get_json()
        revisar("El cliente ve su saldo nuevo en 'Mis puntos'", r.status_code == 200 and d["saldo"] == 100, d)
        revisar("Y el ajuste con su motivo",
                any(x["tipo"] == "AJUSTE" and x["nota"] == "Compensación por producto dañado"
                    for x in d["movimientos"]), d["movimientos"])

        r = cliente.get("/api/admin/clientes?buscar=pts@marks.test", headers=ADMIN)
        revisar("El resumen cuenta los ajustes de los últimos 30 días",
                r.get_json()["resumen"]["ajustes_30_dias"] >= 4, r.get_json()["resumen"])
    finally:
        limpiar()

    quedan = query("SELECT COUNT(*) AS n FROM usuarios WHERE correo LIKE %s", ("%pts@marks.test",), one=True)
    revisar("Limpieza: no quedaron usuarios ni movimientos de prueba", quedan["n"] == 0, quedan)

    print(f"\n{sum(resultados)} de {len(resultados)} pruebas correctas")