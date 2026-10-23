import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/cuenta_service.dart';
import '../theme/colores.dart';
import '../widgets/reglas_password.dart';
import '../widgets/soft_ui.dart';

/// Cambiar contraseña (PASO 14).
/// Usa las mismas reglas y el mismo medidor que el registro.
/// La API cierra la sesión en los demás dispositivos; este celular sigue con sesión.
/// Al terminar regresa el mensaje de la API.
class CambiarPasswordScreen extends StatefulWidget {
  final String correo; // para la regla "no debe contener tu correo"

  const CambiarPasswordScreen({super.key, required this.correo});

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _formulario = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();

  bool _ocultar = true;
  bool _guardando = false;
  String? _error;

  List<TextEditingController> get _campos => [_actual, _nueva, _repetir];

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      c.addListener(_alCambiar);
    }
  }

  // Redibuja el medidor y quita el mensaje de error
  void _alCambiar() => setState(() => _error = null);

  @override
  void dispose() {
    for (final c in _campos) {
      c.removeListener(_alCambiar);
      c.dispose();
    }
    super.dispose();
  }

  String? _validarActual(String? v) =>
      (v ?? '').isEmpty ? 'Escribe tu contraseña actual' : null;

  String? _validarNueva(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Escribe tu nueva contraseña';
    if (t == _actual.text) return 'Debe ser diferente a la actual';
    if (!ReglasPassword.esSegura(t, widget.correo)) return 'Tu contraseña aún no es segura';
    return null;
  }

  String? _validarRepetir(String? v) =>
      (v ?? '') != _nueva.text ? 'Las contraseñas no coinciden' : null;

  Future<void> _guardar() async {
    if (_guardando) return;
    FocusScope.of(context).unfocus();
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final mensaje = await CuentaService.cambiarPassword(
        actual: _actual.text,
        nueva: _nueva.text,
      );
      if (mounted) Navigator.of(context).pop(mensaje);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.detalles.isEmpty
            ? e.mensaje
            : '${e.mensaje}:\n- ${e.detalles.join('\n- ')}';
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _ojo() => IconButton(
        tooltip: _ocultar ? 'Mostrar contraseñas' : 'Ocultar contraseñas',
        icon: Icon(_ocultar ? PhosphorIconsLight.eye : PhosphorIconsLight.eyeSlash, size: 22),
        onPressed: () => setState(() => _ocultar = !_ocultar),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_guardando,
      child: Scaffold(
        backgroundColor: MarksColores.fondo,
        body: SafeArea(
          child: Form(
            key: _formulario,
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  // Encabezado
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Regresar',
                        icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                        onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                      ),
                      const Text(
                        'Cambiar contraseña',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: MarksColores.azul,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Por seguridad, al cambiarla se cerrará tu sesión en tus otros '
                      'dispositivos. En este celular seguirás dentro.',
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: MarksColores.textoSuave),
                    ),
                  ),
                  const SizedBox(height: 20),

                  CampoSuave(
                    controller: _actual,
                    hint: 'Contraseña actual',
                    icono: PhosphorIconsLight.lockSimple,
                    habilitado: !_guardando,
                    ocultarTexto: _ocultar,
                    accionTeclado: TextInputAction.next,
                    autofill: const [AutofillHints.password],
                    validador: _validarActual,
                    sufijo: _ojo(),
                  ),
                  const SizedBox(height: 16),
                  CampoSuave(
                    controller: _nueva,
                    hint: 'Nueva contraseña',
                    icono: PhosphorIconsLight.lockKey,
                    habilitado: !_guardando,
                    ocultarTexto: _ocultar,
                    accionTeclado: TextInputAction.next,
                    autofill: const [AutofillHints.newPassword],
                    validador: _validarNueva,
                  ),
                  MedidorPassword(password: _nueva.text, correo: widget.correo),
                  const SizedBox(height: 16),
                  CampoSuave(
                    controller: _repetir,
                    hint: 'Repite la nueva contraseña',
                    icono: PhosphorIconsLight.lockKey,
                    habilitado: !_guardando,
                    ocultarTexto: _ocultar,
                    accionTeclado: TextInputAction.done,
                    validador: _validarRepetir,
                    alEnviar: (_) => _guardar(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    TarjetaError(mensaje: _error!),
                  ],
                  const SizedBox(height: 24),

                  BotonPrincipal(
                    texto: 'Cambiar contraseña',
                    icono: PhosphorIconsLight.check,
                    cargando: _guardando,
                    onPressed: _guardar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}