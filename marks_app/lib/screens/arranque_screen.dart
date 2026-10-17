import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/colores.dart';
import '../widgets/marks_logo.dart';
import '../widgets/soft_ui.dart';
import 'bienvenida_screen.dart';
import 'confirmar_correo_screen.dart';
import 'inicio_screen.dart';

/// Primera pantalla al abrir la app.
/// Revisa si hay una sesión guardada y decide a dónde ir:
/// - Sin sesión                     -> Bienvenida
/// - Sesión con correo sin confirmar -> Confirmar correo
/// - Sesión con correo confirmado    -> Inicio
/// - Sin conexión                    -> tarjeta con botón para reintentar
class ArranqueScreen extends StatefulWidget {
  const ArranqueScreen({super.key});

  @override
  State<ArranqueScreen> createState() => _ArranqueScreenState();
}

class _ArranqueScreenState extends State<ArranqueScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _revisarSesion();
  }

  Future<void> _revisarSesion() async {
    try {
      final usuario = await AuthService.usuarioActual();
      if (!mounted) return;

      final Widget destino;
      if (usuario == null) {
        destino = const BienvenidaScreen();
      } else if (!usuario.correoVerificado) {
        destino = ConfirmarCorreoScreen(correo: usuario.correo);
      } else {
        destino = InicioScreen(usuario: usuario);
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animacion, secundaria) => destino,
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animacion, secundaria, hijo) =>
              FadeTransition(opacity: animacion, child: hijo),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Ocurrió un error al abrir la app. Intenta de nuevo.');
    }
  }

  void _reintentar() {
    setState(() => _error = null);
    _revisarSesion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarksColores.verdeMarca,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MarksLogo(tamano: 56, color: MarksColores.blanco),
                  const SizedBox(height: 10),
                  const Text(
                    'Compra en el súper sin filas',
                    style: TextStyle(
                      color: MarksColores.blanco,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (_error == null)
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: MarksColores.blanco,
                      ),
                    )
                  else
                    TarjetaSuave(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const IconoCirculo(
                            icono: PhosphorIconsLight.wifiX,
                            color: MarksColores.error,
                            tamano: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Sin conexión',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: MarksColores.azul,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: MarksColores.textoSuave,
                            ),
                          ),
                          const SizedBox(height: 22),
                          BotonPrincipal(
                            texto: 'Reintentar',
                            icono: PhosphorIconsLight.arrowClockwise,
                            onPressed: _reintentar,
                          ),
                        ],
                      ),
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