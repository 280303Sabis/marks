import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/opinion.dart';
import '../services/api_service.dart';
import '../services/opiniones_service.dart';
import '../theme/colores.dart';
import '../widgets/opiniones_ui.dart';
import '../widgets/soft_ui.dart';
import 'opinar_screen.dart';

/// Opiniones de un producto (PASO 13): promedio, barritas por estrella,
/// mi opinión y lo que dicen los demás clientes (con fotos y Reportar).
/// Desde aquí se califica el producto o se edita mi opinión (PASO 13.5).
class OpinionesProductoScreen extends StatefulWidget {
  final int productoId;
  final String nombre;

  const OpinionesProductoScreen({super.key, required this.productoId, required this.nombre});

  @override
  State<OpinionesProductoScreen> createState() => _OpinionesProductoScreenState();
}

class _OpinionesProductoScreenState extends State<OpinionesProductoScreen> {
  OpinionesProducto? _datos;
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
      final datos = await OpinionesService.deProducto(widget.productoId, limite: 50);
      if (!mounted) return;
      setState(() => _datos = datos);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Abre Calificar / Editar. Si se guardó o se borró algo, recarga.
  Future<void> _abrirOpinar({Opinion? existente}) async {
    final cambio = await abrirOpinar(
      context,
      productoId: widget.productoId,
      nombre: widget.nombre,
      existente: existente,
    );
    if (cambio && mounted) _cargar();
  }

  /// Pide el motivo y manda el reporte. La opinión sigue visible: solo se avisa al admin.
  Future<void> _reportar(Opinion opinion) async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MarksColores.fondo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '¿Por qué reportas esta opinión?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: MarksColores.azul,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Un administrador la revisará.',
                  style: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                ),
              ),
              for (final opcion in motivosReporte.entries)
                ListTile(
                  leading: const Icon(PhosphorIconsLight.flag, color: MarksColores.azul),
                  title: Text(opcion.value, style: const TextStyle(color: MarksColores.azul)),
                  onTap: () => Navigator.of(context).pop(opcion.key),
                ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.x, color: MarksColores.textoSuave),
                title: const Text('Cancelar', style: TextStyle(color: MarksColores.textoSuave)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
    if (motivo == null) return;
    try {
      _aviso(await OpinionesService.reportar(opinion.id, motivo));
    } on ApiException catch (e) {
      _aviso(e.mensaje); // ej. "Ya reportaste esta opinión"
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarksColores.fondo,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Encabezado
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Opiniones',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: MarksColores.azul,
                          ),
                        ),
                        Text(
                          widget.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _contenido()),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    final d = _datos;
    if (d == null) {
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
                _error ?? 'No se pudieron cargar las opiniones.',
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

    // La mía va aparte (arriba); en la lista solo las de los demás
    final otras = d.opiniones.where((o) => !o.esMia).toList();
    final mia = d.miOpinion;

    return RefreshIndicator(
      color: MarksColores.verde,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          if (!d.activas) ...[
            const _Aviso(
              icono: PhosphorIconsLight.prohibit,
              texto: 'Las opiniones de este producto están desactivadas por ahora.',
            ),
            const SizedBox(height: 16),
          ],

          // Resumen
          TarjetaSuave(
            padding: const EdgeInsets.all(18),
            child: d.resumen.vacio
                ? const Row(
                    children: [
                      Icon(PhosphorIconsLight.star, color: colorEstrella, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Todavía nadie califica este producto.',
                          style: TextStyle(fontSize: 14, color: MarksColores.azul),
                        ),
                      ),
                    ],
                  )
                : ResumenEstrellas(resumen: d.resumen),
          ),

          // Invitación a calificar (compró el producto y todavía no opina)
          if (mia == null && d.puedeOpinar) ...[
            const SizedBox(height: 16),
            TarjetaSuave(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '¿Ya lo probaste?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MarksColores.azul,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Compraste este producto. Tu opinión ayuda a otros clientes.',
                    style: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                  ),
                  const SizedBox(height: 14),
                  BotonPrincipal(
                    texto: 'Calificar producto',
                    icono: PhosphorIconsLight.star,
                    onPressed: () => _abrirOpinar(),
                  ),
                ],
              ),
            ),
          ],

          // Mi opinión
          if (mia != null) ...[
            const _Titulo('Tu opinión'),
            TarjetaOpinion(
              opinion: mia,
              pie: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _abrirOpinar(existente: mia),
                  icon: const Icon(PhosphorIconsLight.pencilSimple, size: 18),
                  label: const Text('Editar o borrar'),
                  style: TextButton.styleFrom(foregroundColor: MarksColores.verdeOscuro),
                ),
              ),
            ),
          ],

          // Las de los demás
          if (otras.isNotEmpty) ...[
            const _Titulo('Lo que dicen los clientes'),
            for (final o in otras)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TarjetaOpinion(opinion: o, onReportar: () => _reportar(o)),
              ),
          ],
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;

  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: MarksColores.azul,
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Aviso({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MarksColores.azul.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: MarksColores.azul),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13, height: 1.4, color: MarksColores.azul),
            ),
          ),
        ],
      ),
    );
  }
}