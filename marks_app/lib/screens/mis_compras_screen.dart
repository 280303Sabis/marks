import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/venta.dart';
import '../services/api_service.dart';
import '../services/compras_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/soft_ui.dart';
import 'ticket_screen.dart';

/// Mis compras (PASO 12): historial del cliente, de la más nueva a la más vieja.
/// Al tocar una compra se abre su ticket (con el QR si todavía no sale de la tienda).
class MisComprasScreen extends StatefulWidget {
  const MisComprasScreen({super.key});

  @override
  State<MisComprasScreen> createState() => _MisComprasScreenState();
}

class _MisComprasScreenState extends State<MisComprasScreen> {
  ListaCompras? _lista;
  bool _cargando = true;
  String? _error;
  String? _abriendo; // folio que se está abriendo (para mostrar el indicador)

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _lista == null; // la primera vez se muestra el indicador grande
      _error = null;
    });
    try {
      final lista = await ComprasService.listar();
      if (!mounted) return;
      setState(() => _lista = lista);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(ResumenCompra compra) async {
    if (_abriendo != null) return;
    setState(() => _abriendo = compra.folio);
    try {
      final venta = await ComprasService.verCompra(compra.folio);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TicketScreen(venta: venta)),
      );
      if (mounted) _cargar(); // por si el guardia ya la validó
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _abriendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarksColores.fondo,
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Mis compras',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MarksColores.azul,
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
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error sin datos previos: mensaje y botón para reintentar
    if (_lista == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TarjetaError(mensaje: _error ?? 'No se pudieron cargar tus compras.'),
          const SizedBox(height: 16),
          BotonSecundario(
            texto: 'Reintentar',
            icono: PhosphorIconsLight.arrowClockwise,
            onPressed: _cargar,
          ),
        ],
      );
    }

    final compras = _lista!.compras;
    return RefreshIndicator(
      color: MarksColores.verde,
      onRefresh: _cargar, // deslizar hacia abajo para actualizar
      child: compras.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
              children: const [
                Center(
                  child: IconoCirculo(
                    icono: PhosphorIconsLight.receipt,
                    color: MarksColores.azul,
                    tamano: 80,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  'Aún no tienes compras',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: MarksColores.azul,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Escanea tus productos y paga desde la app. Tus tickets aparecerán aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: compras.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _TarjetaCompra(
                compra: compras[i],
                abriendo: _abriendo == compras[i].folio,
                alTocar: () => _abrir(compras[i]),
              ),
            ),
    );
  }
}

/// Una compra en la lista.
class _TarjetaCompra extends StatelessWidget {
  final ResumenCompra compra;
  final bool abriendo;
  final VoidCallback alTocar;

  const _TarjetaCompra({
    required this.compra,
    required this.abriendo,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final n = compra.articulos;
    return TarjetaSuave(
      padding: const EdgeInsets.all(16),
      onTap: alTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  compra.folio,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: MarksColores.azul,
                  ),
                ),
              ),
              _EtiquetaEstado(estado: compra.estado),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${Formato.fecha(compra.pagadaEn)} · ${compra.sucursal}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$n ${n == 1 ? 'artículo' : 'artículos'}',
                style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
              ),
              if (compra.puntosGanados > 0) ...[
                const SizedBox(width: 10),
                const Icon(PhosphorIconsLight.star, size: 14, color: MarksColores.verdeOscuro),
                const SizedBox(width: 3),
                Text(
                  '+${compra.puntosGanados}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.verdeOscuro,
                  ),
                ),
              ],
              const Spacer(),
              if (abriendo)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  Formato.precio(compra.total),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: MarksColores.azul,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(PhosphorIconsLight.caretRight, size: 16, color: MarksColores.textoSuave),
            ],
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de color según el estado de la compra.
class _EtiquetaEstado extends StatelessWidget {
  final String estado;

  const _EtiquetaEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (estado) {
      'PAGADA' => ('Por salir', MarksColores.alerta),
      'VALIDADA' => ('Validada', MarksColores.verdeOscuro),
      'CANCELADA' => ('Cancelada', MarksColores.error),
      _ => (estado, MarksColores.textoSuave),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}