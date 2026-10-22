import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Error que devuelve la API o que ocurre al intentar conectarse.
class ApiException implements Exception {
  /// Código HTTP de la respuesta (null si no hubo conexión).
  final int? estado;

  /// Mensaje listo para mostrarse al usuario.
  final String mensaje;

  /// Detalles adicionales (por ejemplo, reglas de contraseña que no se cumplen).
  final List<String> detalles;

  /// Código corto que manda la API en algunos errores (ej. YA_OPINASTE).
  final String? codigo;

  ApiException(this.mensaje, {this.estado, this.detalles = const [], this.codigo});

  /// La sesión ya no es válida y el usuario debe iniciar sesión de nuevo.
  bool get sesionExpirada => estado == 401;

  /// No se pudo llegar a la API (sin internet, IP incorrecta o API apagada).
  bool get sinConexion => estado == null;

  @override
  String toString() => mensaje;
}

/// Guarda el token de sesión cifrado dentro del celular.
/// En Android se usa el almacén seguro del sistema (Keystore)
/// y en iPhone el Llavero (Keychain).
class SesionStorage {
  SesionStorage._();

  static const FlutterSecureStorage _almacen = FlutterSecureStorage();
  static const String _claveToken = 'marks_token';

  static Future<void> guardarToken(String token) =>
      _almacen.write(key: _claveToken, value: token);

  static Future<String?> leerToken() => _almacen.read(key: _claveToken);

  static Future<void> borrarToken() => _almacen.delete(key: _claveToken);
}

/// Un archivo que se manda dentro de un formulario (por ejemplo, una foto).
class ArchivoSubida {
  /// Nombre del campo en el formulario (ej. 'fotos').
  final String campo;

  /// Ruta del archivo dentro del celular (la que regresa image_picker).
  final String ruta;

  const ArchivoSubida(this.campo, this.ruta);
}

/// Punto único de comunicación entre la app y la API de MARK'S.
class ApiService {
  ApiService._();

  static Future<dynamic> get(String ruta, {bool conToken = false}) =>
      _enviar('GET', ruta, conToken: conToken);

  static Future<dynamic> post(
    String ruta, {
    Map<String, dynamic>? datos,
    bool conToken = false,
  }) =>
      _enviar('POST', ruta, datos: datos, conToken: conToken);

  static Future<dynamic> put(
    String ruta, {
    Map<String, dynamic>? datos,
    bool conToken = false,
  }) =>
      _enviar('PUT', ruta, datos: datos, conToken: conToken);

  static Future<dynamic> delete(
    String ruta, {
    Map<String, dynamic>? datos,
    bool conToken = false,
  }) =>
      _enviar('DELETE', ruta, datos: datos, conToken: conToken);

  /// Manda un formulario con archivos (multipart/form-data), por ejemplo
  /// una opinión con fotos. [metodo] es 'POST' o 'PUT'.
  /// Tiene más tiempo de espera que una petición normal porque sube fotos.
  static Future<dynamic> enviarFormulario(
    String metodo,
    String ruta, {
    Map<String, String> campos = const {},
    List<ArchivoSubida> archivos = const [],
    bool conToken = true,
  }) async {
    final peticion = http.MultipartRequest(metodo, Uri.parse('${ApiConfig.baseUrl}$ruta'));
    // El Content-Type (con su "boundary") lo pone el paquete http solo
    peticion.fields.addAll(campos);
    try {
      for (final archivo in archivos) {
        peticion.files.add(await http.MultipartFile.fromPath(archivo.campo, archivo.ruta));
      }
    } on FileSystemException {
      throw ApiException('No se pudo leer una de las fotos. Vuelve a elegirla.');
    }
    return _procesar(peticion, conToken: conToken, espera: ApiConfig.tiempoEspera * 4);
  }

  /// Petición normal con JSON.
  static Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    Map<String, dynamic>? datos,
    bool conToken = false,
  }) async {
    final peticion = http.Request(metodo, Uri.parse('${ApiConfig.baseUrl}$ruta'));
    peticion.headers['Content-Type'] = 'application/json; charset=utf-8';
    if (datos != null) {
      peticion.body = jsonEncode(datos);
    }
    return _procesar(peticion, conToken: conToken, espera: ApiConfig.tiempoEspera);
  }

  /// Parte común: pone el token, envía, lee la respuesta y convierte los errores.
  static Future<dynamic> _procesar(
    http.BaseRequest peticion, {
    required bool conToken,
    required Duration espera,
  }) async {
    peticion.headers['Accept'] = 'application/json';

    if (conToken) {
      final token = await SesionStorage.leerToken();
      if (token != null) {
        peticion.headers['Authorization'] = 'Bearer $token';
      }
    }

    // 1. Enviar la petición
    final http.Response respuesta;
    try {
      final enviada = await peticion.send().timeout(espera);
      respuesta = await http.Response.fromStream(enviada);
    } on TimeoutException {
      throw ApiException(
        'La conexión tardó demasiado. Revisa tu internet e intenta de nuevo.',
      );
    } on http.ClientException {
      throw ApiException(
        'No se pudo conectar con MARK\'S. Revisa tu conexión a internet.',
      );
    }

    // 2. Leer la respuesta (utf8 para conservar acentos y la letra ñ)
    dynamic cuerpo;
    final texto = utf8.decode(respuesta.bodyBytes);
    if (texto.isNotEmpty) {
      try {
        cuerpo = jsonDecode(texto);
      } on FormatException {
        cuerpo = null;
      }
    }

    // 3. Respuesta correcta
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }

    // 4. Respuesta con error: usar el mensaje que manda la API
    String mensaje = 'Ocurrió un error (${respuesta.statusCode}). Intenta de nuevo.';
    List<String> detalles = const [];
    String? codigo;
    if (cuerpo is Map) {
      if (cuerpo['error'] is String) {
        mensaje = cuerpo['error'] as String;
      }
      if (cuerpo['detalles'] is List) {
        detalles = (cuerpo['detalles'] as List).map((d) => d.toString()).toList();
      }
      if (cuerpo['codigo'] is String) {
        codigo = cuerpo['codigo'] as String;
      }
    }

    // Si la sesión ya no es válida, se borra el token guardado
    if (respuesta.statusCode == 401 && conToken) {
      await SesionStorage.borrarToken();
    }

    throw ApiException(mensaje,
        estado: respuesta.statusCode, detalles: detalles, codigo: codigo);
  }
}