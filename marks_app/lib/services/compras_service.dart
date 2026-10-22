import '../models/puntos.dart';
import '../models/venta.dart';
import 'api_service.dart';

/// Historial de compras y estado de cuenta de puntos del cliente (PASO 12).
/// Todo se pide a la API con la sesión del cliente: cada quien solo ve lo suyo.
class ComprasService {
  ComprasService._();

  /// Mis compras: de la más nueva a la más vieja.
  static Future<ListaCompras> listar() async {
    final respuesta = await ApiService.get('/api/compras', conToken: true);
    return ListaCompras.fromJson(respuesta as Map<String, dynamic>);
  }

  /// El ticket completo de una compra (con su QR si todavía no sale de la tienda).
  static Future<Venta> verCompra(String folio) async {
    final respuesta = await ApiService.get(
      '/api/compras/${Uri.encodeComponent(folio)}',
      conToken: true,
    );
    return Venta.fromJson(
      (respuesta as Map<String, dynamic>)['venta'] as Map<String, dynamic>,
    );
  }

  /// Mis puntos: saldo, reglas y estado de cuenta.
  static Future<EstadoCuentaPuntos> misPuntos() async {
    final respuesta = await ApiService.get('/api/puntos/movimientos', conToken: true);
    return EstadoCuentaPuntos.fromJson(respuesta as Map<String, dynamic>);
  }
}