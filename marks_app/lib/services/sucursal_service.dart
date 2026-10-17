import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/sucursal.dart';
import 'api_service.dart';

/// Sucursales: lista desde la API y la sucursal elegida guardada en el celular.
class SucursalService {
  SucursalService._();

  static const FlutterSecureStorage _almacen = FlutterSecureStorage();
  static const String _clave = 'marks_sucursal';

  /// Sucursales activas (no requiere sesión).
  static Future<List<Sucursal>> obtenerSucursales() async {
    final respuesta = await ApiService.get('/api/sucursales');
    if (respuesta is! List) return const [];
    return respuesta
        .map((s) => Sucursal.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Guarda la sucursal elegida para recordarla al volver a abrir la app.
  static Future<void> guardarSeleccion(Sucursal sucursal) =>
      _almacen.write(key: _clave, value: jsonEncode(sucursal.toJson()));

  /// Sucursal elegida anteriormente, o null si no hay ninguna.
  static Future<Sucursal?> leerSeleccion() async {
    final texto = await _almacen.read(key: _clave);
    if (texto == null) return null;
    try {
      return Sucursal.fromJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      await _almacen.delete(key: _clave); // dato dañado: se descarta
      return null;
    }
  }

  /// Olvida la sucursal elegida.
  static Future<void> borrarSeleccion() => _almacen.delete(key: _clave);
}