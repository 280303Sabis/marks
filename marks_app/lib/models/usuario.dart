/// Datos del usuario que devuelve la API.
class Usuario {
  final int id;
  final String nombre;
  final String correo;
  final String rol;
  final int puntos;
  final bool correoVerificado;

  // Perfil completo (solo vienen en /api/auth/yo) - PASO 14
  final String? apellidos;
  final String? telefono;
  final DateTime? fechaNacimiento;
  final String? sexo;              // F, M o N (prefiere no decirlo)

  // Aviso de Privacidad (solo en /api/auth/yo) - PASO 14
  final bool avisoPendiente;       // aceptó una versión vieja: hay que pedirle la nueva
  final String? avisoVigente;      // versión vigente, ej. "1.2"

  const Usuario({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.puntos,
    required this.correoVerificado,
    this.apellidos,
    this.telefono,
    this.fechaNacimiento,
    this.sexo,
    this.avisoPendiente = false,
    this.avisoVigente,
  });

  /// La app móvil solo admite clientes.
  bool get esCliente => rol == 'CLIENTE';

  /// "Sabina Ortega González" (o solo el nombre si no tiene apellidos).
  String get nombreCompleto {
    final a = (apellidos ?? '').trim();
    return a.isEmpty ? nombre : '$nombre $a';
  }

  /// Texto opcional: null si viene vacío.
  static String? _texto(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  /// Crea un Usuario a partir de la respuesta de la API.
  /// Sirve para /api/auth/login (campo "puntos")
  /// y para /api/auth/yo (campo "puntos_saldo" y el perfil completo).
  factory Usuario.fromJson(Map<String, dynamic> json) {
    final verificado = json['correo_verificado'];
    return Usuario(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? '') as String,
      correo: (json['correo'] ?? '') as String,
      rol: (json['rol'] ?? '') as String,
      puntos: ((json['puntos'] ?? json['puntos_saldo'] ?? 0) as num).toInt(),
      correoVerificado: verificado == true || verificado == 1,
      apellidos: _texto(json['apellidos']),
      telefono: _texto(json['telefono']),
      fechaNacimiento: DateTime.tryParse((json['fecha_nacimiento'] ?? '').toString()),
      sexo: _texto(json['sexo']),
      avisoPendiente: json['aviso_pendiente'] == true,
      avisoVigente: _texto(json['aviso_vigente']),
    );
  }

  /// Copia del usuario con algunos datos distintos
  /// (por ejemplo, el saldo de puntos después de pagar).
  Usuario copiarCon({int? puntos, bool? avisoPendiente}) => Usuario(
        id: id,
        nombre: nombre,
        correo: correo,
        rol: rol,
        puntos: puntos ?? this.puntos,
        correoVerificado: correoVerificado,
        apellidos: apellidos,
        telefono: telefono,
        fechaNacimiento: fechaNacimiento,
        sexo: sexo,
        avisoPendiente: avisoPendiente ?? this.avisoPendiente,
        avisoVigente: avisoVigente,
      );
}