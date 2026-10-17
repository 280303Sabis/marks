import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/colores.dart';
import 'marks_logo.dart';

// ===================================================================
// SOMBRAS
// ===================================================================

/// Sombras suaves de MARK'S (estilo soft UI).
class SombrasMarks {
  SombrasMarks._();

  /// Para tarjetas, campos y botones blancos.
  static final List<BoxShadow> suave = [
    BoxShadow(
      color: MarksColores.azul.withValues(alpha: 0.07),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: MarksColores.blanco.withValues(alpha: 0.9),
      blurRadius: 12,
      offset: const Offset(-4, -4),
    ),
  ];

  /// Para el botón principal verde.
  static final List<BoxShadow> verde = [
    BoxShadow(
      color: MarksColores.verde.withValues(alpha: 0.35),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

// ===================================================================
// TARJETA
// ===================================================================

/// Tarjeta blanca con esquinas redondeadas y sombra suave.
/// Si recibe onTap, se puede tocar.
class TarjetaSuave extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radio;

  const TarjetaSuave({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.radio = 22,
  });

  @override
  Widget build(BuildContext context) {
    final bordes = BorderRadius.circular(radio);
    return Container(
      decoration: BoxDecoration(
        color: MarksColores.blanco,
        borderRadius: bordes,
        boxShadow: SombrasMarks.suave,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: bordes,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ===================================================================
// ÍCONO EN CÍRCULO
// ===================================================================

/// Ícono de línea delgada dentro de un círculo de color suave.
class IconoCirculo extends StatelessWidget {
  final IconData icono;
  final Color color;
  final double tamano;

  const IconoCirculo({
    super.key,
    required this.icono,
    this.color = MarksColores.verde,
    this.tamano = 52,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icono, color: color, size: tamano * 0.48),
    );
  }
}

// ===================================================================
// CAMPO DE TEXTO
// ===================================================================

/// Campo de texto blanco con sombra suave e ícono centrado.
/// El mensaje de validación aparece debajo, fuera de la sombra.
class CampoSuave extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData icono;
  final bool ocultarTexto;
  final bool habilitado;
  final TextInputType? tipoTeclado;
  final TextInputAction? accionTeclado;
  final Iterable<String>? autofill;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;
  final Widget? sufijo;

  const CampoSuave({
    super.key,
    required this.hint,
    required this.icono,
    this.controller,
    this.ocultarTexto = false,
    this.habilitado = true,
    this.tipoTeclado,
    this.accionTeclado,
    this.autofill,
    this.validador,
    this.alEnviar,
    this.sufijo,
  });

  static const double _alto = 58;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Sombra solo detrás del campo (no detrás del mensaje de error)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _alto,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: SombrasMarks.suave,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          enabled: habilitado,
          obscureText: ocultarTexto,
          keyboardType: tipoTeclado,
          textInputAction: accionTeclado,
          autofillHints: autofill,
          autocorrect: !ocultarTexto && tipoTeclado != TextInputType.emailAddress,
          validator: validador,
          onFieldSubmitted: alEnviar,
          style: const TextStyle(fontSize: 15.5, color: MarksColores.azul),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 18, right: 12),
              child: Icon(icono, size: 22),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: _alto),
            suffixIcon: sufijo,
          ),
        ),
      ],
    );
  }
}

// ===================================================================
// BOTONES
// ===================================================================

/// Botón principal verde con sombra suave.
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;
  final IconData? icono;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.cargando = false,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    final activo = onPressed != null && !cargando;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: activo ? SombrasMarks.verde : const [],
      ),
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        child: cargando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: MarksColores.blanco,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(texto),
                ],
              ),
      ),
    );
  }
}

/// Botón secundario blanco con sombra suave.
class BotonSecundario extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;

  const BotonSecundario({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: SombrasMarks.suave,
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 20),
              const SizedBox(width: 10),
            ],
            Text(texto),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// MENSAJE DE ERROR
// ===================================================================

/// Tarjeta roja suave con ícono de alerta.
class TarjetaError extends StatelessWidget {
  final String mensaje;

  const TarjetaError({super.key, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MarksColores.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MarksColores.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconoCirculo(
            icono: PhosphorIconsLight.warningCircle,
            color: MarksColores.error,
            tamano: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: MarksColores.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================
// ENCABEZADO
// ===================================================================

/// Panel verde con el logo centrado.
/// Si recibe onRegresar, muestra la flecha para volver.
class EncabezadoMarks extends StatelessWidget {
  final String? subtitulo;
  final VoidCallback? onRegresar;
  final double tamanoLogo;

  const EncabezadoMarks({
    super.key,
    this.subtitulo,
    this.onRegresar,
    this.tamanoLogo = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 32,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        color: MarksColores.verdeMarca,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Fila superior: flecha de regresar (o espacio vacío)
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: onRegresar == null
                  ? null
                  : Material(
                      color: MarksColores.blanco.withValues(alpha: 0.22),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onRegresar,
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            PhosphorIconsLight.arrowLeft,
                            color: MarksColores.blanco,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          MarksLogo(tamano: tamanoLogo, color: MarksColores.blanco),
          if (subtitulo != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarksColores.blanco,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===================================================================
// CONFIRMACIÓN
// ===================================================================

/// Ventana flotante de confirmación.
/// Devuelve true si el usuario confirma.
Future<bool> mostrarConfirmacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String textoConfirmar,
  IconData icono = PhosphorIconsLight.question,
  bool peligro = false,
}) async {
  final Color colorAccion = peligro ? MarksColores.error : MarksColores.verde;

  final resultado = await showDialog<bool>(
    context: context,
    barrierColor: MarksColores.azul.withValues(alpha: 0.35),
    builder: (contexto) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconoCirculo(icono: icono, color: colorAccion, tamano: 64),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MarksColores.azul,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: MarksColores.textoSuave,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: MarksColores.fondo,
                    ),
                    onPressed: () => Navigator.of(contexto).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorAccion,
                    ),
                    onPressed: () => Navigator.of(contexto).pop(true),
                    child: Text(textoConfirmar),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return resultado == true;
}