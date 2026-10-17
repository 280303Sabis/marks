/// Formatos de texto usados en toda la app.
class Formato {
  Formato._();

  /// 1250.5 -> "$1,250.50"
  static String precio(double valor) {
    final partes = valor.abs().toStringAsFixed(2).split('.');
    final enteros = partes[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${valor < 0 ? '-' : ''}\$$enteros.${partes[1]}';
  }

  /// 1.25 -> "1.250 kg"   |   3 -> "3"
  static String cantidad(double valor, {bool granel = false}) =>
      granel ? '${valor.toStringAsFixed(3)} kg' : valor.toStringAsFixed(0);
}