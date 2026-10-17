import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/verificacion_service.dart';
import '../theme/colores.dart';
import '../widgets/reglas_password.dart';
import '../widgets/soft_ui.dart';

/// Recuperación de contraseña en dos etapas:
/// 1. El cliente escribe su correo y se le envía un código.
/// 2. Escribe el código y su nueva contraseña.
/// Al terminar regresa al login con un mensaje de éxito.
class RecuperarPasswordScreen extends StatefulWidget {
  final String correoInicial;

  const RecuperarPasswordScreen({super.key, this.correoInicial = ''});

  @override
  State<RecuperarPasswordScreen> createState() => _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _formCorreo = GlobalKey<FormState>();
  final _formNueva = GlobalKey<FormState>();

  late final TextEditingController _correo;
  final _codigo = TextEditingController();
  final _password = TextEditingController();

  bool _codigoEnviado = false; // false = etapa 1, true = etapa 2
  bool _cargando = false;
  bool _ocultarPassword = true;
  String? _aviso;
  String? _error;

  Timer? _temporizador;
  int _segundos = 0;

  static final RegExp _formatoCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  List<TextEditingController> get _campos => [_correo, _codigo, _password];

  @override
  void initState() {
    super.initState();
    _correo = TextEditingController(text: widget.correoInicial.trim());
    for (final c in _campos) {
      c.addListener(_alCambiar);
    }
  }

  // Redibuja el medidor y quita el mensaje de error
  void _alCambiar() => setState(() => _error = null);

  @override
  void dispose() {
    _temporizador?.cancel();
    for (final c in _campos) {
      c.removeListener(_alCambiar);
      c.dispose();
    }
    super.dispose();
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

  // ---------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------
  String? _validarCorreo(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Escribe tu correo';
    if (!_formatoCorreo.hasMatch(t)) return 'Escribe un correo válido';
    return null;
  }

  String? _validarCodigo(String? v) {
    if (!RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())) {
      return 'Escribe los 6 dígitos del código';
    }
    return null;
  }

  String? _validarPassword(String? v) {
    if ((v ?? '').isEmpty) return 'Escribe tu nueva contraseña';
    if (!ReglasPassword.esSegura(v!, _correo.text)) return 'Tu contraseña aún no es segura';
    return null;
  }

  // ---------------------------------------------------------------
  // Etapa 1: enviar código
  // ---------------------------------------------------------------
  Future<void> _enviarCodigo() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();
    if (!_codigoEnviado && !_formCorreo.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final mensaje = await VerificacionService.solicitarRecuperacion(_correo.text);
      if (!mounted) return;
      setState(() {
        _aviso = mensaje;
        _codigoEnviado = true;
      });
      _iniciarCuenta(60);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarCorreo() {
    _temporizador?.cancel();
    _codigo.clear();
    _password.clear();
    setState(() {
      _codigoEnviado = false;
      _segundos = 0;
      _aviso = null;
      _error = null;
    });
  }

  // ---------------------------------------------------------------
  // Etapa 2: guardar la nueva contraseña
  // ---------------------------------------------------------------
  Future<void> _guardar() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();
    if (!_formNueva.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final mensaje = await VerificacionService.restablecerPassword(
        correo: _correo.text,
        codigo: _codigo.text,
        passwordNueva: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(mensaje); // regresa al login con el mensaje
    } on ApiException catch (e) {
      if (!mounted) return;
      _codigo.clear();
      setState(() {
        _error = e.detalles.isEmpty
            ? e.mensaje
            : '${e.mensaje}:\n- ${e.detalles.join('\n- ')}';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------------------------------------------------------------
  // Pantalla
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EncabezadoMarks(
            subtitulo: 'Recupera tu contraseña',
            tamanoLogo: 32,
            onRegresar: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  children: [
                    Center(
                      child: IconoCirculo(
                        icono: _codigoEnviado
                            ? PhosphorIconsLight.lockKeyOpen
                            : PhosphorIconsLight.lockKey,
                        tamano: 72,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _codigoEnviado ? 'Crea tu nueva contraseña' : '¿Olvidaste tu contraseña?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: MarksColores.azul,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _codigoEnviado
                          ? 'Escribe el código que enviamos a ${_correo.text.trim()} y tu nueva contraseña.'
                          : 'Escribe el correo de tu cuenta y te enviaremos un código de 6 dígitos.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: MarksColores.textoSuave,
                      ),
                    ),
                    const SizedBox(height: 26),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: _codigoEnviado ? _etapaNueva() : _etapaCorreo(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Etapa 1: correo.
  Widget _etapaCorreo() {
    return Form(
      key: _formCorreo,
      child: Column(
        key: const ValueKey('etapa1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoSuave(
            controller: _correo,
            hint: 'Correo electrónico',
            icono: PhosphorIconsLight.envelopeSimple,
            habilitado: !_cargando,
            tipoTeclado: TextInputType.emailAddress,
            accionTeclado: TextInputAction.done,
            autofill: const [AutofillHints.email],
            validador: _validarCorreo,
            alEnviar: (_) => _enviarCodigo(),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            TarjetaError(mensaje: _error!),
            const SizedBox(height: 20),
          ],
          BotonPrincipal(
            texto: 'Enviar código',
            icono: PhosphorIconsLight.paperPlaneTilt,
            cargando: _cargando,
            onPressed: _enviarCodigo,
          ),
        ],
      ),
    );
  }

  /// Etapa 2: código y nueva contraseña.
  Widget _etapaNueva() {
    return Form(
      key: _formNueva,
      child: Column(
        key: const ValueKey('etapa2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Aviso de envío
          if (_aviso != null) ...[
            TarjetaSuave(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(PhosphorIconsLight.info, color: MarksColores.verde, size: 22),
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
            const SizedBox(height: 20),
          ],

          CampoSuave(
            controller: _codigo,
            hint: 'Código de 6 dígitos',
            icono: PhosphorIconsLight.password,
            habilitado: !_cargando,
            tipoTeclado: TextInputType.number,
            accionTeclado: TextInputAction.next,
            autofill: const [AutofillHints.oneTimeCode],
            validador: _validarCodigo,
          ),
          const SizedBox(height: 16),
          CampoSuave(
            controller: _password,
            hint: 'Nueva contraseña',
            icono: PhosphorIconsLight.lockSimple,
            habilitado: !_cargando,
            ocultarTexto: _ocultarPassword,
            accionTeclado: TextInputAction.done,
            autofill: const [AutofillHints.newPassword],
            validador: _validarPassword,
            alEnviar: (_) => _guardar(),
            sufijo: IconButton(
              tooltip: _ocultarPassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
              icon: Icon(
                _ocultarPassword ? PhosphorIconsLight.eye : PhosphorIconsLight.eyeSlash,
                size: 22,
              ),
              onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
            ),
          ),
          MedidorPassword(password: _password.text, correo: _correo.text),
          const SizedBox(height: 22),

          if (_error != null) ...[
            TarjetaError(mensaje: _error!),
            const SizedBox(height: 20),
          ],

          BotonPrincipal(
            texto: 'Guardar nueva contraseña',
            cargando: _cargando,
            onPressed: _guardar,
          ),
          const SizedBox(height: 12),

          // Reenviar y cambiar correo
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: (_cargando || _segundos > 0) ? null : _enviarCodigo,
                icon: const Icon(PhosphorIconsLight.arrowClockwise, size: 18),
                label: Text(
                  _segundos > 0 ? 'Reenviar código en $_segundos s' : 'Reenviar código',
                ),
              ),
              TextButton(
                onPressed: _cargando ? null : _cambiarCorreo,
                style: TextButton.styleFrom(foregroundColor: MarksColores.textoSuave),
                child: const Text('Cambiar correo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}