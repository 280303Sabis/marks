import '../models/opinion.dart';
import 'api_service.dart';

/// Calificaciones y opiniones de productos (PASO 13).
/// Todas las rutas requieren sesión iniciada (se manda el token).
///
/// Las fotos se mandan como rutas de archivos del celular
/// (las que regresa image_picker). La API las revisa, las reduce
/// a máximo 1280 px y les borra los metadatos (GPS, cámara).
class OpinionesService {
  OpinionesService._();

  /// Mismas reglas que la API.
  static const int maxFotos = 3;
  static const int maxComentario = 500;

  /// Resumen (promedio) y opiniones publicadas de un producto.
  static Future<OpinionesProducto> deProducto(int productoId, {int limite = 20}) async {
    final r = await ApiService.get(
      '/api/productos/$productoId/opiniones?limite=$limite',
      conToken: true,
    );
    return OpinionesProducto.fromJson(r as Map<String, dynamic>);
  }

  /// Opinar sobre un producto que el cliente compró.
  /// Si ya había opinado, la API responde 409 con codigo 'YA_OPINASTE'.
  static Future<Opinion> opinar({
    required int productoId,
    required int estrellas,
    String comentario = '',
    List<String> fotos = const [],
  }) async {
    final r = await ApiService.enviarFormulario(
      'POST',
      '/api/productos/$productoId/opiniones',
      campos: {
        'estrellas': '$estrellas',
        'comentario': comentario.trim(),
      },
      archivos: [for (final ruta in fotos) ArchivoSubida('fotos', ruta)],
    );
    return Opinion.fromJson((r as Map<String, dynamic>)['opinion'] as Map<String, dynamic>);
  }

  /// Editar mi opinión.
  /// [conservar]: ids de las fotos que ya tenía y se quedan (las demás se borran).
  /// [fotosNuevas]: rutas de fotos nuevas del celular.
  static Future<Opinion> editar({
    required int opinionId,
    required int estrellas,
    String comentario = '',
    List<int> conservar = const [],
    List<String> fotosNuevas = const [],
  }) async {
    final r = await ApiService.enviarFormulario(
      'PUT',
      '/api/opiniones/$opinionId',
      campos: {
        'estrellas': '$estrellas',
        'comentario': comentario.trim(),
        // Siempre se manda: vacío quiere decir "quitar todas las fotos"
        'conservar': conservar.join(','),
      },
      archivos: [for (final ruta in fotosNuevas) ArchivoSubida('fotos', ruta)],
    );
    return Opinion.fromJson((r as Map<String, dynamic>)['opinion'] as Map<String, dynamic>);
  }

  /// Borrar mi opinión (y sus fotos).
  static Future<void> borrar(int opinionId) async {
    await ApiService.delete('/api/opiniones/$opinionId', conToken: true);
  }

  /// Reportar la opinión de otro cliente. [motivo]: una clave de motivosReporte.
  /// Si ya la había reportado, la API responde 409 con codigo 'YA_REPORTADA'.
  /// Devuelve el mensaje de la API para mostrarlo.
  static Future<String> reportar(int opinionId, String motivo) async {
    final r = await ApiService.post(
      '/api/opiniones/$opinionId/reportar',
      datos: {'motivo': motivo},
      conToken: true,
    );
    return ((r as Map?)?['mensaje'] ?? 'Gracias. Revisaremos esta opinión') as String;
  }

  /// "Mis opiniones": productos pendientes de calificar y las que ya hice.
  static Future<MisOpiniones> mias() async {
    final r = await ApiService.get('/api/opiniones/mias', conToken: true);
    return MisOpiniones.fromJson(r as Map<String, dynamic>);
  }
}