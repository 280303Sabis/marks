import '../models/producto.dart';
import 'api_service.dart';

/// Consulta de productos para el escáner.
/// Todas las rutas requieren sesión iniciada (se manda el token).
class ProductoService {
  ProductoService._();

  /// Busca el producto escaneado en la sucursal del cliente.
  /// Si no existe en esa sucursal, lanza ApiException (404) con el mensaje de la API.
  ///
  /// Granel con peso escrito: se manda [peso] tal como lo escribió el cliente
  /// y la [unidad] ('kg' o 'g'). La API valida el peso y calcula el importe.
  static Future<Producto> escanear(
    String codigo,
    int sucursalId, {
    String? peso,
    String unidad = 'kg',
  }) async {
    final limpio = codigo.trim();
    var ruta = '/api/productos/escanear/${Uri.encodeComponent(limpio)}?sucursal_id=$sucursalId';
    if (peso != null) {
      ruta += '&peso=${Uri.encodeQueryComponent(peso.trim())}&unidad=$unidad';
    }
    final respuesta = await ApiService.get(ruta, conToken: true);
    return Producto.fromJson(respuesta as Map<String, dynamic>);
  }

  /// Catálogo completo de la sucursal.
  static Future<List<Producto>> catalogo(int sucursalId) async {
    final respuesta = await ApiService.get(
      '/api/productos?sucursal_id=$sucursalId',
      conToken: true,
    );
    if (respuesta is! List) return const [];
    return respuesta
        .map((p) => Producto.fromJson(p as Map<String, dynamic>))
        .toList();
  }
}