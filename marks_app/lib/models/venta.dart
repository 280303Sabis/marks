/// Modelo de una compra pagada (lo que responde /api/compras/pagar
/// y /api/compras/FOLIO).
/// 
double _numero(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Un producto dentro del ticket.
class LineaVenta {
  final String nombre;
  final String tipoVenta;    // UNIDAD o GRANEL
  final double cantidad;     // piezas o kg
  final double precio;       // precio normal
  final double precioFinal;  // con oferta si había
  final double importe;      // lo que se cobró
  final double importeNormal;
  final bool esLocal;

  const LineaVenta({
    required this.nombre,
    required this.tipoVenta,
    required this.cantidad,
    required this.precio,
    required this.precioFinal,
    required this.importe,
    required this.importeNormal,
    required this.esLocal,
  });

  bool get esGranel => tipoVenta == 'GRANEL';
  bool get tieneOferta => precioFinal < precio;

  factory LineaVenta.fromJson(Map<String, dynamic> j) => LineaVenta(
        nombre: (j['nombre'] ?? '') as String,
        tipoVenta: (j['tipo_venta'] ?? 'UNIDAD') as String,
        cantidad: _numero(j['cantidad']),
        precio: _numero(j['precio']),
        precioFinal: _numero(j['precio_final'] ?? j['precio']),
        importe: _numero(j['importe']),
        importeNormal: _numero(j['importe_normal'] ?? j['importe']),
        esLocal: j['es_local'] == true || j['es_local'] == 1,
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
  final double ahorro;
  final double total;
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
    required this.total,
    required this.marcaTarjeta,
    required this.ultimos4,
    required this.lineas,
    required this.qr,
  });

  /// Pagada pero el guardia todavía no escanea el QR.
  bool get pendienteDeSalida => estado == 'PAGADA' && qr != null;

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
      total: _numero(j['total']),
      marcaTarjeta: (tarjeta['marca'] ?? '') as String,
      ultimos4: (tarjeta['ultimos4'] ?? '') as String,
      lineas: ((j['lineas'] as List?) ?? const [])
          .map((l) => LineaVenta.fromJson(l as Map<String, dynamic>))
          .toList(),
      qr: j['qr'] as String?,
    );
  }
}