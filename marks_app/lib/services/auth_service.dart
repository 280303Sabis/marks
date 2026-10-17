import '../models/usuario.dart';
import 'api_service.dart';

/// Manejo de la sesión del cliente: registrar, iniciar, recordar y cerrar sesión.
class AuthService {
  AuthService._();

  static const String _soloClientes =
      'Esta app es solo para clientes. El personal de MARK\'S '
      'entra desde la página web, en "Acceso personal".';

  /// Crea una cuenta de cliente.
  /// fechaNacimiento en formato AAAA-MM-DD; sexo: F, M o N.
  /// La API exige aceptar el Aviso de Privacidad y tener 18 años o más.
  static Future<Usuario> registrar({
    required String nombre,
    String? apellidos,
    required String correo,
    String? telefono,
    required String password,
    required String fechaNacimiento,
    required String sexo,
  }) async {
    final respuesta = await ApiService.post(
      '/api/auth/registro',
      datos: {
        'nombre': nombre.trim(),
        'apellidos': (apellidos ?? '').trim(),
        'correo': correo.trim().toLowerCase(),
        'telefono': (telefono ?? '').trim(),
        'password': password,
        'fecha_nacimiento': fechaNacimiento,
        'sexo': sexo,
        'acepta_privacidad': true,
      },
    );

    await SesionStorage.guardarToken(respuesta['token'] as String);
    return Usuario.fromJson(respuesta['usuario'] as Map<String, dynamic>);
  }

  /// Inicia sesión con correo y contraseña.
  /// Después pide el perfil completo para saber si el correo está confirmado.
  static Future<Usuario> iniciarSesion(String correo, String password) async {
    final respuesta = await ApiService.post(
      '/api/auth/login',
      datos: {
        'correo': correo.trim().toLowerCase(),
        'password': password,
      },
    );

    final basico = Usuario.fromJson(respuesta['usuario'] as Map<String, dynamic>);

    // El personal (ADMIN y GUARDIA) no usa la app móvil
    if (!basico.esCliente) {
      throw ApiException(_soloClientes, estado: 403);
    }

    await SesionStorage.guardarToken(respuesta['token'] as String);

    // Perfil completo (incluye correo_verificado)
    final perfil = await ApiService.get('/api/auth/yo', conToken: true);
    return Usuario.fromJson(perfil as Map<String, dynamic>);
  }

  /// Revisa si hay una sesión guardada y si sigue siendo válida.
  /// Devuelve el usuario, o null si debe iniciar sesión de nuevo.
  static Future<Usuario?> usuarioActual() async {
    final token = await SesionStorage.leerToken();
    if (token == null) return null;

    try {
      final respuesta = await ApiService.get('/api/auth/yo', conToken: true);
      final usuario = Usuario.fromJson(respuesta as Map<String, dynamic>);
      if (!usuario.esCliente) {
        await SesionStorage.borrarToken();
        return null;
      }
      return usuario;
    } on ApiException catch (e) {
      // Token vencido o sesión cerrada desde otro dispositivo
      if (e.sesionExpirada) return null;
      rethrow; // sin conexión u otro error: se informa a la pantalla
    }
  }

  /// Cierra la sesión en este celular.
  static Future<void> cerrarSesion() => SesionStorage.borrarToken();
}