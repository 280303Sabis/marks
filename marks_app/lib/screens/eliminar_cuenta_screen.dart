import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../services/cuenta_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';
import 'bienvenida_screen.dart';

/// Eliminar mi cuenta (PASO 14, derecho de Cancelación).
/// Pide la contraseña y escribir la palabra ELIMINAR. No se puede deshacer.
class EliminarCuentaScreen extends StatefulWidget {
  final int puntos; // para avisar cuántos puntos se pierden

  const EliminarCuentaScreen({super.key, required this.puntos});

  @override
  State<EliminarCuentaScreen> createState() => _EliminarCuentaScreenState();
}

class _EliminarCuentaScreenState extends State<EliminarCuentaScreen> {
  static const String _palabra = 'ELIMINAR';

  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocultar = true;
  bool _eliminando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_alCambiar);
    _confirmacion.addListener(_alCambiar);
  }

  void _alCambiar() => setState(() => _error = null);

  @override
  void dispose() {
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  /// El botón solo se activa con la contraseña y la palabra escrita exacta.
  bool get _listo =>
      _password.text.isNotEmpty && _confirmacion.text.trim() == _palabra && !_eliminando;

  Future<void> _eliminar() async {
    if (!_listo) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _eliminando = true;
      _error = null;
    });
    try {
      await CuentaService.eliminarCuenta(
        password: _password.text,
        confirmacion: _confirmacion.text.trim(),
      );
      await CarritoService.instancia.vaciar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tu cuenta fue eliminada. Gracias por usar MARK'S")),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BienvenidaScreen()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _eliminando = false;
        _error = e.mensaje; // ej. "Contraseña incorrecta"
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final puntos = widget.puntos;
    return PopScope(
      canPop: !_eliminando,
      child: Scaffold(
        backgroundColor: MarksColores.fondo,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              // Encabezado
              Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                    onPressed: _eliminando ? null : () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Eliminar mi cuenta',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MarksColores.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Qué pasa al eliminarla
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: MarksColores.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MarksColores.error.withValues(alpha: 0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        IconoCirculo(
                          icono: PhosphorIconsLight.warning,
                          color: MarksColores.error,
                          tamano: 40,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Esto no se puede deshacer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: MarksColores.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Punto('Se borran tu nombre, correo, teléfono, fecha de nacimiento y sexo.'),
                    _Punto(puntos > 0
                        ? 'Pierdes tus $puntos puntos.'
                        : 'Tus puntos se pierden.'),
                    const _Punto('Se borran todas tus opiniones y sus fotos.'),
                    const _Punto('Tus compras se conservan sin tus datos, solo para la contabilidad '
                        'de la tienda.'),
                    const _Punto('Ya no podrás iniciar sesión con este correo.'),
                    const SizedBox(height: 4),
                    const Text(
                      'Si solo quieres una copia de tus datos, usa "Descargar mis datos" antes.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: MarksColores.textoSuave),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              CampoSuave(
                controller: _password,
                hint: 'Tu contraseña',
                icono: PhosphorIconsLight.lockSimple,
                habilitado: !_eliminando,
                ocultarTexto: _ocultar,
                accionTeclado: TextInputAction.next,
                sufijo: IconButton(
                  tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  icon: Icon(_ocultar ? PhosphorIconsLight.eye : PhosphorIconsLight.eyeSlash,
                      size: 22),
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 8),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13.5, color: MarksColores.azul),
                    children: [
                      TextSpan(text: 'Para confirmar, escribe '),
                      TextSpan(text: _palabra, style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              TextField(
                controller: _confirmacion,
                enabled: !_eliminando,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 15.5, letterSpacing: 2, color: MarksColores.azul),
                decoration: const InputDecoration(hintText: _palabra),
              ),

              if (_error != null) ...[
                const SizedBox(height: 20),
                TarjetaError(mensaje: _error!),
              ],
              const SizedBox(height: 24),

              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _listo ? _eliminar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MarksColores.error,
                    foregroundColor: MarksColores.blanco,
                  ),
                  icon: _eliminando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: MarksColores.blanco,
                          ),
                        )
                      : const Icon(PhosphorIconsLight.trash, size: 20),
                  label: Text(_eliminando ? 'Eliminando...' : 'Eliminar mi cuenta para siempre'),
                ),
              ),
              const SizedBox(height: 12),
              BotonSecundario(
                texto: 'No, conservar mi cuenta',
                onPressed: _eliminando ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renglón con viñeta.
class _Punto extends StatelessWidget {
  final String texto;

  const _Punto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 10),
            child: Icon(PhosphorIconsFill.circle, size: 6, color: MarksColores.error),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: MarksColores.azul),
            ),
          ),
        ],
      ),
    );
  }
}