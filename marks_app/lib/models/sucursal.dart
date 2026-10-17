/// Sucursal (tienda) de MARK'S.
class Sucursal {
  final int id;
  final String nombre;
  final String direccion;
  final String municipio;

  const Sucursal({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.municipio,
  });

  factory Sucursal.fromJson(Map<String, dynamic> json) => Sucursal(
        id: (json['id'] as num).toInt(),
        nombre: (json['nombre'] ?? '') as String,
        direccion: (json['direccion'] ?? '') as String,
        municipio: (json['municipio'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'direccion': direccion,
        'municipio': municipio,
      };

  /// "Av. Manuel Ordóñez 100, Santa Catarina"
  String get ubicacion =>
      [direccion, municipio].where((t) => t.trim().isNotEmpty).join(', ');
}