import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/venta.dart';
import '../services/api_service.dart';
import '../services/compras_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../utils/tarjeta.dart';
import '../widgets/soft_ui.dart';
import 'opinar_screen.dart';
import 'opiniones_producto_screen.dart';

/// Ticket de una compra con su QR de salida (PASO 10).
/// El guardia escanea el QR en la salida para validar la compra.
/// Desde aquí se califica cada producto (PASO 13), excepto justo al pagar.
class TicketScreen extends StatefulWidget {
  final Venta venta;
  final bool recienPagada; // true: se acaba de pagar (muestra "Pago aprobado")

  const TicketScreen({super.key, required this.venta, this.recienPagada = false});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  /// El ticket se vuelve a pedir después de opinar (para cambiar los botones).
  late Venta venta = widget.venta;

  bool get recienPagada => widget.recienPagada;

  /// Calificar (si no ha opinado) o ver/editar mi opinión (si ya opinó).
  Future<void> _opinar(LineaVenta linea) async {
    final productoId = linea.productoId;
    if (productoId == null) return;
    if (linea.yaOpino) {
      // Abre las opiniones del producto: ahí está "Editar o borrar"
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OpinionesProductoScreen(productoId: productoId, nombre: linea.nombre),
        ),
      );
    } else {
      final cambio = await abrirOpinar(context, productoId: productoId, nombre: linea.nombre);
      if (!cambio) return;
    }
    await _recargar();
  }

  Future<void> _recargar() async {
    try {
      final nueva = await ComprasService.verCompra(venta.folio);
      if (mounted) setState(() => venta = nueva);
    } on ApiException {
      // Sin conexión: se queda el ticket que ya tenía
    }
  }

  static String _fecha(DateTime? f) {
    if (f == null) return '';
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(f.day)}/${d2(f.month)}/${f.year}  ${d2(f.hour)}:${d2(f.minute)}';
  }

  void _volverAlInicio(BuildContext context) =>
      Navigator.of(context).popUntil((ruta) => ruta.isFirst);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarksColores.fondo,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            // Encabezado
            if (recienPagada) ...[
              const Center(
                child: IconoCirculo(icono: PhosphorIconsLight.checkCircle, tamano: 72),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pago aprobado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: MarksColores.azul,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gracias por comprar en MARK\'S',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
              ),
            ] else
              Row(
                children: [
                  IconButton(
                    tooltip: 'Regresar',
                    icon: const Icon(PhosphorIconsLight.arrowLeft, color: MarksColores.azul),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Tu compra',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MarksColores.azul,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),

            // Pase de salida
            TarjetaSuave(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: venta.pendienteDeSalida
                  ? Column(
                      children: [
                        const Text(
                          'Tu pase de salida',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: MarksColores.azul,
                          ),
                        ),
                        const SizedBox(height: 12),
                        QrImageView(
                          data: venta.qr!,
                          version: QrVersions.auto,
                          size: 230,
                          backgroundColor: MarksColores.blanco,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: MarksColores.azul,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: MarksColores.azul,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          venta.folio,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: MarksColores.azul,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Muestra este código al guardia en la salida. '
                          'Si no lo lee, sube el brillo de tu pantalla.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: MarksColores.textoSuave,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      children: [
                        IconoCirculo(icono: PhosphorIconsLight.sealCheck, tamano: 44),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Esta compra ya se validó en la salida.',
                            style: TextStyle(fontSize: 14, color: MarksColores.azul),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // Detalle del ticket
            TarjetaSuave(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Fila(texto: 'Sucursal', valor: venta.sucursal),
                  _Fila(texto: 'Fecha', valor: _fecha(venta.pagadaEn)),
                  _Fila(
                    texto: 'Pagado con',
                    valor: '${Tarjeta.nombreMarca(venta.marcaTarjeta)} •••• ${venta.ultimos4}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: MarksColores.borde),
                  ),
                  for (final l in venta.lineas)
                    _LineaTicket(
                      linea: l,
                      // Al recién pagar no se muestra: primero hay que probar el producto
                      alOpinar: (!recienPagada && venta.permiteOpinar && l.admiteOpinion)
                          ? () => _opinar(l)
                          : null,
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: MarksColores.borde),
                  ),
                  _Fila(
                    texto: 'Subtotal (${venta.articulos} artículos)',
                    valor: Formato.precio(venta.subtotal),
                  ),
                  if (venta.ahorro > 0)
                    _Fila(
                      texto: 'Ahorraste',
                      valor: '-${Formato.precio(venta.ahorro)}',
                      color: MarksColores.verdeOscuro,
                    ),
                  if (venta.puntosUsados > 0)
                    _Fila(
                      texto: 'Pagado con puntos (${venta.puntosUsados})',
                      valor: '-${Formato.precio(venta.descuentoPuntos)}',
                      color: MarksColores.verdeOscuro,
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: MarksColores.azul,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        Formato.precio(venta.total),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: MarksColores.verdeOscuro,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (venta.puntosGanados > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MarksColores.verde,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: SombrasMarks.verde,
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsLight.star, color: MarksColores.blanco, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ganaste ${venta.puntosGanados} puntos con esta compra',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.blanco,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            BotonPrincipal(
              texto: 'Volver al inicio',
              icono: PhosphorIconsLight.house,
              onPressed: () => _volverAlInicio(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila "texto ........ valor".
class _Fila extends StatelessWidget {
  final String texto;
  final String valor;
  final Color? color;

  const _Fila({required this.texto, required this.valor, this.color});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(fontSize: 13.5, color: color ?? MarksColores.textoSuave);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: estilo),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: estilo.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un producto del ticket.
class _LineaTicket extends StatelessWidget {
  final LineaVenta linea;

  /// null: no se muestra el botón de opinar.
  final VoidCallback? alOpinar;

  const _LineaTicket({required this.linea, this.alOpinar});

  @override
  Widget build(BuildContext context) {
    final detalle = linea.esGranel
        ? '${linea.cantidad.toStringAsFixed(3)} kg x ${Formato.precio(linea.precioFinal)}'
        : '${linea.cantidad.toStringAsFixed(0)} x ${Formato.precio(linea.precioFinal)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.azul,
                  ),
                ),
                Text(
                  linea.tieneOferta ? '$detalle  (oferta)' : detalle,
                  style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                ),
                if (alOpinar != null)
                  TextButton.icon(
                    onPressed: alOpinar,
                    icon: Icon(
                      linea.yaOpino ? PhosphorIconsFill.star : PhosphorIconsLight.star,
                      size: 16,
                      color: const Color(0xFFF2B01E),
                    ),
                    label: Text(linea.yaOpino ? 'Ver mi opinión' : 'Calificar'),
                    style: TextButton.styleFrom(
                      foregroundColor: MarksColores.verdeOscuro,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formato.precio(linea.importe),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MarksColores.azul,
            ),
          ),
        ],
      ),
    );
  }
}