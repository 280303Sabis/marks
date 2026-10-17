import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/colores.dart';
import '../widgets/campos_registro.dart';
import '../widgets/reglas_password.dart';
import '../widgets/soft_ui.dart';
import 'aviso_privacidad_screen.dart';
import 'confirmar_correo_screen.dart';
import 'login_screen.dart';

/// Registro de cliente en 2 pasos:
///   1. Sobre ti: nombre, apellidos, fecha de nacimiento y sexo.
///   2. Tu cuenta: correo, teléfono, contraseña y Aviso de Privacidad.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  static const int _edadMinima = 18;
  static final RegExp _formatoCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formPaso1 = GlobalKey<FormState>();
  final _formPaso2 = GlobalKey<FormState>();

  final _nombre = TextEditingController();
  final _apellidos = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  final _password = TextEditingController();

  int _paso = 1;
  DateTime? _fechaNacimiento;
  String? _sexo;
  bool _ocultarPassword = true;
  bool _aceptaAviso = false;
  bool _cargando = false;
  String? _error;

  List<TextEditingController> get _campos =>
      [_nombre, _apellidos, _correo, _telefono, _password];

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      c.addListener(_alCambiar);
    }
  }

  // Redibuja el medidor de contraseña y quita el mensaje de error
  void _alCambiar() => setState(() => _error = null);

  @override
  void dispose() {
    for (final c in _campos) {
      c.removeListener(_alCambiar);
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------
  String? _validarNombre(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 2) return 'Escribe tu nombre';
    if (t.length > 80) return 'Máximo 80 caracteres';
    return null;
  }

  String? _validarFecha(DateTime? v) {
    if (v == null) return 'Elige tu fecha de nacimiento';
    if (calcularEdad(v) < _edadMinima) {
      return 'Debes tener al menos $_edadMinima años para crear una cuenta';
    }
    return null;
  }

  String? _validarSexo(String? v) => v == null ? 'Elige una opción' : null;

  String? _validarCorreo(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Escribe tu correo';
    if (!_formatoCorreo.hasMatch(t)) return 'Escribe un correo válido';
    return null;
  }

  String? _validarTelefono(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null; // es opcional
    if (!RegExp(r'^\d{10}$').hasMatch(t)) return 'Debe tener 10 dígitos';
    return null;
  }

  String? _validarPassword(String? v) {
    if ((v ?? '').isEmpty) return 'Escribe una contraseña';
    if (!ReglasPassword.esSegura(v!, _correo.text)) return 'Tu contraseña aún no es segura';
    return null;
  }

  // ---------------------------------------------------------------
  // Navegación entre pasos
  // ---------------------------------------------------------------
  void _continuar() {
    FocusScope.of(context).unfocus();
    if (!_formPaso1.currentState!.validate()) return;
    setState(() {
      _paso = 2;
      _error = null;
    });
  }

  void _volverAlPaso1() {
    FocusScope.of(context).unfocus();
    setState(() {
      _paso = 1;
      _error = null;
    });
  }

  void _irALogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _abrirAviso() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AvisoPrivacidadScreen()),
    );
  }

  void _cambiarAceptacion(bool valor) {
    setState(() {
      _aceptaAviso = valor;
      _error = null;
    });
  }

  // ---------------------------------------------------------------
  // Crear la cuenta
  // ---------------------------------------------------------------
  Future<void> _crearCuenta() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();
    if (!_formPaso2.currentState!.validate()) return;

    if (!_aceptaAviso) {
      setState(() => _error = 'Debes aceptar el Aviso de Privacidad para crear tu cuenta.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final usuario = await AuthService.registrar(
        nombre: _nombre.text,
        apellidos: _apellidos.text,
        correo: _correo.text,
        telefono: _telefono.text,
        password: _password.text,
        fechaNacimiento: fechaIso(_fechaNacimiento!),
        sexo: _sexo!,
      );
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ConfirmarCorreoScreen(correo: usuario.correo)),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
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
    final navegador = Navigator.of(context);

    return PopScope(
      // En el paso 2, el botón "atrás" del celular regresa al paso 1
      canPop: _paso == 1,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _volverAlPaso1();
      },
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoMarks(
              subtitulo: 'Crea tu cuenta',
              tamanoLogo: 32,
              onRegresar: _paso == 2
                  ? _volverAlPaso1
                  : (navegador.canPop() ? () => navegador.pop() : null),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: [
                      BarraPasos(paso: _paso, total: 2),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        transitionBuilder: (hijo, animacion) => FadeTransition(
                          opacity: animacion,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0.06, 0),
                              end: Offset.zero,
                            ).animate(animacion),
                            child: hijo,
                          ),
                        ),
                        child: _paso == 1 ? _contenidoPaso1() : _contenidoPaso2(),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '¿Ya tienes cuenta?',
                            style: TextStyle(color: MarksColores.textoSuave),
                          ),
                          TextButton(
                            onPressed: _cargando ? null : _irALogin,
                            child: const Text('Inicia sesión'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MarksColores.azul,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          style: const TextStyle(fontSize: 14, color: MarksColores.textoSuave),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _etiqueta(String texto) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: MarksColores.azul,
          ),
        ),
      );

  /// Paso 1: Sobre ti
  Widget _contenidoPaso1() {
    return Form(
      key: _formPaso1,
      child: Column(
        key: const ValueKey('paso1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('Sobre ti', 'Cuéntanos un poco de ti.'),
          CampoSuave(
            controller: _nombre,
            hint: 'Nombre',
            icono: PhosphorIconsLight.user,
            accionTeclado: TextInputAction.next,
            autofill: const [AutofillHints.givenName],
            validador: _validarNombre,
          ),
          const SizedBox(height: 16),
          CampoSuave(
            controller: _apellidos,
            hint: 'Apellidos (opcional)',
            icono: PhosphorIconsLight.user,
            accionTeclado: TextInputAction.done,
            autofill: const [AutofillHints.familyName],
          ),
          const SizedBox(height: 22),
          _etiqueta('Fecha de nacimiento'),
          SelectorFecha(
            hint: 'Elige tu fecha',
            valorInicial: _fechaNacimiento,
            validator: _validarFecha,
            alCambiar: (f) => setState(() => _fechaNacimiento = f),
          ),
          const SizedBox(height: 22),
          _etiqueta('Sexo'),
          SelectorSexo(
            valorInicial: _sexo,
            validator: _validarSexo,
            alCambiar: (s) => setState(() => _sexo = s),
          ),
          const SizedBox(height: 28),
          BotonPrincipal(
            texto: 'Continuar',
            icono: PhosphorIconsLight.arrowRight,
            onPressed: _continuar,
          ),
        ],
      ),
    );
  }

  /// Paso 2: Tu cuenta
  Widget _contenidoPaso2() {
    return Form(
      key: _formPaso2,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('paso2'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titulo('Tu cuenta', 'Con estos datos vas a iniciar sesión.'),
            CampoSuave(
              controller: _correo,
              hint: 'Correo electrónico',
              icono: PhosphorIconsLight.envelopeSimple,
              habilitado: !_cargando,
              tipoTeclado: TextInputType.emailAddress,
              accionTeclado: TextInputAction.next,
              autofill: const [AutofillHints.email],
              validador: _validarCorreo,
            ),
            const SizedBox(height: 16),
            CampoSuave(
              controller: _telefono,
              hint: 'Teléfono, 10 dígitos (opcional)',
              icono: PhosphorIconsLight.phone,
              habilitado: !_cargando,
              tipoTeclado: TextInputType.phone,
              accionTeclado: TextInputAction.next,
              autofill: const [AutofillHints.telephoneNumberNational],
              validador: _validarTelefono,
            ),
            const SizedBox(height: 16),
            CampoSuave(
              controller: _password,
              hint: 'Crea una contraseña',
              icono: PhosphorIconsLight.lockSimple,
              habilitado: !_cargando,
              ocultarTexto: _ocultarPassword,
              accionTeclado: TextInputAction.done,
              autofill: const [AutofillHints.newPassword],
              validador: _validarPassword,
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

            // Aceptar Aviso de Privacidad
            TarjetaSuave(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              onTap: _cargando ? null : () => _cambiarAceptacion(!_aceptaAviso),
              child: Row(
                children: [
                  Checkbox(
                    value: _aceptaAviso,
                    activeColor: MarksColores.verde,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    onChanged: _cargando ? null : (v) => _cambiarAceptacion(v ?? false),
                  ),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'He leído y acepto el ',
                          style: TextStyle(fontSize: 14, color: MarksColores.azul),
                        ),
                        GestureDetector(
                          onTap: _abrirAviso,
                          child: const Text(
                            'Aviso de Privacidad',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: MarksColores.verdeOscuro,
                              decoration: TextDecoration.underline,
                              decorationColor: MarksColores.verdeOscuro,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_error != null) ...[
              TarjetaError(mensaje: _error!),
              const SizedBox(height: 20),
            ],

            BotonPrincipal(
              texto: 'Crear cuenta',
              cargando: _cargando,
              onPressed: _crearCuenta,
            ),
          ],
        ),
      ),
    );
  }
}