/// Modelos del carrito.
///
/// LineaCarrito: lo que se guarda en el celular (lo que el cliente escaneó).
/// CotizacionCarrito: lo que responde la API con precios y existencias actuales.

double _numero(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? _numeroOpcional(dynamic v) => v == null ? null : _numero(v);

/// Una línea del carrito tal como se guarda en el celular.
class LineaCarrito {
  final String id;            // identificador interno de la línea
  final String codigo;        // lo que se manda a la API: EAN, GR-40001 o etiqueta de báscula
  final String nombre;
  final String tipoVenta;     // UNIDAD o GRANEL
  final int cantidad;         // piezas (en granel siempre 1: una bolsa)
  final double? pesoKg;       // solo granel
  final bool desdeBascula;    // el peso vino de la etiqueta de báscula
  final double precioFinal;   // precio al escanear (referencia; el real lo da la API)
  final double? importe;      // solo granel: importe que calculó la API al escanear

  const LineaCarrito({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tipoVenta,
    required this.cantidad,
    required this.pesoKg,
    required this.desdeBascula,
    required this.precioFinal,
    required this.importe,
  });

  bool get esGranel => tipoVenta == 'GRANEL';

  /// Total aproximado para el botón del escáner (el real lo calcula la API).
  double get totalAproximado => esGranel ? (importe ?? 0) : precioFinal * cantidad;

  LineaCarrito copiarCon({int? cantidad}) => LineaCarrito(
        id: id,
        codigo: codigo,
        nombre: nombre,
        tipoVenta: tipoVenta,
        cantidad: cantidad ?? this.cantidad,
        pesoKg: pesoKg,
        desdeBascula: desdeBascula,
        precioFinal: precioFinal,
        importe: importe,
      );

  /// Lo que se manda a POST /api/carrito/cotizar.
  Map<String, dynamic> paraApi() {
    if (!esGranel) return {'codigo': codigo, 'cantidad': cantidad};
    if (desdeBascula) return {'codigo': codigo};          // el peso viene en el código
    return {'codigo': codigo, 'peso_kg': pesoKg};
  }

  /// Para guardar en el celular.
  Map<String, dynamic> toJson() => {
        'id': id,
        'codigo': codigo,
        'nombre': nombre,
        'tipo_venta': tipoVenta,
        'cantidad': cantidad,
        'peso_kg': pesoKg,
        'desde_bascula': desdeBascula,
        'precio_final': precioFinal,
        'importe': importe,
      };

  factory LineaCarrito.fromJson(Map<String, dynamic> j) => LineaCarrito(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: (j['nombre'] ?? '') as String,
        tipoVenta: (j['tipo_venta'] ?? 'UNIDAD') as String,
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
        pesoKg: _numeroOpcional(j['peso_kg']),
        desdeBascula: j['desde_bascula'] == true,
        precioFinal: _numero(j['precio_final']),
        importe: _numeroOpcional(j['importe']),
      );
}

/// Una línea ya calculada por la API.
class LineaCotizada {
  final int indice;
  final String nombre;
  final double precio;        // precio normal
  final double precioFinal;   // con oferta si existe
  final double? importe;      // null si la línea tiene error
  final double? importeNormal;
  final String? error;

  const LineaCotizada({
    required this.indice,
    required this.nombre,
    required this.precio,
    required this.precioFinal,
    required this.importe,
    required this.importeNormal,
    required this.error,
  });

  bool get tieneError => error != null;
  bool get tieneOferta => precioFinal < precio;

  factory LineaCotizada.fromJson(Map<String, dynamic> j) => LineaCotizada(
        indice: (j['indice'] as num).toInt(),
        nombre: (j['nombre'] ?? '') as String,
        precio: _numero(j['precio']),
        precioFinal: _numero(j['precio_final'] ?? j['precio']),
        importe: _numeroOpcional(j['importe']),
        importeNormal: _numeroOpcional(j['importe_normal']),
        error: j['error'] as String?,
      );
}

/// Respuesta completa de POST /api/carrito/cotizar.
class CotizacionCarrito {
  final List<LineaCotizada> lineas;
  final double subtotal;
  final double ahorro;
  final double total;
  final int articulos;
  final int lineasConError;
  final bool sePuedePagar;

  const CotizacionCarrito({
    required this.lineas,
    required this.subtotal,
    required this.ahorro,
    required this.total,
    required this.articulos,
    required this.lineasConError,
    required this.sePuedePagar,
  });

  /// La línea calculada que corresponde a la posición [i] del carrito.
  LineaCotizada? linea(int i) {
    for (final l in lineas) {
      if (l.indice == i) return l;
    }
    return null;
  }

  factory CotizacionCarrito.fromJson(Map<String, dynamic> j) => CotizacionCarrito(
        lineas: ((j['lineas'] as List?) ?? const [])
            .map((l) => LineaCotizada.fromJson(l as Map<String, dynamic>))
            .toList(),
        subtotal: _numero(j['subtotal']),
        ahorro: _numero(j['ahorro']),
        total: _numero(j['total']),
        articulos: (j['articulos'] as num?)?.toInt() ?? 0,
        lineasConError: (j['lineas_con_error'] as num?)?.toInt() ?? 0,
        sePuedePagar: j['se_puede_pagar'] == true,
      );
}