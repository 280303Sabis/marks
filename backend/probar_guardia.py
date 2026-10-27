"""
Pruebas del PASO W12: el guardia valida el QR de salida.

Cómo correrlo:
    cd backend
    python probar_guardia.py

Crea un guardia, un cliente y dos compras de prueba (una en cada sucursal)
directo en la base, sin mover inventario ni puntos. Prueba el QR auténtico,
el alterado, el folio escrito, la otra sucursal y el QR usado dos veces.
Al final BORRA las compras y los usuarios de prueba.
"""
import uuid

from werkzeug.security import generate_password_hash

from app import create_app
from app.db import get_db, query
from app.utils.qr import texto_qr
from app.utils.seguridad import crear_token

CORREOS = ("prueba.guardia.w12@marks.test", "prueba.cliente.w12@marks.test")
FOLIOS = ("MK-991231-000001", "MK-991231-000002", "MK-991231-000003")

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
    ejecutar("DELETE FROM ventas WHERE folio IN (%s, %s, %s)", FOLIOS)   # el detalle se borra en cascada
    for u in query("SELECT id FROM usuarios WHERE correo IN (%s, %s)", CORREOS):
        ejecutar("DELETE FROM bitacora_accesos WHERE usuario_id = %s", (u["id"],))
        ejecutar("DELETE FROM usuarios WHERE id = %s", (u["id"],))


def crear_usuario(correo, rol_id, rol, nombre, apellidos=None):
    uid = ejecutar("""INSERT INTO usuarios (nombre, apellidos, correo, password_hash, rol_id,
                                            correo_verificado, acepto_privacidad_en,
                                            version_aviso_privacidad)
                      VALUES (%s, %s, %s, %s, %s, 1, NOW(), %s)""",
                   (nombre, apellidos, correo, generate_password_hash("sin-login"), rol_id,
                    app.config["AVISO_PRIVACIDAD_VERSION"]))
    return uid, {"Authorization": "Bearer " + crear_token({"id": uid, "rol": rol, "token_version": 1})}


def crear_venta(folio, usuario_id, sucursal_id, estado="PAGADA"):
    producto = query("SELECT id, codigo_barras, nombre FROM productos ORDER BY id LIMIT 1", one=True)
    vid = ejecutar("""INSERT INTO ventas (folio, clave_pago, usuario_id, sucursal_id, articulos,
                                          subtotal, ahorro, total, tarjeta_marca, tarjeta_ultimos4, estado)
                      VALUES (%s, %s, %s, %s, 2, 57.00, 0, 57.00, 'VISA', '4242', %s)""",
                   (folio, str(uuid.uuid4()), usuario_id, sucursal_id, estado))
    ejecutar("""INSERT INTO venta_detalle (venta_id, producto_id, codigo, nombre, tipo_venta, cantidad,
                                           precio, precio_final, importe, importe_normal)
                VALUES (%s, %s, %s, %s, 'UNIDAD', 2, 28.50, 28.50, 57.00, 57.00)""",
             (vid, producto["id"], producto["codigo_barras"], producto["nombre"]))
    return vid


def validar(headers, **datos):
    return cliente.post("/api/guardia/validar", headers=headers, json=datos)


with app.app_context():
    limpiar()
    sucursales = [s["id"] for s in query("SELECT id FROM sucursales WHERE activa = 1 ORDER BY id")]
    S1 = sucursales[0]
    S2 = sucursales[1] if len(sucursales) > 1 else None
    try:
        guardia_id, GUARDIA = crear_usuario(CORREOS[0], 3, "GUARDIA", "Guardia", "Prueba")
        cliente_id, CLIENTE = crear_usuario(CORREOS[1], 1, "CLIENTE", "Sabina", "Ortega")
        crear_venta(FOLIOS[0], cliente_id, S1)
        if S2:
            crear_venta(FOLIOS[1], cliente_id, S2)
        crear_venta(FOLIOS[2], cliente_id, S1, estado="CANCELADA")
        QR = texto_qr(FOLIOS[0])

        # ---------- Permisos ----------
        r = validar({}, qr=QR, sucursal_id=S1)
        revisar("Validar sin sesión: 401", r.status_code == 401, r.status_code)
        r = validar(CLIENTE, qr=QR, sucursal_id=S1)
        revisar("Un cliente no puede validar: 403", r.status_code == 403, r.status_code)

        # ---------- Errores ----------
        r = validar(GUARDIA, qr=QR)
        revisar("Sin sucursal: 400", r.status_code == 400, r.get_json())
        alterado = QR[:-3] + ("AAA" if not QR.endswith("AAA") else "BBB")
        r = validar(GUARDIA, qr=alterado, sucursal_id=S1)
        revisar("QR con la firma alterada: 400 QR_INVALIDO",
                r.status_code == 400 and r.get_json()["codigo"] == "QR_INVALIDO", r.get_json())
        r = validar(GUARDIA, qr=QR.replace("000001", "000009"), sucursal_id=S1)
        revisar("QR con otro folio y la misma firma: 400 QR_INVALIDO",
                r.status_code == 400 and r.get_json()["codigo"] == "QR_INVALIDO", r.get_json())
        r = validar(GUARDIA, qr="https://otra-pagina.com", sucursal_id=S1)
        revisar("Un QR que no es de MARK'S: 400 QR_INVALIDO",
                r.status_code == 400 and r.get_json()["codigo"] == "QR_INVALIDO", r.get_json())
        r = validar(GUARDIA, folio="MK-12", sucursal_id=S1)
        revisar("Folio escrito incompleto: 400 FOLIO_INVALIDO",
                r.status_code == 400 and r.get_json()["codigo"] == "FOLIO_INVALIDO", r.get_json())
        r = validar(GUARDIA, qr=texto_qr("MK-991231-000099"), sucursal_id=S1)
        revisar("QR auténtico de un folio que no existe: 404 NO_EXISTE",
                r.status_code == 404 and r.get_json()["codigo"] == "NO_EXISTE", r.get_json())
        if S2:
            r = validar(GUARDIA, qr=texto_qr(FOLIOS[1]), sucursal_id=S1)
            revisar("Compra de otra sucursal: 409 OTRA_SUCURSAL",
                    r.status_code == 409 and r.get_json()["codigo"] == "OTRA_SUCURSAL", r.get_json())
        r = validar(GUARDIA, qr=texto_qr(FOLIOS[2]), sucursal_id=S1)
        revisar("Compra cancelada: 409 CANCELADA",
                r.status_code == 409 and r.get_json()["codigo"] == "CANCELADA", r.get_json())
        revisar("Los intentos rechazados no validaron nada",
                query("SELECT estado FROM ventas WHERE folio = %s", (FOLIOS[0],), one=True)["estado"]
                == "PAGADA")

        # ---------- Validar ----------
        r = validar(GUARDIA, qr=QR, sucursal_id=S1)
        d = r.get_json()
        revisar("QR auténtico: 200 'puede salir'", r.status_code == 200, d)
        revisar("Responde folio, cliente corto, artículos, total y productos",
                d["venta"]["folio"] == FOLIOS[0] and d["venta"]["cliente"] == "Sabina O."
                and d["venta"]["articulos"] == 2 and d["venta"]["total"] == 57
                and len(d["venta"]["productos"]) == 1, d)
        v = query("SELECT estado, validada_en, validada_por FROM ventas WHERE folio = %s",
                  (FOLIOS[0],), one=True)
        revisar("En la base: VALIDADA con fecha y el guardia",
                v["estado"] == "VALIDADA" and v["validada_en"] and v["validada_por"] == guardia_id, v)

        r = validar(GUARDIA, qr=QR, sucursal_id=S1)
        d = r.get_json()
        revisar("El mismo QR otra vez: 409 YA_VALIDADA con cuándo y quién",
                r.status_code == 409 and d["codigo"] == "YA_VALIDADA"
                and d["venta"]["validada_en"] and d["venta"]["validada_por"] == "Guardia Prueba", d)

        r = cliente.get(f"/api/compras/{FOLIOS[0]}", headers=CLIENTE)
        venta_app = r.get_json().get("venta", {})
        revisar("En la app la compra ya dice VALIDADA y ya no trae QR",
                r.status_code == 200 and venta_app.get("estado") == "VALIDADA"
                and venta_app.get("qr") is None, r.get_json())

        # ---------- Folio escrito ----------
        if S2:
            r = validar(GUARDIA, folio=FOLIOS[1].lower(), sucursal_id=S2)
            revisar("Folio escrito a mano (en minúsculas) en su sucursal: 200",
                    r.status_code == 200 and r.get_json()["forma"] == "FOLIO", r.get_json())

        # ---------- Resumen ----------
        r = cliente.get(f"/api/guardia/resumen?sucursal_id={S1}", headers=GUARDIA)
        d = r.get_json()
        revisar("Resumen de hoy: incluye la validación con su hora",
                r.status_code == 200 and d["validadas_hoy"] >= 1
                and any(u["folio"] == FOLIOS[0] and len(u["hora"]) == 5 for u in d["ultimas"]), d)
        r = cliente.get(f"/api/guardia/resumen?sucursal_id={S1}", headers=CLIENTE)
        revisar("Un cliente no ve el resumen: 403", r.status_code == 403, r.status_code)

    finally:
        limpiar()

    revisar("Limpieza: no quedaron compras ni usuarios de prueba",
            not query("SELECT 1 FROM ventas WHERE folio IN (%s, %s, %s)", FOLIOS, one=True)
            and not query("SELECT 1 FROM usuarios WHERE correo IN (%s, %s)", CORREOS, one=True))

print(f"\n{sum(resultados)} de {len(resultados)} pruebas correctas")