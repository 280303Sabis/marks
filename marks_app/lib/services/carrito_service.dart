import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/carrito.dart';
import '../models/producto.dart';
import 'api_service.dart';

/// Resultado de intentar agregar un producto al carrito.
enum ResultadoAgregar {
  agregado,          // línea nueva
  sumado,            // se sumó 1 pieza a una línea que ya existía
  limitePiezas,      // ya tiene 20 piezas de ese producto
  etiquetaRepetida,  // esa etiqueta de báscula ya está en el carrito
  carritoLleno,      // ya tiene 60 productos distintos
  otraSucursal,      // el carrito es de otra sucursal
}

/// El carrito del cliente.
///
/// - Vive en el celular y se guarda cifrado (si se cierra la app, no se pierde).
/// - Avisa a las pantallas cuando cambia (ChangeNotifier), así el botón
///   "Ver carrito" del escáner se actualiza solo.
/// - El total real lo calcula la API con cotizar().
class CarritoService extends ChangeNotifier {
  CarritoService._();

  /// Una sola instancia para toda la app.
  static final CarritoService instancia = CarritoService._();

  static const int maxPiezas = 20;
  static const int maxLineas = 60;
  static const FlutterSecureStorage _almacen = FlutterSecureStorage();
  static const String _clave = 'marks_carrito';

  final List<LineaCarrito> _lineas = [];
  int? _sucursalId;

  List<LineaCarrito> get lineas => List.unmodifiable(_lineas);
  int? get sucursalId => _sucursalId;
  bool get vacio => _lineas.isEmpty;

  /// Piezas + bolsas de granel (cada bolsa cuenta 1).
  int get articulos => _lineas.fold<int>(0, (suma, l) => suma + (l.esGranel ? 1 : l.cantidad));

  /// Total aproximado para el botón del escáner.
  double get totalAproximado => _lineas.fold<double>(0.0, (suma, l) => suma + l.totalAproximado);

  /// Lee el carrito guardado en el celular (solo la primera vez).
  /// Si varias pantallas lo piden al mismo tiempo, todas esperan la MISMA lectura.
  Future<void> cargar() => _carga ??= _leer();
  Future<void>? _carga;

  Future<void> _leer() async {
    String? texto;
    try {
      texto = await _almacen.read(key: _clave);
    } catch (e) {
      // No se pudo leer el almacenamiento: no se borra nada, solo se avisa
      debugPrint('[Carrito] No se pudo leer: $e');
      return;
    }
    if (texto == null) {
      debugPrint('[Carrito] No hay carrito guardado');
      notifyListeners();
      return;
    }
    try {
      final datos = jsonDecode(texto) as Map<String, dynamic>;
      _sucursalId = (datos['sucursal_id'] as num?)?.toInt();
      _lineas
        ..clear()
        ..addAll((datos['lineas'] as List)
            .map((l) => LineaCarrito.fromJson(l as Map<String, dynamic>)));
      debugPrint('[Carrito] Cargado: ${_lineas.length} líneas, sucursal $_sucursalId');
    } catch (e) {
      // Lo guardado está dañado: se empieza con el carrito vacío
      debugPrint('[Carrito] Guardado dañado, se descarta: $e');
      _lineas.clear();
      _sucursalId = null;
      await _almacen.delete(key: _clave);
    }
    notifyListeners();
  }

  /// Guarda el carrito en el celular y después avisa a las pantallas.
  Future<void> _guardar() async {
    try {
      if (_lineas.isEmpty) {
        await _almacen.delete(key: _clave);
      } else {
        await _almacen.write(
          key: _clave,
          value: jsonEncode({
            'sucursal_id': _sucursalId,
            'lineas': _lineas.map((l) => l.toJson()).toList(),
          }),
        );
      }
      debugPrint('[Carrito] Guardado: ${_lineas.length} líneas');
    } catch (e) {
      debugPrint('[Carrito] No se pudo guardar: $e');
    }
    notifyListeners();
  }

  /// Agrega el producto que el cliente eligió en la hoja.
  /// [codigoLeido] es el código que leyó la cámara (o que escribió el cliente).
  Future<ResultadoAgregar> agregar(
    Producto p, {
    required String codigoLeido,
    required int sucursalId,
  }) async {
    await cargar();
    if (_lineas.isNotEmpty && _sucursalId != sucursalId) {
      return ResultadoAgregar.otraSucursal;
    }

    if (!p.esGranel) {
      // Por pieza: si ya está en el carrito, se suma 1
      final i = _lineas.indexWhere((l) => !l.esGranel && l.codigo == p.codigoBarras);
      if (i >= 0) {
        if (_lineas[i].cantidad >= maxPiezas) return ResultadoAgregar.limitePiezas;
        _lineas[i] = _lineas[i].copiarCon(cantidad: _lineas[i].cantidad + 1);
        await _guardar();
        return ResultadoAgregar.sumado;
      }
    } else if (p.desdeBascula && _lineas.any((l) => l.codigo == codigoLeido)) {
      // Granel: cada bolsa es una línea, pero la misma etiqueta no se agrega dos veces
      return ResultadoAgregar.etiquetaRepetida;
    }

    if (_lineas.length >= maxLineas) return ResultadoAgregar.carritoLleno;

    _sucursalId = sucursalId;
    _lineas.add(LineaCarrito(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      codigo: (p.esGranel && p.desdeBascula) ? codigoLeido : p.codigoBarras,
      nombre: p.nombre,
      tipoVenta: p.tipoVenta,
      cantidad: 1,
      pesoKg: p.pesoKg,
      desdeBascula: p.desdeBascula,
      precioFinal: p.precioFinal,
      importe: p.importe,
    ));
    await _guardar();
    return ResultadoAgregar.agregado;
  }

  /// Cambia las piezas de una línea (de 1 a 20).
  Future<void> cambiarCantidad(String id, int cantidad) async {
    final i = _lineas.indexWhere((l) => l.id == id);
    if (i < 0 || _lineas[i].esGranel) return;
    _lineas[i] = _lineas[i].copiarCon(cantidad: cantidad.clamp(1, maxPiezas).toInt());
    await _guardar();
  }

  Future<void> quitar(String id) async {
    _lineas.removeWhere((l) => l.id == id);
    if (_lineas.isEmpty) _sucursalId = null;
    await _guardar();
  }

  Future<void> vaciar() async {
    _lineas.clear();
    _sucursalId = null;
    await _guardar();
  }

  /// Pide a la API el carrito calculado con precios y existencias actuales.
  Future<CotizacionCarrito> cotizar() async {
    await cargar();
    final respuesta = await ApiService.post(
      '/api/carrito/cotizar',
      datos: {
        'sucursal_id': _sucursalId,
        'lineas': _lineas.map((l) => l.paraApi()).toList(),
      },
      conToken: true,
    );
    return CotizacionCarrito.fromJson(respuesta as Map<String, dynamic>);
  }
}