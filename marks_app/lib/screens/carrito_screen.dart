import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/carrito.dart';
import '../models/sucursal.dart';
import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/soft_ui.dart';
import 'pago_screen.dart';

/// Pantalla del carrito.
/// Muestra lo que el cliente escaneó y le pide a la API el total real.
class CarritoScreen extends StatefulWidget {
  final Sucursal sucursal;

  const CarritoScreen({super.key, required this.sucursal});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final CarritoService _carrito = CarritoService.instancia;

  CotizacionCarrito? _cotizacion;
  bool _cotizando = false;
  String? _error;
  int _peticion = 0; // para ignorar respuestas viejas si el cliente cambia rápido

  @override
  void initState() {
    super.initState();
    _carrito.addListener(_alCambiarCarrito);
    _carrito.cargar().then((_) => _cotizar());
  }

  @override
  void dispose() {
    _carrito.removeListener(_alCambiarCarrito);
    super.dispose();
  }

  /// Cada cambio en el carrito se vuelve a calcular en la API.
  void _alCambiarCarrito() {
    if (mounted) _cotizar();
  }

  Future<void> _cotizar() async {
    if (_carrito.vacio) {
      setState(() {
        _cotizacion = null;
        _error = null;
        _cotizando = false;
      });
      return;
    }
    final numero = ++_peticion;
    setState(() {
      _cotizando = true;
      _error = null;
    });
    try {
      final resultado = await _carrito.cotizar();
      if (!mounted || numero != _peticion) return;
      setState(() => _cotizacion = resultado);
    } on ApiException catch (e) {
      if (!mounted || numero != _peticion) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted && numero == _peticion) setState(() => _cotizando = false);
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String accion) async {
    final respuesta = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: Text(accion, style: const TextStyle(color: MarksColores.error)),
          ),
        ],
      ),
    );
    return respuesta == true;
  }

  Future<void> _quitar(LineaCarrito linea) async {
    final ok = await _confirmar(
      'Quitar producto',
      '¿Quitar ${linea.nombre} de tu carrito?',
      'Quitar',
    );
    if (ok) await _carrito.quitar(linea.id);
  }

  Future<void> _restar(LineaCarrito linea) async {
    if (linea.cantidad <= 1) {
      await _quitar(linea);
    } else {
      await _carrito.cambiarCantidad(linea.id, linea.cantidad - 1);
    }
  }

  Future<void> _vaciar() async {
    final ok = await _confirmar(
      'Vaciar carrito',
      'Se quitarán todos los productos de tu carrito.',
      'Vaciar',
    );
    if (ok) await _carrito.vaciar();
  }

  Future<void> _continuarAlPago() async {
    final c = _cotizacion;
    if (c == null || !c.sePuedePagar) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PagoScreen(sucursal: widget.sucursal, cotizacion: c)),
    );
    // Si regresó sin pagar (por ejemplo, el total cambió), se recalcula el carrito
    if (mounted && !_carrito.vacio) _cotizar();
  }

  @override
  Widget build(BuildContext context) {
    final lineas = _carrito.lineas;

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tu carrito',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: MarksColores.azul,
                          ),
                        ),
                        Text(
                          widget.sucursal.nombre,
                          style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  if (lineas.isNotEmpty)
                    TextButton.icon(
                      onPressed: _vaciar,
                      icon: const Icon(PhosphorIconsLight.trash, size: 18, color: MarksColores.error),
                      label: const Text('Vaciar', style: TextStyle(color: MarksColores.error)),
                    ),
                ],
              ),
            ),
            if (_cotizando) const LinearProgressIndicator(minHeight: 2),

            // Contenido
            Expanded(
              child: lineas.isEmpty
                                    // Devuelve true: "quiero escanear" (Inicio abre el escáner)
                  ? _CarritoVacio(alEscanear: () => Navigator.of(context).pop(true))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      itemCount: lineas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _TarjetaLinea(
                        linea: lineas[i],
                        calculada: _cotizacion?.linea(i),
                        alSumar: lineas[i].cantidad < CarritoService.maxPiezas
                            ? () => _carrito.cambiarCantidad(lineas[i].id, lineas[i].cantidad + 1)
                            : null,
                        alRestar: () => _restar(lineas[i]),
                        alQuitar: () => _quitar(lineas[i]),
                      ),
                    ),
            ),

            // Resumen
            if (lineas.isNotEmpty)
              _Resumen(
                cotizacion: _cotizacion,
                cotizando: _cotizando,
                error: _error,
                alReintentar: _cotizar,
                alPagar: _continuarAlPago,
              ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una línea del carrito.
class _TarjetaLinea extends StatelessWidget {
  final LineaCarrito linea;
  final LineaCotizada? calculada;
  final VoidCallback? alSumar;
  final VoidCallback alRestar;
  final VoidCallback alQuitar;

  const _TarjetaLinea({
    required this.linea,
    required this.calculada,
    required this.alSumar,
    required this.alRestar,
    required this.alQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final c = calculada;
    final error = c?.error;
    final precio = c?.precioFinal ?? linea.precioFinal;

    final detalle = linea.esGranel
        ? '${linea.pesoKg?.toStringAsFixed(3) ?? '-'} kg x ${Formato.precio(precio)}'
        : '${Formato.precio(precio)} c/u';

    return TarjetaSuave(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoCirculo(
                icono: linea.esGranel ? PhosphorIconsLight.scales : PhosphorIconsLight.package,
                color: error == null ? MarksColores.verde : MarksColores.error,
                tamano: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linea.nombre,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MarksColores.azul,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                    ),
                    if (linea.esGranel || (c?.tieneOferta ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (linea.esGranel)
                              _Chip(
                                texto: linea.desdeBascula ? 'Báscula' : 'Peso escrito',
                                color: MarksColores.azul,
                              ),
                            if (c?.tieneOferta ?? false)
                              const _Chip(texto: 'Oferta', color: MarksColores.alerta),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c?.importe != null ? Formato.precio(c!.importe!) : '-',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: error == null ? MarksColores.azul : MarksColores.textoSuave,
                ),
              ),
            ],
          ),

          // Error de la línea (caducado, agotado, sin existencias...)
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(PhosphorIconsLight.warningCircle, size: 16, color: MarksColores.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(fontSize: 13, color: MarksColores.error),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),
          Row(
            children: [
              if (!linea.esGranel) ...[
                _BotonCantidad(icono: PhosphorIconsLight.minus, alTocar: alRestar),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${linea.cantidad}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MarksColores.azul,
                    ),
                  ),
                ),
                _BotonCantidad(icono: PhosphorIconsLight.plus, alTocar: alSumar),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: alQuitar,
                icon: const Icon(PhosphorIconsLight.trash, size: 18, color: MarksColores.error),
                label: const Text('Quitar', style: TextStyle(color: MarksColores.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón redondo para sumar o restar piezas.
class _BotonCantidad extends StatelessWidget {
  final IconData icono;
  final VoidCallback? alTocar;

  const _BotonCantidad({required this.icono, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: alTocar == null ? MarksColores.borde : MarksColores.verde.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: alTocar,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icono,
            size: 18,
            color: alTocar == null ? MarksColores.textoSuave : MarksColores.verdeOscuro,
          ),
        ),
      ),
    );
  }
}

/// Etiqueta pequeña de color suave.
class _Chip extends StatelessWidget {
  final String texto;
  final Color color;

  const _Chip({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

/// Resumen con subtotal, ahorro, total y botón de pago.
class _Resumen extends StatelessWidget {
  final CotizacionCarrito? cotizacion;
  final bool cotizando;
  final String? error;
  final VoidCallback alReintentar;
  final VoidCallback alPagar;

  const _Resumen({
    required this.cotizacion,
    required this.cotizando,
    required this.error,
    required this.alReintentar,
    required this.alPagar,
  });

  @override
  Widget build(BuildContext context) {
    final c = cotizacion;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: MarksColores.blanco,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Row(
              children: [
                const Icon(PhosphorIconsLight.wifiSlash, size: 18, color: MarksColores.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(error!, style: const TextStyle(fontSize: 13, color: MarksColores.error)),
                ),
                TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (c != null) ...[
            _FilaResumen(texto: 'Subtotal (${c.articulos} artículos)', valor: Formato.precio(c.subtotal)),
            if (c.ahorro > 0)
              _FilaResumen(
                texto: 'Ahorraste',
                valor: '-${Formato.precio(c.ahorro)}',
                color: MarksColores.verdeOscuro,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: MarksColores.borde),
            ),
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MarksColores.azul),
                ),
                const Spacer(),
                Text(
                  Formato.precio(c.total),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: MarksColores.verdeOscuro,
                  ),
                ),
              ],
            ),
            if (c.lineasConError > 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Quita los productos marcados en rojo para continuar.',
                  style: TextStyle(fontSize: 13, color: MarksColores.error),
                ),
              ),
            const SizedBox(height: 14),
          ],
          BotonPrincipal(
            texto: cotizando && c == null ? 'Calculando...' : 'Continuar al pago',
            icono: PhosphorIconsLight.creditCard,
            onPressed: (c != null && c.sePuedePagar && !cotizando) ? alPagar : null,
          ),
        ],
      ),
    );
  }
}

class _FilaResumen extends StatelessWidget {
  final String texto;
  final String valor;
  final Color? color;

  const _FilaResumen({required this.texto, required this.valor, this.color});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(fontSize: 14, color: color ?? MarksColores.textoSuave);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(texto, style: estilo),
          const Spacer(),
          Text(valor, style: estilo.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Se muestra cuando no hay productos.
class _CarritoVacio extends StatelessWidget {
  final VoidCallback alEscanear;

  const _CarritoVacio({required this.alEscanear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const IconoCirculo(
            icono: PhosphorIconsLight.shoppingCartSimple,
            color: MarksColores.verde,
            tamano: 80,
          ),
          const SizedBox(height: 18),
          const Text(
            'Tu carrito está vacío',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: MarksColores.azul),
          ),
          const SizedBox(height: 6),
          const Text(
            'Escanea el código de barras de tus productos para agregarlos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
          ),
          const SizedBox(height: 22),
          BotonPrincipal(
            texto: 'Escanear productos',
            icono: PhosphorIconsLight.scan,
            onPressed: alEscanear,
          ),
        ],
      ),
    );
  }
}