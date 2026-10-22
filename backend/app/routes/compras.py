"""
COMPRAS (lado del cliente) - PASO 10 y PASO 11 (puntos)

  Solo clientes con sesión iniciada:
    POST /api/compras/pagar        paga el carrito y devuelve el ticket con su QR de salida
    GET  /api/compras/<folio>      vuelve a mostrar una compra (ticket y QR)

  Cuerpo de /compras/pagar:
    {
      "sucursal_id": 1,
      "lineas": [ ...igual que /carrito/cotizar... ],
      "usar_puntos": true,                       <- opcional: canjear puntos (PASO 11)
      "total_esperado": 146.50,                  <- lo que el cliente vio que se cobraría
      "clave_pago": "1b4e28ba-2fa1-11d2-883f-0016d3cca427",   <- nueva en cada intento de pago
      "tarjeta": {"marca": "VISA", "ultimos4": "4242"}
    }

  Reglas:
    - Solo paga quien ya confirmó su correo.
    - El pago es SIMULADO: la API nunca recibe el número completo de la tarjeta.
    - El total lo vuelve a calcular la API (no se confía en la app).
      Si no coincide con total_esperado, NO se cobra y se pide revisar el carrito.
    - Venta, detalle, stock, kárdex y puntos se guardan en UNA transacción:
      si algo falla, no se guarda nada.
    - Si llega dos veces la misma clave_pago (el internet falló y la app reintentó),
      se devuelve la misma venta: nunca se cobra dos veces.
    - Puntos (reglas en utils/puntos.py): se descuentan los usados y se suman
      los ganados al pagar; cada movimiento queda en movimientos_puntos.
"""
import re
from datetime import datetime
from decimal import Decimal, InvalidOperation

import pymysql
from flask import Blueprint, g, jsonify, request

from ..db import get_db, query
from ..utils.puntos import importe_local, puntos_a_ganar, puntos_canjeables
from ..utils.qr import texto_qr
from ..utils.seguridad import registrar_bitacora, requiere_rol
from .carrito import CarritoInvalido, calcular_carrito

bp = Blueprint("compras", __name__)

CLAVE_VALIDA = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
ULTIMOS4_VALIDO = re.compile(r"^\d{4}$")
NUMERO_TARJETA = re.compile(r"\d{12,19}")
MARCAS = {"VISA", "MASTERCARD", "AMEX"}


class SinExistencias(Exception):
    """Otro cliente se llevó el producto mientras este pagaba."""


class PuntosInsuficientes(Exception):
    """El saldo de puntos cambió mientras el cliente pagaba."""


# ------------------------------------------------------------------
# Ticket: lo que la app muestra después de pagar
# ------------------------------------------------------------------
def _ticket(venta_id):
    v = query("""SELECT v.id, v.folio, v.estado, v.sucursal_id, s.nombre AS sucursal,
                        v.articulos, v.subtotal, v.ahorro, v.puntos_usados, v.descuento_puntos,
                        v.total, v.puntos_ganados,
                        v.tarjeta_marca, v.tarjeta_ultimos4, v.pagada_en, v.validada_en
                 FROM ventas v JOIN sucursales s ON s.id = v.sucursal_id
                 WHERE v.id = %s""", (venta_id,), one=True)
    lineas = query("""SELECT nombre, tipo_venta, cantidad, precio, precio_final,
                             importe, importe_normal, es_local
                      FROM venta_detalle WHERE venta_id = %s ORDER BY id""", (venta_id,))
    for l in lineas:
        l["es_local"] = bool(l["es_local"])
        if l["tipo_venta"] == "UNIDAD":
            l["cantidad"] = int(l["cantidad"])
    return {
        "folio": v["folio"],
        "estado": v["estado"],
        "sucursal_id": v["sucursal_id"],
        "sucursal": v["sucursal"],
        "pagada_en": v["pagada_en"],
        "validada_en": v["validada_en"],
        "articulos": v["articulos"],
        "subtotal": v["subtotal"],
        "ahorro": v["ahorro"],
        "puntos_usados": v["puntos_usados"],
        "descuento_puntos": v["descuento_puntos"],
        "total": v["total"],
        "puntos_ganados": v["puntos_ganados"],
        "tarjeta": {"marca": v["tarjeta_marca"], "ultimos4": v["tarjeta_ultimos4"]},
        "lineas": lineas,
        # El QR solo sirve mientras la compra no ha salido de la tienda
        "qr": texto_qr(v["folio"]) if v["estado"] == "PAGADA" else None,
    }


def _venta_por_clave(clave):
    return query("SELECT id, usuario_id FROM ventas WHERE clave_pago = %s", (clave,), one=True)


def _saldo_actual():
    return query("SELECT puntos_saldo FROM usuarios WHERE id = %s",
                 (g.usuario_id,), one=True)["puntos_saldo"]


def _ya_pagada(venta_id):
    return jsonify(mensaje="Esta compra ya estaba pagada", repetida=True,
                   venta=_ticket(venta_id), puntos_saldo=_saldo_actual()), 200


# ------------------------------------------------------------------
# POST /api/compras/pagar
# ------------------------------------------------------------------
@bp.post("/compras/pagar")
@requiere_rol("CLIENTE")
def pagar():
    datos = request.get_json(silent=True) or {}

    # 1. Correo confirmado
    u = query("SELECT correo, correo_verificado, puntos_saldo FROM usuarios WHERE id = %s",
              (g.usuario_id,), one=True)
    if not u["correo_verificado"]:
        return jsonify(error="Confirma tu correo para poder pagar",
                       codigo="CORREO_NO_CONFIRMADO"), 403

    # 2. Clave de pago (evita cobrar dos veces)
    clave = str(datos.get("clave_pago", "")).strip().lower()
    if not CLAVE_VALIDA.match(clave):
        return jsonify(error="Solicitud de pago no válida"), 400

    # 3. Tarjeta: solo marca y últimos 4 dígitos
    tarjeta = datos.get("tarjeta")
    if not isinstance(tarjeta, dict):
        return jsonify(error="Faltan los datos de la tarjeta"), 400
    if set(tarjeta) - {"marca", "ultimos4"} or any(
            NUMERO_TARJETA.search(str(valor)) for valor in tarjeta.values()):
        return jsonify(error="Por seguridad, la app no debe enviar el número completo de la tarjeta"), 400
    marca = str(tarjeta.get("marca", "")).upper()
    ultimos4 = str(tarjeta.get("ultimos4", ""))
    if marca not in MARCAS or not ULTIMOS4_VALIDO.match(ultimos4):
        return jsonify(error="Los datos de la tarjeta no son válidos"), 400

    # 4. ¿Ya se pagó con esta misma clave? Se devuelve la misma venta
    previa = _venta_por_clave(clave)
    if previa:
        if previa["usuario_id"] != g.usuario_id:
            return jsonify(error="Solicitud de pago no válida"), 409
        return _ya_pagada(previa["id"])

    # 5. El total lo calcula la API
    try:
        carrito = calcular_carrito(datos)
    except CarritoInvalido as e:
        return jsonify(error=str(e)), 400
    if not carrito["se_puede_pagar"]:
        return jsonify(error="Revisa tu carrito: hay productos que no se pueden comprar",
                       codigo="CARRITO_CON_ERRORES", carrito=carrito), 409

    # 6. Puntos: cuántos se usan y cuántos se ganan (PASO 11)
    usar_puntos = datos.get("usar_puntos") is True
    if usar_puntos:
        puntos_usados, descuento = puntos_canjeables(u["puntos_saldo"], carrito["total"])
        if puntos_usados == 0:
            return jsonify(error="Tus puntos ya no alcanzan para un descuento. Revisa tu pago.",
                           codigo="PUNTOS_CAMBIARON"), 409
    else:
        puntos_usados, descuento = 0, Decimal("0.00")
    cobrado = carrito["total"] - descuento
    puntos_ganados = puntos_a_ganar(carrito["total"], importe_local(carrito), cobrado)

    try:
        esperado = Decimal(str(datos.get("total_esperado"))).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError):
        return jsonify(error="Falta el total a pagar"), 400
    if esperado != cobrado:
        return jsonify(error="El total de tu carrito cambió. Revísalo antes de pagar.",
                       codigo="TOTAL_CAMBIO", carrito=carrito), 409

    # 7. Guardar todo en una sola transacción
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Se bloquea el saldo del cliente hasta terminar (evita usar los mismos puntos dos veces)
            cur.execute("SELECT puntos_saldo FROM usuarios WHERE id = %s FOR UPDATE",
                        (g.usuario_id,))
            saldo = cur.fetchone()["puntos_saldo"]
            if saldo < puntos_usados:
                raise PuntosInsuficientes()

            cur.execute("""INSERT INTO ventas
                             (clave_pago, usuario_id, sucursal_id, articulos,
                              subtotal, ahorro, puntos_usados, descuento_puntos,
                              total, puntos_ganados, tarjeta_marca, tarjeta_ultimos4)
                           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                        (clave, g.usuario_id, carrito["sucursal_id"], carrito["articulos"],
                         carrito["subtotal"], carrito["ahorro"], puntos_usados, descuento,
                         cobrado, puntos_ganados, marca, ultimos4))
            venta_id = cur.lastrowid
            folio = f"MK-{datetime.now():%y%m%d}-{venta_id:06d}"
            cur.execute("UPDATE ventas SET folio = %s WHERE id = %s", (folio, venta_id))

            # Detalle (se copian nombre y precios del momento)
            por_producto = {}   # producto_id -> (nombre, cantidad total)
            for l in carrito["lineas"]:
                cantidad = l["peso_kg"] if l["tipo_venta"] == "GRANEL" else Decimal(l["cantidad"])
                cur.execute("""INSERT INTO venta_detalle
                                 (venta_id, producto_id, codigo, nombre, tipo_venta, cantidad,
                                  precio, precio_final, importe, importe_normal, es_local)
                               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                            (venta_id, l["producto_id"], l["codigo"], l["nombre"],
                             l["tipo_venta"], cantidad, l["precio"], l["precio_final"],
                             l["importe"], l["importe_normal"], bool(l["es_local"])))
                nombre, suma = por_producto.get(l["producto_id"], (l["nombre"], Decimal(0)))
                por_producto[l["producto_id"]] = (nombre, suma + cantidad)

            # Stock y kárdex: se descuenta SOLO si todavía alcanza
            for producto_id, (nombre, cantidad) in por_producto.items():
                cur.execute("""UPDATE inventario SET stock = stock - %s
                               WHERE producto_id = %s AND sucursal_id = %s AND stock >= %s""",
                            (cantidad, producto_id, carrito["sucursal_id"], cantidad))
                if cur.rowcount != 1:
                    raise SinExistencias(nombre)
                cur.execute("""SELECT stock FROM inventario
                               WHERE producto_id = %s AND sucursal_id = %s""",
                            (producto_id, carrito["sucursal_id"]))
                stock_final = cur.fetchone()["stock"]
                cur.execute("""INSERT INTO movimientos_inventario
                                 (producto_id, sucursal_id, tipo, cantidad, stock_final,
                                  usuario_id, venta_id, nota)
                               VALUES (%s, %s, 'SALIDA_VENTA', %s, %s, %s, %s, %s)""",
                            (producto_id, carrito["sucursal_id"], -cantidad, stock_final,
                             g.usuario_id, venta_id, f"Venta {folio}"))

            # Puntos: primero se restan los usados y luego se suman los ganados
            if puntos_usados:
                saldo -= puntos_usados
                cur.execute("""INSERT INTO movimientos_puntos
                                 (usuario_id, venta_id, tipo, puntos, saldo_final, nota)
                               VALUES (%s, %s, 'CANJEADOS', %s, %s, %s)""",
                            (g.usuario_id, venta_id, -puntos_usados, saldo,
                             f"Descuento de ${descuento} en {folio}"))
            if puntos_ganados:
                saldo += puntos_ganados
                cur.execute("""INSERT INTO movimientos_puntos
                                 (usuario_id, venta_id, tipo, puntos, saldo_final, nota)
                               VALUES (%s, %s, 'GANADOS', %s, %s, %s)""",
                            (g.usuario_id, venta_id, puntos_ganados, saldo, f"Compra {folio}"))
            cur.execute("UPDATE usuarios SET puntos_saldo = %s WHERE id = %s",
                        (saldo, g.usuario_id))
        conn.commit()
    except SinExistencias as e:
        conn.rollback()
        return jsonify(error=f"{e} se agotó mientras pagabas. No se hizo ningún cobro.",
                       codigo="SIN_EXISTENCIAS"), 409
    except PuntosInsuficientes:
        conn.rollback()
        return jsonify(error="Tu saldo de puntos cambió. Revisa tu pago. No se hizo ningún cobro.",
                       codigo="PUNTOS_CAMBIARON"), 409
    except pymysql.err.IntegrityError:
        # Dos pagos con la misma clave al mismo tiempo: gana el primero
        conn.rollback()
        previa = _venta_por_clave(clave)
        if previa and previa["usuario_id"] == g.usuario_id:
            return _ya_pagada(previa["id"])
        raise
    except Exception:
        conn.rollback()
        raise

    registrar_bitacora("COMPRA_PAGADA", g.usuario_id, u["correo"],
                       f"{folio} total ${cobrado} {marca} ****{ultimos4} "
                       f"puntos -{puntos_usados} +{puntos_ganados}")
    return jsonify(mensaje="Pago aprobado", repetida=False, venta=_ticket(venta_id),
                   puntos_saldo=saldo), 201


# ------------------------------------------------------------------
# GET /api/compras/<folio>
# ------------------------------------------------------------------
@bp.get("/compras/<folio>")
@requiere_rol("CLIENTE")
def ver_compra(folio):
    v = query("SELECT id FROM ventas WHERE folio = %s AND usuario_id = %s",
              (folio.strip().upper(), g.usuario_id), one=True)
    if not v:   # no existe o es de otro cliente: misma respuesta
        return jsonify(error="No encontramos esa compra"), 404
    return jsonify(venta=_ticket(v["id"]))