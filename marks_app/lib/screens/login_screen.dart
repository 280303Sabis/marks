import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';
import 'confirmar_correo_screen.dart';
import 'inicio_screen.dart';
import 'recuperar_password_screen.dart';
import 'registro_screen.dart';

/// Pantalla para que el cliente inicie sesión con correo y contraseña.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _password = TextEditingController();

  bool _ocultarPassword = true;
  bool _cargando = false;
  String? _error;

  static final RegExp _formatoCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    // Al corregir cualquier campo, se quita el mensaje de error
    _correo.addListener(_limpiarError);
    _password.addListener(_limpiarError);
  }

  void _limpiarError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  void dispose() {
    _correo.removeListener(_limpiarError);
    _password.removeListener(_limpiarError);
    _correo.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validarCorreo(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Escribe tu correo';
    if (!_formatoCorreo.hasMatch(texto)) return 'Escribe un correo válido';
    return null;
  }

  String? _validarPassword(String? valor) {
    if ((valor ?? '').isEmpty) return 'Escribe tu contraseña';
    return null;
  }

  void _irARegistro() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RegistroScreen()),
    );
  }

  Future<void> _abrirRecuperar() async {
    final mensaje = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RecuperarPasswordScreen(correoInicial: _correo.text),
      ),
    );
    if (!mounted || mensaje == null) return;

    // Contraseña cambiada: se limpia el campo y se avisa
    _password.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _entrar() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus(); // oculta el teclado
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final usuario = await AuthService.iniciarSesion(_correo.text, _password.text);
      if (!mounted) return;

      // Con correo confirmado entra a Inicio; si no, primero lo confirma
      final Widget destino = usuario.correoVerificado
          ? InicioScreen(usuario: usuario)
          : ConfirmarCorreoScreen(correo: usuario.correo);

      // Borra el historial (no se puede regresar al login)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destino),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _password.clear(); // primero se borra (por seguridad)...
      setState(() => _error = e.mensaje); // ...y después se muestra el error
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navegador = Navigator.of(context);

    return Scaffold(
      body: Column(
        children: [
          EncabezadoMarks(
            subtitulo: 'Inicia sesión para comprar',
            onRegresar: navegador.canPop() ? () => navegador.pop() : null,
          ),

          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formulario,
                  child: AutofillGroup(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      children: [
                        // Saludo
                        const Text(
                          'Hola de nuevo',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: MarksColores.azul,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ingresa con tu correo y tu contraseña.',
                          style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                        ),
                        const SizedBox(height: 28),

                        // Correo
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
                        const SizedBox(height: 18),

                        // Contraseña
                        CampoSuave(
                          controller: _password,
                          hint: 'Contraseña',
                          icono: PhosphorIconsLight.lockSimple,
                          habilitado: !_cargando,
                          ocultarTexto: _ocultarPassword,
                          accionTeclado: TextInputAction.done,
                          autofill: const [AutofillHints.password],
                          validador: _validarPassword,
                          alEnviar: (_) => _entrar(),
                          sufijo: IconButton(
                            tooltip: _ocultarPassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            icon: Icon(
                              _ocultarPassword
                                  ? PhosphorIconsLight.eye
                                  : PhosphorIconsLight.eyeSlash,
                              size: 22,
                            ),
                            onPressed: () => setState(
                              () => _ocultarPassword = !_ocultarPassword,
                            ),
                          ),
                        ),

                        // Olvidé mi contraseña
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _cargando ? null : _abrirRecuperar,
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Mensaje de error de la API
                        if (_error != null) ...[
                          TarjetaError(mensaje: _error!),
                          const SizedBox(height: 20),
                        ],

                        // Botón principal
                        BotonPrincipal(
                          texto: 'Iniciar sesión',
                          cargando: _cargando,
                          onPressed: _entrar,
                        ),
                        const SizedBox(height: 24),

                        // Crear cuenta
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              '¿No tienes cuenta?',
                              style: TextStyle(color: MarksColores.textoSuave),
                            ),
                            TextButton(
                              onPressed: _cargando ? null : _irARegistro,
                              child: const Text('Crea una'),
                            ),
                          ],
                        ),
                      ],
                    ),
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