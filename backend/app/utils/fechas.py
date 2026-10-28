"""
FECHAS CON LA HORA DE MONTERREY  (PASO W14)

  La base guarda las fechas con la hora de SU servidor:
    - Aiven (la nube):  hora UTC  -> una compra de las 12:30 se guarda como 18:30
    - MySQL local:      la hora de la computadora (Monterrey)

  Antes la API mandaba esas fechas tal cual, así que con Aiven la app y la
  página mostraban las compras 6 horas adelantadas. Ahora, al convertir la
  respuesta a JSON, cada fecha con hora se pasa a la hora de Monterrey
  (UTC-6, sin horario de verano), sin importar dónde esté la base.

  Las fechas sin hora (como la fecha de nacimiento) no se tocan.
"""
from datetime import datetime, timedelta, timezone

from flask import has_app_context

from ..db import query

HORA_MX = timezone(timedelta(hours=-6))
_desfase = None   # diferencia entre la hora de la base y UTC (se calcula una sola vez)


def desfase_bd():
    """Horas que la base está adelantada o atrasada respecto a UTC."""
    global _desfase
    if _desfase is None:
        ahora_bd = query("SELECT NOW() AS ahora", one=True)["ahora"]
        ahora_utc = datetime.now(timezone.utc).replace(tzinfo=None)
        _desfase = timedelta(hours=round((ahora_bd - ahora_utc).total_seconds() / 3600))
    return _desfase


def a_hora_mx(fecha_bd):
    """Fecha guardada en la base -> la misma fecha con la hora de Monterrey."""
    if fecha_bd is None or fecha_bd.tzinfo is not None or not has_app_context():
        return fecha_bd
    try:
        utc = (fecha_bd - desfase_bd()).replace(tzinfo=timezone.utc)
    except Exception:
        return fecha_bd   # sin base disponible: se manda como estaba
    return utc.astimezone(HORA_MX).replace(tzinfo=None)