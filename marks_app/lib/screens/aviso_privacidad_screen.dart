import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';

/// Muestra el Aviso de Privacidad vigente.
/// El texto se obtiene de la API, así siempre es la versión actual.
class AvisoPrivacidadScreen extends StatefulWidget {
  const AvisoPrivacidadScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EncabezadoMarks(
            subtitulo: 'Aviso de Privacidad',
            tamanoLogo: 36,
            onRegresar: () => Navigator.of(context).pop(),
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
                        ],
                      );
                    }

                    // Contenido
                    final aviso = estado.data!;
                    final secciones = (aviso['secciones'] as List?) ?? const [];

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      children: [
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
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}