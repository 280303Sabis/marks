import 'api_service.dart';

/// Confirmación de correo y recuperación de contraseña con código de 6 dígitos.
/// Los códigos los genera y envía la API por correo; la app nunca los conoce.
class VerificacionService {
  VerificacionService._();

  static String _mensaje(dynamic respuesta, String porDefecto) {
    if (respuesta is Map && respuesta['mensaje'] is String) {
      return respuesta['mensaje'] as String;
    }
    return porDefecto;
  }

  // ---------------------------------------------------------------
  // Confirmar correo (requiere sesión iniciada)
  // ---------------------------------------------------------------

  /// Pide a la API que envíe el código al correo del usuario.
  /// Devuelve el mensaje de la API (por ejemplo, "Te enviamos un código a ...").
  static Future<String> enviarCodigoCorreo() async {
    final respuesta = await ApiService.post(
      '/api/auth/correo/enviar-codigo',
      conToken: true,
    );
    return _mensaje(respuesta, 'Te enviamos un código a tu correo.');
  }

  /// Valida el código. Si es incorrecto lanza ApiException
  /// con el mensaje de la API (incluye los intentos que quedan).
  static Future<void> confirmarCorreo(String codigo) async {
    await ApiService.post(
      '/api/auth/correo/confirmar',
      datos: {'codigo': codigo.trim()},
      conToken: true,
    );
  }

  // ---------------------------------------------------------------
  // Recuperar contraseña (sin sesión)
  // ---------------------------------------------------------------

  /// Pide un código para restablecer la contraseña.
  /// La API responde lo mismo exista o no el correo (por seguridad).
  static Future<String> solicitarRecuperacion(String correo) async {
    final respuesta = await ApiService.post(
      '/api/auth/recuperar/solicitar',
      datos: {'correo': correo.trim().toLowerCase()},
    );
    return _mensaje(respuesta, 'Si el correo está registrado, te enviamos un código.');
  }

  /// Guarda la nueva contraseña usando el código recibido.
  /// Al hacerlo, la API cierra todas las sesiones abiertas de esa cuenta.
  static Future<String> restablecerPassword({
    required String correo,
    required String codigo,
    required String passwordNueva,
  }) async {
    final respuesta = await ApiService.post(
      '/api/auth/recuperar/restablecer',
      datos: {
        'correo': correo.trim().toLowerCase(),
        'codigo': codigo.trim(),
        'password_nueva': passwordNueva,
      },
    );
    return _mensaje(respuesta, 'Contraseña actualizada. Ya puedes iniciar sesión.');
  }

  /// Si la API responde "Espera 45 segundos...", devuelve 45.
  /// Sirve para mostrar la cuenta regresiva del botón "Reenviar código".
  static int? segundosDeEspera(String mensaje) {
    final coincidencia = RegExp(r'Espera (\d+) segundos').firstMatch(mensaje);
    return coincidencia == null ? null : int.tryParse(coincidencia.group(1)!);
  }
}