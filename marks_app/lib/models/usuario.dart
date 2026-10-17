/// Datos del usuario que devuelve la API.
class Usuario {
  final int id;
  final String nombre;
  final String correo;
  final String rol;
  final int puntos;
  final bool correoVerificado;

  const Usuario({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.puntos,
    required this.correoVerificado,
  });

  /// La app móvil solo admite clientes.
  bool get esCliente => rol == 'CLIENTE';

  /// Crea un Usuario a partir de la respuesta de la API.
  /// Sirve para /api/auth/login (campo "puntos")
  /// y para /api/auth/yo (campo "puntos_saldo").
  factory Usuario.fromJson(Map<String, dynamic> json) {
    final verificado = json['correo_verificado'];
    return Usuario(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '') as String,
      correo: (json['correo'] ?? '') as String,
      rol: (json['rol'] ?? '') as String,
      puntos: ((json['puntos'] ?? json['puntos_saldo'] ?? 0) as num).toInt(),
      correoVerificado: verificado == true || verificado == 1,
    );
  }
}