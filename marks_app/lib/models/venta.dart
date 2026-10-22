// Modelo de una compra pagada (lo que responde /api/compras/pagar
// y /api/compras/FOLIO).

double _numero(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Un producto dentro del ticket.
class LineaVenta {
  final int? productoId;     // PASO 13: para opinar sobre el producto
  final String nombre;
  final String tipoVenta;    // UNIDAD o GRANEL
  final double cantidad;     // piezas o kg
  final double precio;       // precio normal
  final double precioFinal;  // con oferta si había
  final double importe;      // lo que se cobró
  final double importeNormal;
  final bool esLocal;
  final int? opinionId;          // PASO 13: null si todavía no opina
  final bool opinionesActivas;   // PASO 13: el admin puede apagarlas

  const LineaVenta({
    required this.productoId,
    required this.nombre,
    required this.tipoVenta,
    required this.cantidad,
    required this.precio,
    required this.precioFinal,
    required this.importe,
    required this.importeNormal,
    required this.esLocal,
    required this.opinionId,
    required this.opinionesActivas,
  });

  bool get esGranel => tipoVenta == 'GRANEL';
  bool get tieneOferta => precioFinal < precio;

  /// Ya calificó este producto (el botón dice "Editar opinión").
  bool get yaOpino => opinionId != null;

  /// Se puede mostrar el botón "Opinar" o "Editar opinión".
  bool get admiteOpinion => productoId != null && opinionesActivas;

  factory LineaVenta.fromJson(Map<String, dynamic> j) => LineaVenta(
        productoId: (j['producto_id'] as num?)?.toInt(),
        nombre: (j['nombre'] ?? '') as String,
        tipoVenta: (j['tipo_venta'] ?? 'UNIDAD') as String,
        cantidad: _numero(j['cantidad']),
        precio: _numero(j['precio']),
        precioFinal: _numero(j['precio_final'] ?? j['precio']),
        importe: _numero(j['importe']),
        importeNormal: _numero(j['importe_normal'] ?? j['importe']),
        esLocal: j['es_local'] == true || j['es_local'] == 1,
        opinionId: (j['opinion_id'] as num?)?.toInt(),
        opinionesActivas: j['opiniones_activas'] != false && j['opiniones_activas'] != 0,
      );
}

/// Una compra pagada.
class Venta {
  final String folio;        // MK-261022-000001
  final String estado;       // PAGADA, VALIDADA o CANCELADA
  final String sucursal;
  final DateTime? pagadaEn;
  final int articulos;
  final double subtotal;
  final double ahorro;          // por ofertas
  final int puntosUsados;       // PASO 11
  final double descuentoPuntos; // PASO 11: $ que descontaron los puntos
  final double total;           // lo que se cobró a la tarjeta
  final int puntosGanados;      // PASO 11
  final String marcaTarjeta; // VISA, MASTERCARD o AMEX
  final String ultimos4;
  final List<LineaVenta> lineas;
  final String? qr;          // texto firmado del QR (null si ya salió de la tienda)

  const Venta({
    required this.folio,
    required this.estado,
    required this.sucursal,
    required this.pagadaEn,
    required this.articulos,
    required this.subtotal,
    required this.ahorro,
    required this.puntosUsados,
    required this.descuentoPuntos,
    required this.total,
    required this.puntosGanados,
    required this.marcaTarjeta,
    required this.ultimos4,
    required this.lineas,
    required this.qr,
  });

  /// Pagada pero el guardia todavía no escanea el QR.
  bool get pendienteDeSalida => estado == 'PAGADA' && qr != null;

  /// Solo se opina sobre compras pagadas o validadas (no canceladas).
  bool get permiteOpinar => estado == 'PAGADA' || estado == 'VALIDADA';

  factory Venta.fromJson(Map<String, dynamic> j) {
    final tarjeta = (j['tarjeta'] as Map?) ?? const {};
    return Venta(
      folio: (j['folio'] ?? '') as String,
      estado: (j['estado'] ?? '') as String,
      sucursal: (j['sucursal'] ?? '') as String,
      pagadaEn: DateTime.tryParse((j['pagada_en'] ?? '').toString()),
      articulos: (j['articulos'] as num?)?.toInt() ?? 0,
      subtotal: _numero(j['subtotal']),
      ahorro: _numero(j['ahorro']),
      puntosUsados: (j['puntos_usados'] as num?)?.toInt() ?? 0,
      descuentoPuntos: _numero(j['descuento_puntos']),
      total: _numero(j['total']),
      puntosGanados: (j['puntos_ganados'] as num?)?.toInt() ?? 0,
      marcaTarjeta: (tarjeta['marca'] ?? '') as String,
      ultimos4: (tarjeta['ultimos4'] ?? '') as String,
      lineas: ((j['lineas'] as List?) ?? const [])
          .map((l) => LineaVenta.fromJson(l as Map<String, dynamic>))
          .toList(),
      qr: j['qr'] as String?,
    );
  }
}

/// Una compra en la lista de "Mis compras" (resumen, sin productos).
class ResumenCompra {
  final String folio;
  final String estado;       // PAGADA, VALIDADA o CANCELADA
  final String sucursal;
  final DateTime? pagadaEn;
  final int articulos;
  final double total;
  final int puntosUsados;
  final int puntosGanados;

  const ResumenCompra({
    required this.folio,
    required this.estado,
    required this.sucursal,
    required this.pagadaEn,
    required this.articulos,
    required this.total,
    required this.puntosUsados,
    required this.puntosGanados,
  });

  /// Pagada pero el guardia todavía no escanea el QR.
  bool get porSalir => estado == 'PAGADA';

  factory ResumenCompra.fromJson(Map<String, dynamic> j) => ResumenCompra(
        folio: (j['folio'] ?? '') as String,
        estado: (j['estado'] ?? '') as String,
        sucursal: (j['sucursal'] ?? '') as String,
        pagadaEn: DateTime.tryParse((j['pagada_en'] ?? '').toString()),
        articulos: (j['articulos'] as num?)?.toInt() ?? 0,
        total: _numero(j['total']),
        puntosUsados: (j['puntos_usados'] as num?)?.toInt() ?? 0,
        puntosGanados: (j['puntos_ganados'] as num?)?.toInt() ?? 0,
      );
}

/// Respuesta de GET /api/compras.
class ListaCompras {
  final List<ResumenCompra> compras;
  final List<String> porSalir; // folios pagados que el guardia aún no valida

  const ListaCompras({required this.compras, required this.porSalir});

  factory ListaCompras.fromJson(Map<String, dynamic> j) => ListaCompras(
        compras: ((j['compras'] as List?) ?? const [])
            .map((c) => ResumenCompra.fromJson(c as Map<String, dynamic>))
            .toList(),
        porSalir: ((j['por_salir'] as List?) ?? const []).map((f) => f.toString()).toList(),
      );
}