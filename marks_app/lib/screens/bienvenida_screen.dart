import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/colores.dart';
import '../widgets/soft_ui.dart';
import 'login_screen.dart';
import 'registro_screen.dart';

/// Primera pantalla que ve el cliente al abrir la app.
class BienvenidaScreen extends StatelessWidget {
  const BienvenidaScreen({super.key});

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const EncabezadoMarks(
            subtitulo: 'Compra en el súper sin filas',
            tamanoLogo: 52,
          ),

          // Beneficios
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  children: const [
                    Text(
                      '¿Cómo funciona?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: MarksColores.azul,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tu compra completa en tres pasos.',
                      style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                    ),
                    SizedBox(height: 20),
                    _Beneficio(
                      icono: PhosphorIconsLight.scan,
                      titulo: 'Escanea',
                      texto: 'Usa la cámara de tu celular para agregar productos.',
                    ),
                    SizedBox(height: 14),
                    _Beneficio(
                      icono: PhosphorIconsLight.creditCard,
                      titulo: 'Paga en la app',
                      texto: 'Sin pasar por caja ni hacer fila.',
                    ),
                    SizedBox(height: 14),
                    _Beneficio(
                      icono: PhosphorIconsLight.storefront,
                      titulo: 'Apoya lo local',
                      texto: 'Productos de Nuevo León y puntos en cada compra.',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botones fijos abajo
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BotonPrincipal(
                        texto: 'Iniciar sesión',
                        onPressed: () => _abrir(context, const LoginScreen()),
                      ),
                      const SizedBox(height: 14),
                      BotonSecundario(
                        texto: 'Crear cuenta',
                        onPressed: () => _abrir(context, const RegistroScreen()),
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

/// Tarjeta de beneficio: ícono en círculo, título y descripción.
class _Beneficio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;

  const _Beneficio({
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return TarjetaSuave(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconoCirculo(icono: icono),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.azul,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: MarksColores.textoSuave,
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