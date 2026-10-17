import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/verificacion_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';
import 'bienvenida_screen.dart';
import 'inicio_screen.dart';

/// Confirmación obligatoria del correo con un código de 6 dígitos.
/// No se puede entrar a la app hasta confirmar el correo.
class ConfirmarCorreoScreen extends StatefulWidget {
  final String correo;

  const ConfirmarCorreoScreen({super.key, required this.correo});

  @override
  State<ConfirmarCorreoScreen> createState() => _ConfirmarCorreoScreenState();
}

class _ConfirmarCorreoScreenState extends State<ConfirmarCorreoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _codigo = TextEditingController();

  bool _enviando = false;
  bool _confirmando = false;
  String? _aviso; // mensaje informativo (código enviado)
  String? _error;

  Timer? _temporizador;
  int _segundos = 0; // cuenta regresiva para reenviar

  @override
  void initState() {
    super.initState();
    _codigo.addListener(_limpiarError);
    _enviarCodigo(); // se envía automáticamente al abrir
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _codigo.removeListener(_limpiarError);
    _codigo.dispose();
    super.dispose();
  }

  void _limpiarError() {
    if (_error != null) setState(() => _error = null);
  }

  void _iniciarCuenta(int segundos) {
    _temporizador?.cancel();
    setState(() => _segundos = segundos);
    _temporizador = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _segundos--);
      if (_segundos <= 0) t.cancel();
    });
  }

  /// Entra a la app con los datos actualizados del usuario.
  Future<void> _entrarAInicio({bool recienConfirmado = false}) async {
    final usuario = await AuthService.usuarioActual();
    if (!mounted) return;

    if (usuario == null) {
      _irABienvenida();
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => InicioScreen(usuario: usuario)),
      (_) => false,
    );
    if (recienConfirmado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo confirmado. Tu cuenta está protegida.')),
      );
    }
  }

  void _irABienvenida() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BienvenidaScreen()),
      (_) => false,
    );
  }

  Future<void> _enviarCodigo() async {
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final mensaje = await VerificacionService.enviarCodigoCorreo();
      if (!mounted) return;

      // Si ya estaba confirmado, pasa directo a la app
      if (mensaje.contains('ya está confirmado')) {
        await _entrarAInicio();
        return;
      }

      setState(() => _aviso = mensaje);
      _iniciarCuenta(60);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.sesionExpirada) {
        _irABienvenida();
        return;
      }
      final espera = VerificacionService.segundosDeEspera(e.mensaje);
      if (espera != null) {
        // Ya se había enviado uno hace poco: se usa ese mismo código
        setState(() => _aviso = 'Ya te enviamos un código hace poco. Revisa tu correo.');
        _iniciarCuenta(espera);
      } else {
        setState(() => _error = e.mensaje);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String? _validarCodigo(String? v) {
    final t = (v ?? '').trim();
    if (!RegExp(r'^\d{6}$').hasMatch(t)) return 'Escribe los 6 dígitos del código';
    return null;
  }

  Future<void> _confirmar() async {
    if (_confirmando) return;
    FocusScope.of(context).unfocus();
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _confirmando = true;
      _error = null;
    });

    try {
      await VerificacionService.confirmarCorreo(_codigo.text);
      if (!mounted) return;
      await _entrarAInicio(recienConfirmado: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _codigo.clear();
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  /// Cierra la sesión para registrarse con otro correo o entrar con otra cuenta.
  Future<void> _usarOtroCorreo() async {
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Usar otro correo?',
      mensaje: 'Se cerrará la sesión y podrás crear tu cuenta con otro correo '
          'o entrar con otra cuenta.',
      textoConfirmar: 'Continuar',
      icono: PhosphorIconsLight.envelopeSimple,
    );
    if (!confirmar) return;

    await AuthService.cerrarSesion();
    if (!mounted) return;
    _irABienvenida();
  }

  @override
  Widget build(BuildContext context) {
    final puedeReenviar = !_enviando && _segundos <= 0;
    final ocupado = _enviando || _confirmando;

    return Scaffold(
      body: Column(
        children: [
          const EncabezadoMarks(
            subtitulo: 'Confirma tu correo',
            tamanoLogo: 36,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formulario,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    children: [
                      const Center(
                        child: IconoCirculo(
                          icono: PhosphorIconsLight.envelopeOpen,
                          tamano: 76,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Revisa tu correo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: MarksColores.azul,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Para proteger tu cuenta, escribe el código de 6 dígitos que enviamos a',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.correo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.azul,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Estado del envío
                      if (_enviando)
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Enviando código...',
                              style: TextStyle(color: MarksColores.textoSuave),
                            ),
                          ],
                        )
                      else if (_aviso != null)
                        TarjetaSuave(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(
                                PhosphorIconsLight.info,
                                color: MarksColores.verde,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _aviso!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: MarksColores.azul,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Código
                      CampoSuave(
                        controller: _codigo,
                        hint: 'Código de 6 dígitos',
                        icono: PhosphorIconsLight.password,
                        habilitado: !_confirmando,
                        tipoTeclado: TextInputType.number,
                        accionTeclado: TextInputAction.done,
                        autofill: const [AutofillHints.oneTimeCode],
                        validador: _validarCodigo,
                        alEnviar: (_) => _confirmar(),
                      ),
                      const SizedBox(height: 20),

                      if (_error != null) ...[
                        TarjetaError(mensaje: _error!),
                        const SizedBox(height: 20),
                      ],

                      BotonPrincipal(
                        texto: 'Confirmar correo',
                        cargando: _confirmando,
                        onPressed: _confirmar,
                      ),
                      const SizedBox(height: 16),

                      // Reenviar
                      Center(
                        child: TextButton.icon(
                          onPressed: puedeReenviar ? _enviarCodigo : null,
                          icon: const Icon(PhosphorIconsLight.arrowClockwise, size: 18),
                          label: Text(
                            _segundos > 0
                                ? 'Reenviar código en $_segundos s'
                                : 'Reenviar código',
                          ),
                        ),
                      ),

                      // Usar otro correo
                      Center(
                        child: TextButton(
                          onPressed: ocupado ? null : _usarOtroCorreo,
                          style: TextButton.styleFrom(
                            foregroundColor: MarksColores.textoSuave,
                          ),
                          child: const Text('¿Correo equivocado? Usar otro correo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}