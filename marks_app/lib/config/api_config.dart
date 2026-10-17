/// Configuración de conexión con la API de MARK'S.
class ApiConfig {
  ApiConfig._();

  /// Dirección de la API.
  /// En desarrollo, el celular llega a la API por el cable USB
  /// (comando adb reverse dentro de correr_celular.ps1), por eso la
  /// dirección siempre es 127.0.0.1 sin importar la red Wi-Fi.
  ///
  /// Para usar otra dirección sin tocar el código:
  ///   flutter run --dart-define=API_URL=http://192.168.0.122:5000
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:5000',
  );

  /// Tiempo máximo de espera por una respuesta de la API.
  static const Duration tiempoEspera = Duration(seconds: 10);
}