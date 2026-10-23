import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../services/cuenta_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';

/// Muestra el Aviso de Privacidad vigente.
/// El texto se obtiene de la API, así siempre es la versión actual.
///
/// Con [paraAceptar] = true (PASO 14) se usa cuando el aviso cambió:
/// no se puede salir con "atrás" y abajo están "Acepto" y "No acepto".
/// Devuelve true si aceptó, false si no aceptó.
class AvisoPrivacidadScreen extends StatefulWidget {
  final bool paraAceptar;

  const AvisoPrivacidadScreen({super.key, this.paraAceptar = false});

  @override
  State<AvisoPrivacidadScreen> createState() => _AvisoPrivacidadScreenState();
}

class _AvisoPrivacidadScreenState extends State<AvisoPrivacidadScreen> {
  late Future<Map<String, dynamic>> _aviso;

  @override
  void initState() {
    super.initState();
    _aviso = _cargar();
  }

  Future<Map<String, dynamic>> _cargar() async {
    final respuesta = await ApiService.get('/api/legal/aviso-privacidad');
    return respuesta as Map<String, dynamic>;
  }

  void _reintentar() {
    setState(() => _aviso = _cargar());
  }

  bool _aceptando = false;
  String? _errorAceptar;

  /// Acepta la versión que se está mostrando en pantalla.
  Future<void> _aceptar(String version) async {
    setState(() {
      _aceptando = true;
      _errorAceptar = null;
    });
    try {
      await CuentaService.aceptarAviso(version);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorAceptar = e.mensaje);
      // Si el aviso cambió mientras lo leía, se carga la versión nueva
      if (e.codigo == 'AVISO_CAMBIO') _reintentar();
    } finally {
      if (mounted) setState(() => _aceptando = false);
    }
  }

  Future<void> _noAceptar() async {
    final salir = await mostrarConfirmacion(
      context,
      titulo: '¿No aceptas el aviso?',
      mensaje: 'Para usar MARK\'S es necesario aceptar el Aviso de Privacidad vigente. '
          'Si no lo aceptas se cerrará tu sesión. Tu cuenta no se borra: '
          'puedes volver a entrar y aceptarlo cuando quieras.',
      textoConfirmar: 'Cerrar sesión',
      icono: PhosphorIconsLight.signOut,
      peligro: true,
    );
    if (salir && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final paraAceptar = widget.paraAceptar;
    return PopScope(
      // Cuando hay que aceptarlo, "atrás" no lo cierra
      canPop: !paraAceptar,
      child: Scaffold(
        body: Column(
          children: [
            EncabezadoMarks(
              subtitulo: paraAceptar
                  ? 'Actualizamos nuestro Aviso de Privacidad'
                  : 'Aviso de Privacidad',
              tamanoLogo: 36,
              onRegresar: paraAceptar ? null : () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _aviso,
                    builder: (context, estado) {
                      // Cargando
                      if (estado.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Error
                      if (estado.hasError) {
                        final error = estado.error;
                        final mensaje = error is ApiException
                            ? error.mensaje
                            : 'No se pudo cargar el Aviso de Privacidad.';
                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            TarjetaError(mensaje: mensaje),
                            const SizedBox(height: 20),
                            BotonPrincipal(
                              texto: 'Reintentar',
                              icono: PhosphorIconsLight.arrowClockwise,
                              onPressed: _reintentar,
                            ),
                            // Sin internet no se puede aceptar: deja salir (cierra sesión)
                            if (paraAceptar) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                style: TextButton.styleFrom(
                                  foregroundColor: MarksColores.textoSuave,
                                ),
                                child: const Text('Salir'),
                              ),
                            ],
                          ],
                        );
                      }

                      // Contenido
                      final aviso = estado.data!;
                      final secciones = (aviso['secciones'] as List?) ?? const [];

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                        children: [
                          // Por qué se muestra (solo cuando hay que aceptarlo)
                          if (paraAceptar) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: MarksColores.verde.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Text(
                                'Hicimos cambios en cómo cuidamos tus datos: ahora el aviso '
                                'explica los pagos, los puntos y las opiniones con fotos. '
                                'Léelo y, si estás de acuerdo, acéptalo al final para seguir '
                                'usando la app.',
                                style: TextStyle(fontSize: 14, height: 1.45, color: MarksColores.azul),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Versión y fecha
                          TarjetaSuave(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const IconoCirculo(icono: PhosphorIconsLight.shieldCheck),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Versión ${aviso['version'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: MarksColores.azul,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Última actualización: ${aviso['fecha'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: MarksColores.textoSuave,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Secciones
                          for (final seccion in secciones) ...[
                            TarjetaSuave(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${seccion['titulo'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      color: MarksColores.azul,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${seccion['texto'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.55,
                                      color: MarksColores.azul,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Contacto
                          if (aviso['contacto'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Para dudas o para ejercer tus derechos ARCO escribe a: '
                                '${aviso['contacto']}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: MarksColores.textoSuave,
                                ),
                              ),
                            ),

                          // Aceptar / No aceptar (solo cuando hay que aceptarlo)
                          if (paraAceptar) ...[
                            const SizedBox(height: 24),
                            if (_errorAceptar != null) ...[
                              TarjetaError(mensaje: _errorAceptar!),
                              const SizedBox(height: 16),
                            ],
                            BotonPrincipal(
                              texto: 'Acepto el Aviso de Privacidad',
                              icono: PhosphorIconsLight.check,
                              cargando: _aceptando,
                              onPressed: () => _aceptar('${aviso['version'] ?? ''}'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _aceptando ? null : _noAceptar,
                              style: TextButton.styleFrom(foregroundColor: MarksColores.textoSuave),
                              child: const Text('No acepto'),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}