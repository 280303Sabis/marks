/// Producto tal como lo devuelve la API para una sucursal.
class Producto {
  final int id;
  final String codigoBarras;
  final String? plu;           // solo granel (ej. 40001)
  final String nombre;
  final String categoria;
  final String tipoVenta;      // UNIDAD o GRANEL
  final double precio;         // precio normal (por pieza o por kg)
  final double? precioOferta;  // null si no tiene oferta
  final double precioFinal;    // el que paga el cliente (por pieza o por kg)
  final double stock;          // existencias en la sucursal
  final bool esLocal;          // producto de Nuevo León
  final String? productor;
  final DateTime? fechaCaducidad;
  final bool caducado;         // la fecha de caducidad ya pasó
  final bool caducidadProxima; // vence hoy o en los próximos 3 días
  final bool agotado;
  final bool sePuedeVender;    // no está agotado ni caducado (regla de la API)

  // Solo granel con peso (calculado por la API)
  final double? pesoKg;        // kilos con 3 decimales
  final double? importe;       // precioFinal x pesoKg, redondeado por el servidor
  final bool desdeBascula;     // el peso vino de la etiqueta de báscula

  const Producto({
    required this.id,
    required this.codigoBarras,
    required this.plu,
    required this.nombre,
    required this.categoria,
    required this.tipoVenta,
    required this.precio,
    required this.precioOferta,
    required this.precioFinal,
    required this.stock,
    required this.esLocal,
    required this.productor,
    required this.fechaCaducidad,
    required this.caducado,
    required this.caducidadProxima,
    required this.agotado,
    required this.sePuedeVender,
    required this.pesoKg,
    required this.importe,
    required this.desdeBascula,
  });

  bool get esGranel => tipoVenta == 'GRANEL';
  bool get tieneOferta => precioOferta != null && precioOferta! < precio;
  bool get tienePeso => pesoKg != null && importe != null;

  /// Porcentaje de descuento redondeado (ej. 25 para 25 %).
  int get descuento => tieneOferta ? ((1 - precioOferta! / precio) * 100).round() : 0;

  // MySQL manda los booleanos como 0/1
  static bool _bool(dynamic v) => v == true || v == 1;

  static double _numero(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static double? _numeroOpcional(dynamic v) => v == null ? null : _numero(v);

  factory Producto.fromJson(Map<String, dynamic> json) {
    final caducidad = json['fecha_caducidad'];
    final agotado = _bool(json['agotado']);
    final caducado = _bool(json['caducado']);
    return Producto(
      id: (json['producto_id'] as num).toInt(),
      codigoBarras: (json['codigo_barras'] ?? '') as String,
      plu: json['plu'] as String?,
      nombre: (json['nombre'] ?? '') as String,
      categoria: (json['categoria'] ?? '') as String,
      tipoVenta: (json['tipo_venta'] ?? 'UNIDAD') as String,
      precio: _numero(json['precio']),
      precioOferta: _numeroOpcional(json['precio_oferta']),
      precioFinal: _numero(json['precio_final'] ?? json['precio']),
      stock: _numero(json['stock']),
      esLocal: _bool(json['es_local']),
      productor: json['productor'] as String?,
      fechaCaducidad: caducidad == null ? null : DateTime.tryParse(caducidad.toString()),
      caducado: caducado,
      caducidadProxima: _bool(json['caducidad_proxima']),
      agotado: agotado,
      // Si la API no lo manda, se calcula con la misma regla
      sePuedeVender: json['se_puede_vender'] == null
          ? !agotado && !caducado
          : _bool(json['se_puede_vender']),
      pesoKg: _numeroOpcional(json['peso_kg']),
      importe: _numeroOpcional(json['importe']),
      desdeBascula: _bool(json['desde_bascula']),
    );
  }
}