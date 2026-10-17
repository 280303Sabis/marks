import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/colores.dart';
import 'soft_ui.dart';

/// Una regla de contraseña: si se cumple y qué hacer si no.
class ReglaPassword {
  final String texto;   // descripción de la regla
  final String accion;  // indicación corta cuando falta
  final bool cumple;
  const ReglaPassword(this.texto, this.accion, this.cumple);
}

/// Reglas de contraseña segura (las mismas que valida la API).
/// Incluye la tarjeta con la lista completa (se usa en Recuperar contraseña
/// hasta el 5.10.6).
class ReglasPassword extends StatelessWidget {
  final String password;
  final String correo;

  const ReglasPassword({super.key, required this.password, required this.correo});

  /// Calcula qué reglas se cumplen.
  static List<ReglaPassword> evaluar(String password, String correo) {
    final usuarioCorreo = correo.trim().toLowerCase().split('@').first;
    final contieneCorreo =
        usuarioCorreo.length >= 4 && password.toLowerCase().contains(usuarioCorreo);

    return [
      ReglaPassword('Al menos 8 caracteres', 'Usa al menos 8 caracteres',
          password.length >= 8 && password.length <= 64),
      ReglaPassword('Una letra mayúscula', 'Agrega una letra mayúscula',
          RegExp(r'[A-Z]').hasMatch(password)),
      ReglaPassword('Una letra minúscula', 'Agrega una letra minúscula',
          RegExp(r'[a-z]').hasMatch(password)),
      ReglaPassword('Un número', 'Agrega un número', RegExp(r'\d').hasMatch(password)),
      ReglaPassword('Un símbolo (ej. ! # \$ % & *)', 'Agrega un símbolo, por ejemplo ! # \$ % & *',
          RegExp(r'[^A-Za-z0-9]').hasMatch(password)),
      ReglaPassword('No contiene tu correo', 'No uses tu correo en la contraseña',
          password.isNotEmpty && !contieneCorreo),
    ];
  }

  /// true si la contraseña cumple todas las reglas.
  static bool esSegura(String password, String correo) =>
      evaluar(password, correo).every((r) => r.cumple);

  @override
  Widget build(BuildContext context) {
    return TarjetaSuave(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu contraseña debe tener:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MarksColores.azul,
            ),
          ),
          const SizedBox(height: 8),
          for (final regla in evaluar(password, correo))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    regla.cumple ? PhosphorIconsFill.checkCircle : PhosphorIconsLight.circle,
                    size: 18,
                    color: regla.cumple ? MarksColores.verde : MarksColores.textoSuave,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      regla.texto,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: regla.cumple ? MarksColores.azul : MarksColores.textoSuave,
                        fontWeight: regla.cumple ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Indicador compacto: barra de seguridad y una sola línea con lo que falta.
/// No muestra nada mientras el campo está vacío.
class MedidorPassword extends StatelessWidget {
  final String password;
  final String correo;

  const MedidorPassword({super.key, required this.password, required this.correo});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final reglas = ReglasPassword.evaluar(password, correo);
    final cumplidas = reglas.where((r) => r.cumple).length;
    final segura = cumplidas == reglas.length;
    final pendientes = reglas.where((r) => !r.cumple);
    final faltante = pendientes.isEmpty ? null : pendientes.first;

    final Color color = segura
        ? MarksColores.verde
        : (cumplidas >= 4 ? MarksColores.alerta : MarksColores.error);

    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de seguridad (un segmento por regla)
          Row(
            children: [
              for (var i = 0; i < reglas.length; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < cumplidas ? color : MarksColores.borde,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < reglas.length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Una sola línea con lo que falta
          Row(
            children: [
              Icon(
                segura ? PhosphorIconsFill.checkCircle : PhosphorIconsLight.info,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  segura ? 'Contraseña segura' : faltante!.accion,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: segura ? MarksColores.verdeOscuro : MarksColores.azul,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}