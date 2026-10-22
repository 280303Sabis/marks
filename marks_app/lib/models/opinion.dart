// Modelos de calificaciones y opiniones (PASO 13).
// Lo que responden /api/productos/ID/opiniones y /api/opiniones/mias.

import '../config/api_config.dart';

int _entero(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString()) ?? 0;
}

double _decimal(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse((v ?? '').toString()) ?? 0;
}

DateTime? _fecha(dynamic v) => DateTime.tryParse((v ?? '').toString());

/// Motivos para reportar una opinión: clave que entiende la API -> texto para el cliente.
const Map<String, String> motivosReporte = {
  'OFENSIVA': 'Es ofensiva o grosera',
  'SPAM': 'Es spam o publicidad',
  'FALSA': 'Es falsa o engañosa',
  'OTRO': 'Otro motivo',
};

/// Una foto de una opinión.
class FotoOpinion {
  final int id;
  final String url;   // ruta de la API: /api/opiniones/fotos/xxxx.jpg
  final int ancho;
  final int alto;

  const FotoOpinion({
    required this.id,
    required this.url,
    required this.ancho,
    required this.alto,
  });

  /// Dirección completa para Image.network (la foto es pública, no lleva token).
  String get urlCompleta => url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url';

  /// Ancho / alto, para reservar el espacio antes de que cargue.
  double get proporcion => (ancho > 0 && alto > 0) ? ancho / alto : 1;

  factory FotoOpinion.fromJson(Map<String, dynamic> j) => FotoOpinion(
        id: _entero(j['id']),
        url: (j['url'] ?? '') as String,
        ancho: _entero(j['ancho']),
        alto: _entero(j['alto']),
      );
}

/// Una opinión de un cliente sobre un producto.
class Opinion {
  final int id;
  final int productoId;
  final String autor;          // "Sabina O."
  final int estrellas;         // 1 a 5
  final String? comentario;
  final String estado;         // PUBLICADA u OCULTA
  final DateTime? creadaEn;
  final bool editada;
  final bool esMia;
  final List<FotoOpinion> fotos;
  final String? producto;      // nombre del producto (solo en "Mis opiniones")

  const Opinion({
    required this.id,
    required this.productoId,
    required this.autor,
    required this.estrellas,
    required this.comentario,
    required this.estado,
    required this.creadaEn,
    required this.editada,
    required this.esMia,
    required this.fotos,
    this.producto,
  });

  /// El admin la ocultó: solo la ve su autor.
  bool get oculta => estado == 'OCULTA';

  bool get tieneComentario => (comentario ?? '').trim().isNotEmpty;

  factory Opinion.fromJson(Map<String, dynamic> j) => Opinion(
        id: _entero(j['id']),
        productoId: _entero(j['producto_id']),
        autor: (j['autor'] ?? 'Cliente') as String,
        estrellas: _entero(j['estrellas']),
        comentario: j['comentario'] as String?,
        estado: (j['estado'] ?? 'PUBLICADA') as String,
        creadaEn: _fecha(j['creada_en']),
        editada: j['editada'] == true,
        esMia: j['es_mia'] == true,
        fotos: ((j['fotos'] as List?) ?? const [])
            .map((f) => FotoOpinion.fromJson(f as Map<String, dynamic>))
            .toList(),
        producto: j['producto'] as String?,
      );
}

/// Promedio y cuántas opiniones hay de cada estrella.
class ResumenOpiniones {
  final int total;
  final double promedio;            // 0 si no hay opiniones
  final Map<int, int> porEstrellas; // {5: 10, 4: 3, 3: 0, 2: 1, 1: 0}

  const ResumenOpiniones({
    required this.total,
    required this.promedio,
    required this.porEstrellas,
  });

  bool get vacio => total == 0;

  int cuantas(int estrellas) => porEstrellas[estrellas] ?? 0;

  /// De 0.0 a 1.0, para la barrita de cada estrella.
  double proporcion(int estrellas) => total == 0 ? 0 : cuantas(estrellas) / total;

  factory ResumenOpiniones.fromJson(Map<String, dynamic> j) {
    final mapa = (j['por_estrellas'] as Map?) ?? const {};
    return ResumenOpiniones(
      total: _entero(j['total']),
      promedio: _decimal(j['promedio']),
      porEstrellas: {for (var e = 5; e >= 1; e--) e: _entero(mapa['$e'])},
    );
  }
}

/// Respuesta de GET /api/productos/ID/opiniones.
class OpinionesProducto {
  final int productoId;
  final String producto;
  final bool activas;            // false: el admin apagó las opiniones
  final ResumenOpiniones resumen;
  final List<Opinion> opiniones; // publicadas, de la más nueva a la más vieja
  final Opinion? miOpinion;      // la del cliente (aunque esté oculta)
  final bool puedeOpinar;        // compró el producto y todavía no opina

  const OpinionesProducto({
    required this.productoId,
    required this.producto,
    required this.activas,
    required this.resumen,
    required this.opiniones,
    required this.miOpinion,
    required this.puedeOpinar,
  });

  factory OpinionesProducto.fromJson(Map<String, dynamic> j) => OpinionesProducto(
        productoId: _entero(j['producto_id']),
        producto: (j['producto'] ?? '') as String,
        activas: j['activas'] != false,
        resumen: ResumenOpiniones.fromJson((j['resumen'] as Map<String, dynamic>?) ?? const {}),
        opiniones: ((j['opiniones'] as List?) ?? const [])
            .map((o) => Opinion.fromJson(o as Map<String, dynamic>))
            .toList(),
        miOpinion: j['mi_opinion'] == null
            ? null
            : Opinion.fromJson(j['mi_opinion'] as Map<String, dynamic>),
        puedeOpinar: j['puede_opinar'] == true,
      );
}

/// Un producto que el cliente compró y todavía no califica.
class PendienteOpinion {
  final int productoId;
  final String nombre;
  final DateTime? compradoEn;

  const PendienteOpinion({
    required this.productoId,
    required this.nombre,
    required this.compradoEn,
  });

  factory PendienteOpinion.fromJson(Map<String, dynamic> j) => PendienteOpinion(
        productoId: _entero(j['producto_id']),
        nombre: (j['nombre'] ?? '') as String,
        compradoEn: _fecha(j['comprado_en']),
      );
}

/// Respuesta de GET /api/opiniones/mias (pestañas Pendientes y Publicadas).
class MisOpiniones {
  final List<PendienteOpinion> pendientes;
  final List<Opinion> publicadas;

  const MisOpiniones({required this.pendientes, required this.publicadas});

  factory MisOpiniones.fromJson(Map<String, dynamic> j) => MisOpiniones(
        pendientes: ((j['pendientes'] as List?) ?? const [])
            .map((p) => PendienteOpinion.fromJson(p as Map<String, dynamic>))
            .toList(),
        publicadas: ((j['publicadas'] as List?) ?? const [])
            .map((o) => Opinion.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}