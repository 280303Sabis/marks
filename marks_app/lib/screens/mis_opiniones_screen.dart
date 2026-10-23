import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/opinion.dart';
import '../services/api_service.dart';
import '../services/opiniones_service.dart';
import '../theme/colores.dart';
import '../widgets/opiniones_ui.dart';
import '../widgets/soft_ui.dart';
import 'opinar_screen.dart';

/// Mis opiniones (PASO 13): pestañas "Por calificar" y "Publicadas".
class MisOpinionesScreen extends StatefulWidget {
  const MisOpinionesScreen({super.key});

  @override
  State<MisOpinionesScreen> createState() => _MisOpinionesScreenState();
}

class _MisOpinionesScreenState extends State<MisOpinionesScreen> {
  MisOpiniones? _datos;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await OpinionesService.mias();
      if (!mounted) return;
      setState(() => _datos = datos);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Calificar un pendiente o editar una publicada. Si cambió algo, recarga.
  Future<void> _opinar({required int productoId, required String nombre, Opinion? existente}) async {
    final cambio = await abrirOpinar(
      context,
      productoId: productoId,
      nombre: nombre,
      existente: existente,
    );
    if (cambio && mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MarksColores.fondo,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Regresar',
                      icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'Mis opiniones',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: MarksColores.azul,
                      ),
                    ),
                  ],
                ),
              ),
              if (d == null)
                Expanded(child: _sinDatos())
              else ...[
                TabBar(
                  labelColor: MarksColores.azul,
                  unselectedLabelColor: MarksColores.textoSuave,
                  indicatorColor: MarksColores.verde,
                  indicatorWeight: 3,
                  dividerColor: MarksColores.borde,
                  labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: 'Por calificar (${d.pendientes.length})'),
                    Tab(text: 'Publicadas (${d.publicadas.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _listaPendientes(d.pendientes),
                      _listaPublicadas(d.publicadas),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Cargando por primera vez, o error sin datos.
  Widget _sinDatos() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: MarksColores.verde));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? 'No se pudieron cargar tus opiniones.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: MarksColores.textoSuave),
            ),
            const SizedBox(height: 16),
            BotonSecundario(
              texto: 'Reintentar',
              icono: PhosphorIconsLight.arrowClockwise,
              onPressed: _cargar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaPendientes(List<PendienteOpinion> pendientes) {
    return RefreshIndicator(
      color: MarksColores.verde,
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (pendientes.isEmpty)
            const _Vacio(
              icono: PhosphorIconsLight.checkCircle,
              titulo: 'Todo calificado',
              texto: 'Cuando compres algo nuevo, aquí aparecerá para que lo califiques.',
            )
          else ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Productos que compraste. Tu opinión ayuda a otros clientes.',
                style: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
              ),
            ),
            for (final p in pendientes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TarjetaSuave(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  onTap: () => _opinar(productoId: p.productoId, nombre: p.nombre),
                  child: Row(
                    children: [
                      const IconoCirculo(
                        icono: PhosphorIconsLight.package,
                        color: MarksColores.verde,
                        tamano: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nombre,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: MarksColores.azul,
                              ),
                            ),
                            if (p.compradoEn != null)
                              Text(
                                'Comprado el ${fechaOpinion(p.compradoEn)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: MarksColores.textoSuave,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsLight.star, size: 16, color: colorEstrella),
                          SizedBox(width: 4),
                          Text(
                            'Calificar',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: MarksColores.verdeOscuro,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _listaPublicadas(List<Opinion> publicadas) {
    return RefreshIndicator(
      color: MarksColores.verde,
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (publicadas.isEmpty)
            const _Vacio(
              icono: PhosphorIconsLight.chatText,
              titulo: 'Todavía no opinas',
              texto: 'Califica los productos que compraste desde "Por calificar" o desde tus tickets.',
            )
          else
            for (final o in publicadas)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TarjetaOpinion(
                  opinion: o,
                  mostrarProducto: true,
                  pie: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _opinar(
                        productoId: o.productoId,
                        nombre: o.producto ?? '',
                        existente: o,
                      ),
                      icon: const Icon(PhosphorIconsLight.pencilSimple, size: 18),
                      label: const Text('Editar o borrar'),
                      style: TextButton.styleFrom(foregroundColor: MarksColores.verdeOscuro),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Mensaje cuando una pestaña no tiene nada.
class _Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;

  const _Vacio({required this.icono, required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          IconoCirculo(icono: icono, color: MarksColores.verde, tamano: 64),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: MarksColores.azul,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.4, color: MarksColores.textoSuave),
          ),
        ],
      ),
    );
  }
}