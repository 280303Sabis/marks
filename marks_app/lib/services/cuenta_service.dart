import '../models/usuario.dart';
import 'api_service.dart';

/// Mi perfil (PASO 14): datos, contraseña, sesiones, Aviso de Privacidad,
/// copia de mis datos y eliminar la cuenta.
/// Todas las rutas requieren sesión iniciada (se manda el token).
class CuentaService {
  CuentaService._();

  /// Lee el perfil completo (nombre, apellidos, teléfono, fecha, sexo, aviso...).
  static Future<Usuario> miPerfil() async {
    final r = await ApiService.get('/api/auth/yo', conToken: true);
    return Usuario.fromJson(r as Map<String, dynamic>);
  }

  /// Editar mis datos (derecho de Rectificación). El correo no se cambia aquí.
  /// [fechaNacimiento] en formato AAAA-MM-DD; [sexo]: F, M o N.
  /// Devuelve el perfil como quedó guardado.
  static Future<Usuario> editarPerfil({
    required String nombre,
    String apellidos = '',
    String telefono = '',
    required String fechaNacimiento,
    required String sexo,
  }) async {
    await ApiService.put(
      '/api/cuenta/perfil',
      conToken: true,
      datos: {
        'nombre': nombre.trim(),
        'apellidos': apellidos.trim(),
        'telefono': telefono.trim(),
        'fecha_nacimiento': fechaNacimiento,
        'sexo': sexo,
      },
    );
    return miPerfil();
  }

  /// Cambiar contraseña. La API cierra la sesión en los demás dispositivos
  /// y le da a este celular un token nuevo, que aquí se guarda.
  /// Devuelve el mensaje de la API.
  static Future<String> cambiarPassword({
    required String actual,
    required String nueva,
  }) async {
    final respuesta = await ApiService.post(
      '/api/cuenta/cambiar-password',
      conToken: true,
      datos: {'password_actual': actual, 'password_nueva': nueva},
    );
    final r = respuesta as Map<String, dynamic>;
    await SesionStorage.guardarToken(r['token'] as String);
    return (r['mensaje'] ?? 'Contraseña actualizada') as String;
  }

  /// Cierra la sesión en TODOS los dispositivos (también en este).
  static Future<void> cerrarSesionesEnTodos() async {
    await ApiService.post('/api/cuenta/cerrar-sesiones', conToken: true);
    await SesionStorage.borrarToken();
  }

  /// Copia de mis datos (derecho de Acceso): perfil, compras, puntos y opiniones.
  static Future<Map<String, dynamic>> exportarDatos() async {
    final r = await ApiService.get('/api/cuenta/exportar', conToken: true);
    return r as Map<String, dynamic>;
  }

  /// Eliminar mi cuenta (derecho de Cancelación).
  /// [confirmacion] debe ser la palabra ELIMINAR, escrita por el cliente.
  static Future<void> eliminarCuenta({
    required String password,
    required String confirmacion,
  }) async {
    await ApiService.delete(
      '/api/cuenta',
      conToken: true,
      datos: {'password': password, 'confirmacion': confirmacion},
    );
    await SesionStorage.borrarToken();
  }

  /// Aceptar el Aviso de Privacidad que el cliente acaba de leer.
  /// Si cambió mientras lo leía, la API responde 409 con codigo 'AVISO_CAMBIO'.
  static Future<void> aceptarAviso(String versionLeida) async {
    await ApiService.post(
      '/api/cuenta/aceptar-aviso',
      conToken: true,
      datos: {'version': versionLeida},
    );
  }
}