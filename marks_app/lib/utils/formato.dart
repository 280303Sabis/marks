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

  static const List<String> _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  /// 2026-10-22 14:36 -> "22 oct 2026 · 14:36"
  static String fecha(DateTime? f) {
    if (f == null) return '';
    final hora = f.hour.toString().padLeft(2, '0');
    final minuto = f.minute.toString().padLeft(2, '0');
    return '${f.day} ${_meses[f.month - 1]} ${f.year} · $hora:$minuto';
  }
}