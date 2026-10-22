import 'dart:math';

import 'package:flutter/services.dart';

/// Validación de tarjetas para el PAGO SIMULADO de MARK'S.
///
/// Todo se revisa aquí, en el celular. A la API SOLO se envía la marca
/// y los últimos 4 dígitos: el número completo, la fecha y el CVV
/// nunca salen del teléfono ni se guardan.
class Tarjeta {
  Tarjeta._();

  static String soloDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

  /// VISA, MASTERCARD, AMEX o null si no se reconoce.
  static String? marca(String numero) {
    final d = soloDigitos(numero);
    if (d.isEmpty) return null;
    if (d.startsWith('4')) return 'VISA';
    if (RegExp(r'^3[47]').hasMatch(d)) return 'AMEX';
    if (RegExp(r'^5[1-5]').hasMatch(d)) return 'MASTERCARD';
    if (d.length >= 4) {
      final prefijo = int.parse(d.substring(0, 4));
      if (prefijo >= 2221 && prefijo <= 2720) return 'MASTERCARD';
    }
    return null;
  }

  static String nombreMarca(String? marca) => switch (marca) {
        'VISA' => 'Visa',
        'MASTERCARD' => 'Mastercard',
        'AMEX' => 'American Express',
        _ => 'Tarjeta',
      };

  /// Algoritmo de Luhn: el dígito verificador de las tarjetas.
  static bool pasaLuhn(String digitos) {
    var suma = 0;
    var doble = false;
    for (var i = digitos.length - 1; i >= 0; i--) {
      var n = int.parse(digitos[i]);
      if (doble) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      suma += n;
      doble = !doble;
    }
    return suma % 10 == 0;
  }

  /// Devuelve el error o null si el número es válido.
  static String? validarNumero(String? texto) {
    final d = soloDigitos(texto ?? '');
    if (d.isEmpty) return 'Escribe el número de la tarjeta';
    final m = marca(d);
    if (m == null) return 'Aceptamos Visa, Mastercard y American Express';
    final longitudes = switch (m) {
      'AMEX' => const [15],
      'MASTERCARD' => const [16],
      _ => const [13, 16, 19],
    };
    if (!longitudes.contains(d.length) || !pasaLuhn(d)) {
      return 'Revisa el número de la tarjeta';
    }
    return null;
  }

  /// Fecha MM/AA. La tarjeta vale hasta el último día de ese mes.
  static String? validarVencimiento(String? texto) {
    final t = (texto ?? '').trim();
    final partes = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(t);
    if (partes == null) return 'Escribe la fecha como MM/AA';
    final mes = int.parse(partes.group(1)!);
    final anio = 2000 + int.parse(partes.group(2)!);
    if (mes < 1 || mes > 12) return 'El mes debe ser de 01 a 12';
    final ahora = DateTime.now();
    final finDeMes = DateTime(anio, mes + 1, 1);
    if (!finDeMes.isAfter(ahora)) return 'La tarjeta está vencida';
    if (anio > ahora.year + 15) return 'Revisa la fecha de vencimiento';
    return null;
  }

  static String? validarCvv(String? texto, String? marca) {
    final d = soloDigitos(texto ?? '');
    final largo = marca == 'AMEX' ? 4 : 3;
    if (d.length != largo) return 'El CVV tiene $largo dígitos';
    return null;
  }

  /// Clave única para este intento de pago (UUID versión 4).
  /// Si el internet falla y se reintenta con la MISMA clave, la API no cobra dos veces.
  static String nuevaClavePago() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Escribe el número con espacios: 4242 4242 4242 4242 (Amex: 3782 822463 10005).
class FormatoNumeroTarjeta extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    var d = Tarjeta.soloDigitos(nuevo.text);
    final amex = RegExp(r'^3[47]').hasMatch(d);
    final maximo = amex ? 15 : 19;
    if (d.length > maximo) d = d.substring(0, maximo);

    final grupos = amex ? const [4, 6, 5] : const [4, 4, 4, 4, 3];
    final texto = StringBuffer();
    var i = 0;
    for (final g in grupos) {
      if (i >= d.length) break;
      if (texto.isNotEmpty) texto.write(' ');
      final fin = min(i + g, d.length);
      texto.write(d.substring(i, fin));
      i = fin;
    }
    final resultado = texto.toString();
    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
    );
  }
}

/// Escribe la fecha con diagonal: 0829 -> 08/29.
class FormatoVencimiento extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    var d = Tarjeta.soloDigitos(nuevo.text);
    if (d.length > 4) d = d.substring(0, 4);
    final resultado = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
    );
  }
}