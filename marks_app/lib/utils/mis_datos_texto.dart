// Convierte la copia de mis datos (GET /api/cuenta/exportar) en un texto
// fácil de leer, para el archivo mis_datos_marks.txt (PASO 14).
// El .json se comparte junto con este, para quien lo quiera en formato de datos.

const List<String> _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

const Map<String, String> _sexos = {
  'F': 'Femenino',
  'M': 'Masculino',
  'N': 'Prefiero no decirlo',
};

const Map<String, String> _eventos = {
  'REGISTRO': 'Registro',
  'LOGIN_OK': 'Inicio de sesión',
  'LOGIN_FALLIDO': 'Intento fallido de inicio de sesión',
  'CUENTA_BLOQUEADA': 'Cuenta bloqueada',
  'CAMBIO_PASSWORD': 'Cambio de contraseña',
  'RECUPERACION_SOLICITADA': 'Recuperación de contraseña solicitada',
  'RECUPERACION_OK': 'Contraseña recuperada',
  'CORREO_CONFIRMADO': 'Correo confirmado',
  'DATOS_EXPORTADOS': 'Descarga de mis datos',
  'CUENTA_ELIMINADA': 'Cuenta eliminada',
  'PERFIL_ACTUALIZADO': 'Datos actualizados',
  'COMPRA_PAGADA': 'Compra pagada',
  'AVISO_ACEPTADO': 'Aviso de Privacidad aceptado',
};

const Map<String, String> _movimientos = {
  'GANADOS': 'Puntos ganados',
  'CANJEADOS': 'Puntos usados',
  'AJUSTE': 'Ajuste',
};

/// "22 oct 2026 18:45" (o "22 oct 2026" si no trae hora).
String _fecha(dynamic v) {
  final texto = (v ?? '').toString();
  final f = DateTime.tryParse(texto);
  if (f == null) return texto.isEmpty ? '-' : texto;
  final dia = '${f.day} ${_meses[f.month - 1]} ${f.year}';
  if (!texto.contains('T') && !texto.contains(' ')) return dia;
  final hora = '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
  return '$dia $hora';
}

/// Dinero: 116 -> "$116.00" (la API puede mandar número o texto).
String _dinero(dynamic v) {
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return '\$${n.toStringAsFixed(2)}';
}

String _texto(dynamic v) {
  final t = (v ?? '').toString().trim();
  return t.isEmpty ? '-' : t;
}

List<Map<String, dynamic>> _lista(dynamic v) =>
    ((v as List?) ?? const []).map((e) => e as Map<String, dynamic>).toList();

String misDatosComoTexto(Map<String, dynamic> d) {
  final b = StringBuffer();
  void titulo(String t) {
    b
      ..writeln()
      ..writeln(t.toUpperCase())
      ..writeln('-' * t.length);
  }

  final p = (d['perfil'] as Map<String, dynamic>?) ?? const {};
  b
    ..writeln("MARK'S - Copia de mis datos personales")
    ..writeln('Generada: ${_fecha(d['generado_en'])}')
    ..writeln(_texto(d['aviso']));

  titulo('Mi perfil');
  b
    ..writeln('Nombre: ${_texto(p['nombre'])}')
    ..writeln('Apellidos: ${_texto(p['apellidos'])}')
    ..writeln('Correo: ${_texto(p['correo'])}')
    ..writeln('Teléfono: ${_texto(p['telefono'])}')
    ..writeln('Fecha de nacimiento: ${_fecha(p['fecha_nacimiento'])}')
    ..writeln('Sexo: ${_sexos[p['sexo']] ?? '-'}')
    ..writeln('Puntos: ${p['puntos_saldo'] ?? 0}')
    ..writeln('Correo confirmado: ${(p['correo_verificado'] == true || p['correo_verificado'] == 1) ? 'Sí' : 'No'}')
    ..writeln('Cuenta creada: ${_fecha(p['creado_en'])}')
    ..writeln('Último acceso: ${_fecha(p['ultimo_acceso'])}');

  final aviso = (d['aviso_privacidad_aceptado'] as Map<String, dynamic>?) ?? const {};
  titulo('Aviso de Privacidad aceptado');
  b.writeln('Versión ${_texto(aviso['version'])}, aceptada el ${_fecha(aviso['fecha_aceptacion'])}');

  final compras = _lista(d['compras']);
  titulo('Mis compras (${compras.length})');
  if (compras.isEmpty) b.writeln('Sin compras.');
  for (final c in compras) {
    b
      ..writeln('* ${_texto(c['folio'])} - ${_fecha(c['pagada_en'])} - ${_texto(c['sucursal'])}')
      ..writeln('  Estado: ${_texto(c['estado'])} - ${c['articulos'] ?? 0} artículos')
      ..writeln('  Subtotal ${_dinero(c['subtotal'])} - Ahorro ${_dinero(c['ahorro'])}'
          ' - Puntos usados ${c['puntos_usados'] ?? 0} (${_dinero(c['descuento_puntos'])})')
      ..writeln('  Total ${_dinero(c['total'])} - Puntos ganados ${c['puntos_ganados'] ?? 0}'
          ' - Tarjeta ${_texto(c['tarjeta_marca'])} terminación ${_texto(c['tarjeta_ultimos4'])}');
  }

  final puntos = _lista(d['movimientos_de_puntos']);
  titulo('Movimientos de puntos (${puntos.length})');
  if (puntos.isEmpty) b.writeln('Sin movimientos.');
  for (final m in puntos) {
    final n = (m['puntos'] as num?)?.toInt() ?? 0;
    b.writeln('* ${_fecha(m['fecha'])} - ${_movimientos[m['tipo']] ?? _texto(m['tipo'])}'
        ' ${n > 0 ? '+' : ''}$n - Saldo ${m['saldo_final'] ?? 0}'
        '${(m['nota'] ?? '').toString().isEmpty ? '' : ' - ${m['nota']}'}');
  }

  final opiniones = _lista(d['opiniones']);
  titulo('Mis opiniones (${opiniones.length})');
  if (opiniones.isEmpty) b.writeln('Sin opiniones.');
  for (final o in opiniones) {
    b.writeln('* ${_texto(o['producto'])} - ${o['estrellas']} estrellas - ${_fecha(o['creada_en'])}'
        '${o['editada_en'] == null ? '' : ' (editada)'} - ${_texto(o['estado'])}'
        ' - ${o['fotos'] ?? 0} foto(s)');
    if ((o['comentario'] ?? '').toString().trim().isNotEmpty) {
      b.writeln('  "${o['comentario']}"');
    }
  }

  final accesos = _lista(d['historial_de_accesos']);
  titulo('Historial de accesos (últimos ${accesos.length})');
  for (final a in accesos) {
    b.writeln('* ${_fecha(a['fecha'])} - ${_eventos[a['evento']] ?? _texto(a['evento'])}'
        ' - IP ${_texto(a['ip'])}');
  }

  b
    ..writeln()
    ..writeln('Si algún dato es incorrecto, corrígelo en Mi perfil > Editar mis datos.');
  return b.toString();
}