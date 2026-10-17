import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/colores.dart';
import 'soft_ui.dart';

// ===================================================================
// FECHAS
// ===================================================================

const List<String> _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "15 de enero de 2000"
String fechaLarga(DateTime fecha) => '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year}';

/// "2000-01-15" (formato que espera la API)
String fechaIso(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Años cumplidos a la fecha de hoy.
int calcularEdad(DateTime nacimiento) {
  final hoy = DateTime.now();
  var edad = hoy.year - nacimiento.year;
  if (hoy.month < nacimiento.month ||
      (hoy.month == nacimiento.month && hoy.day < nacimiento.day)) {
    edad--;
  }
  return edad;
}

/// Mensaje de error del campo (debajo del campo, como los demás).
Widget _mensajeError(String texto) => Padding(
      padding: const EdgeInsets.only(left: 18, top: 6),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 12.5, color: MarksColores.error),
      ),
    );

// ===================================================================
// SELECTOR DE FECHA
// ===================================================================

/// Campo con calendario para elegir la fecha de nacimiento.
/// Funciona dentro de un Form (se valida con validate()).
class SelectorFecha extends FormField<DateTime> {
  SelectorFecha({
    super.key,
    required String hint,
    DateTime? valorInicial,
    super.validator,
    ValueChanged<DateTime>? alCambiar,
    bool habilitado = true,
  }) : super(
          initialValue: valorInicial,
          enabled: habilitado,
          builder: (estado) {
            final valor = estado.value;

            Future<void> elegir() async {
              final hoy = DateTime.now();
              final elegida = await showDatePicker(
                context: estado.context,
                initialDate: valor ?? DateTime(hoy.year - 25, hoy.month, hoy.day),
                firstDate: DateTime(hoy.year - 120),
                lastDate: hoy,
                initialDatePickerMode: DatePickerMode.year, // empieza en los años
                helpText: 'Fecha de nacimiento',
                cancelText: 'Cancelar',
                confirmText: 'Aceptar',
              );
              if (elegida != null) {
                estado.didChange(elegida);
                alCambiar?.call(elegida);
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: MarksColores.blanco,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: SombrasMarks.suave,
                    border: estado.hasError
                        ? Border.all(color: MarksColores.error, width: 1.2)
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: habilitado ? elegir : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            const Icon(
                              PhosphorIconsLight.calendarBlank,
                              size: 22,
                              color: MarksColores.textoSuave,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                valor == null ? hint : fechaLarga(valor),
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: valor == null
                                      ? MarksColores.textoSuave
                                      : MarksColores.azul,
                                ),
                              ),
                            ),
                            const Icon(
                              PhosphorIconsLight.caretDown,
                              size: 18,
                              color: MarksColores.textoSuave,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (estado.hasError) _mensajeError(estado.errorText!),
              ],
            );
          },
        );
}

// ===================================================================
// SELECTOR DE SEXO
// ===================================================================

/// Tres botones: Femenino (F), Masculino (M), Prefiero no decirlo (N).
class SelectorSexo extends FormField<String> {
  SelectorSexo({
    super.key,
    String? valorInicial,
    super.validator,
    ValueChanged<String>? alCambiar,
    bool habilitado = true,
  }) : super(
          initialValue: valorInicial,
          enabled: habilitado,
          builder: (estado) {
            Widget opcion(String clave, String texto) => _OpcionSexo(
                  texto: texto,
                  seleccionada: estado.value == clave,
                  alTocar: habilitado
                      ? () {
                          estado.didChange(clave);
                          alCambiar?.call(clave);
                        }
                      : null,
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: opcion('F', 'Femenino')),
                    const SizedBox(width: 12),
                    Expanded(child: opcion('M', 'Masculino')),
                  ],
                ),
                const SizedBox(height: 12),
                opcion('N', 'Prefiero no decirlo'),
                if (estado.hasError) _mensajeError(estado.errorText!),
              ],
            );
          },
        );
}

class _OpcionSexo extends StatelessWidget {
  final String texto;
  final bool seleccionada;
  final VoidCallback? alTocar;

  const _OpcionSexo({required this.texto, required this.seleccionada, this.alTocar});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        color: seleccionada ? MarksColores.verde : MarksColores.blanco,
        borderRadius: BorderRadius.circular(16),
        boxShadow: seleccionada ? SombrasMarks.verde : SombrasMarks.suave,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: alTocar,
          child: Center(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: seleccionada ? FontWeight.w600 : FontWeight.w500,
                color: seleccionada ? MarksColores.blanco : MarksColores.azul,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================
// BARRA DE PASOS
// ===================================================================

/// "Paso 1 de 2" con barra de progreso animada.
class BarraPasos extends StatelessWidget {
  final int paso;
  final int total;

  const BarraPasos({super.key, required this.paso, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paso $paso de $total',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: MarksColores.verdeOscuro,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: paso / total),
            duration: const Duration(milliseconds: 350),
            builder: (context, valor, _) => LinearProgressIndicator(
              value: valor,
              minHeight: 6,
              backgroundColor: MarksColores.borde,
              color: MarksColores.verde,
            ),
          ),
        ),
      ],
    );
  }
}