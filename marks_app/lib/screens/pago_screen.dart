import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/carrito.dart';
import '../models/sucursal.dart';
import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../utils/tarjeta.dart';
import '../widgets/soft_ui.dart';
import 'ticket_screen.dart';

/// Pantalla de pago (PASO 10 y 11). El pago es SIMULADO:
/// - La tarjeta se valida aquí, en el celular.
/// - A la API solo se envía la marca y los últimos 4 dígitos.
/// - Nada de la tarjeta se guarda ni se imprime en la consola.
/// - El cliente puede usar sus puntos como descuento (PASO 11).
class PagoScreen extends StatefulWidget {
  final Sucursal sucursal;
  final CotizacionCarrito cotizacion;

  const PagoScreen({super.key, required this.sucursal, required this.cotizacion});

  @override
  State<PagoScreen> createState() => _PagoScreenState();
}

class _PagoScreenState extends State<PagoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _vencimiento = TextEditingController();
  final _cvv = TextEditingController();

  /// Una clave para ESTE intento de pago. Si falla la conexión y el cliente
  /// toca Pagar otra vez, se manda la misma clave y la API no cobra dos veces.
  final String _clavePago = Tarjeta.nuevaClavePago();

  String? _marca;
  bool _pagando = false;
  bool _usarPuntos = false;
  String? _error;

  PuntosCotizacion? get _puntos => widget.cotizacion.puntos;

  /// Lo que se cobrará a la tarjeta (con o sin descuento por puntos).
  double get _totalACobrar => (_usarPuntos && _puntos != null)
      ? _puntos!.totalConPuntos
      : widget.cotizacion.total;

  /// Puntos que ganará con esta compra.
  int get _puntosAGanar {
    final p = _puntos;
    if (p == null) return 0;
    return _usarPuntos ? p.ganariasConPuntos : p.ganarias;
  }

  @override
  void initState() {
    super.initState();
    _numero.addListener(_alCambiarNumero);
  }

  @override
  void dispose() {
    _numero.removeListener(_alCambiarNumero);
    // Se borran los datos de la tarjeta de la memoria
    _numero.clear();
    _vencimiento.clear();
    _cvv.clear();
    _numero.dispose();
    _vencimiento.dispose();
    _cvv.dispose();
    super.dispose();
  }

  void _alCambiarNumero() {
    final marca = Tarjeta.marca(_numero.text);
    if (marca != _marca || _error != null) {
      setState(() {
        _marca = marca;
        _error = null;
      });
    }
  }

  /// Llena una tarjeta Visa de prueba (para la presentación).
  void _usarTarjetaPrueba() {
    _numero.text = '4242 4242 4242 4242';
    _vencimiento.text = '12/30';
    _cvv.text = '123';
    _formulario.currentState?.validate();
  }

  Future<void> _pagar() async {
    if (_pagando) return;
    FocusScope.of(context).unfocus();
    if (!_formulario.currentState!.validate()) return;

    final digitos = Tarjeta.soloDigitos(_numero.text);
    setState(() {
      _pagando = true;
      _error = null;
    });

    try {
      final venta = await CarritoService.instancia.pagar(
        clavePago: _clavePago,
        totalEsperado: _totalACobrar,
        usarPuntos: _usarPuntos,
        marca: _marca!,
        ultimos4: digitos.substring(digitos.length - 4),
      );
      if (!mounted) return;
      // Se quitan Carrito y Pago de la pila: "atrás" desde el ticket lleva a Inicio
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => TicketScreen(venta: venta, recienPagada: true)),
        (ruta) => ruta.isFirst,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.estado == 409) {
        // El carrito o los puntos cambiaron: no se cobró nada
        setState(() => _pagando = false);
        await _avisarYRegresar(e.mensaje);
        return;
      }
      setState(() {
        _error = e.sinConexion
            ? '${e.mensaje} Puedes intentar de nuevo: no se te cobrará dos veces.'
            : e.mensaje;
      });
    } finally {
      if (mounted && _pagando) setState(() => _pagando = false);
    }
  }

  Future<void> _avisarYRegresar(String mensaje) async {
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Revisa tu carrito'),
        content: Text('$mensaje\n\nNo se hizo ningún cobro.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(),
            child: const Text('Ir al carrito'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cotizacion;
    final p = _puntos;

    return PopScope(
      canPop: !_pagando, // no se puede salir mientras se procesa el pago
      child: Scaffold(
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
                      onPressed: _pagando ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pagar',
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
                  ],
                ),
              ),

              Expanded(
                child: Form(
                  key: _formulario,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      // Resumen del total
                      TarjetaSuave(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            const IconoCirculo(icono: PhosphorIconsLight.receipt, tamano: 48),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total a pagar',
                                    style: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                                  ),
                                  Text(
                                    Formato.precio(_totalACobrar),
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: MarksColores.verdeOscuro,
                                    ),
                                  ),
                                  Text(
                                    c.ahorro > 0
                                        ? '${c.articulos} artículos · Ahorras ${Formato.precio(c.ahorro)}'
                                        : '${c.articulos} artículos',
                                    style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                                  ),
                                  if (_usarPuntos && p != null)
                                    Text(
                                      'Antes ${Formato.precio(c.total)} · '
                                      'Puntos -${Formato.precio(p.descuento)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: MarksColores.verdeOscuro,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Puntos (PASO 11)
                      if (p != null) ...[
                        _TarjetaPuntos(
                          puntos: p,
                          usar: _usarPuntos,
                          puntosAGanar: _puntosAGanar,
                          alCambiar: _pagando ? null : (v) => setState(() => _usarPuntos = v),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Aviso de pago simulado
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MarksColores.verde.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(PhosphorIconsLight.shieldCheck,
                                    color: MarksColores.verdeOscuro, size: 22),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Pago simulado del proyecto. Los datos de tu tarjeta no se '
                                    'guardan: solo se registran la marca y los últimos 4 dígitos.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: MarksColores.azul,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _pagando ? null : _usarTarjetaPrueba,
                                child: const Text('Usar tarjeta de prueba'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Número de tarjeta
                      CampoSuave(
                        controller: _numero,
                        hint: 'Número de la tarjeta',
                        icono: PhosphorIconsLight.creditCard,
                        habilitado: !_pagando,
                        tipoTeclado: TextInputType.number,
                        accionTeclado: TextInputAction.next,
                        formateadores: [FormatoNumeroTarjeta()],
                        validador: Tarjeta.validarNumero,
                        sufijo: _marca == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    Tarjeta.nombreMarca(_marca),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: MarksColores.verdeOscuro,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Vencimiento y CVV
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CampoSuave(
                              controller: _vencimiento,
                              hint: 'MM/AA',
                              icono: PhosphorIconsLight.calendarBlank,
                              habilitado: !_pagando,
                              tipoTeclado: TextInputType.number,
                              accionTeclado: TextInputAction.next,
                              formateadores: [FormatoVencimiento()],
                              validador: Tarjeta.validarVencimiento,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CampoSuave(
                              controller: _cvv,
                              hint: 'CVV',
                              icono: PhosphorIconsLight.lockSimple,
                              habilitado: !_pagando,
                              ocultarTexto: true,
                              tipoTeclado: TextInputType.number,
                              accionTeclado: TextInputAction.done,
                              formateadores: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validador: (v) => Tarjeta.validarCvv(v, _marca),
                              alEnviar: (_) => _pagar(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (_error != null) ...[
                        TarjetaError(mensaje: _error!),
                        const SizedBox(height: 20),
                      ],

                      BotonPrincipal(
                        texto: 'Pagar ${Formato.precio(_totalACobrar)}',
                        icono: PhosphorIconsLight.lockSimple,
                        cargando: _pagando,
                        onPressed: _pagar,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de puntos en el pago: interruptor para canjear y puntos que ganará.
class _TarjetaPuntos extends StatelessWidget {
  final PuntosCotizacion puntos;
  final bool usar;
  final int puntosAGanar;
  final ValueChanged<bool>? alCambiar;

  const _TarjetaPuntos({
    required this.puntos,
    required this.usar,
    required this.puntosAGanar,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return TarjetaSuave(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (puntos.puedeCanjear)
            Row(
              children: [
                const IconoCirculo(icono: PhosphorIconsLight.star, tamano: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Usar ${puntos.puntosUsables} puntos',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.azul,
                        ),
                      ),
                      Text(
                        '-${Formato.precio(puntos.descuento)} · Tienes ${puntos.saldo} puntos',
                        style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(value: usar, onChanged: alCambiar),
              ],
            )
          else
            Row(
              children: [
                const IconoCirculo(icono: PhosphorIconsLight.star, tamano: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tienes ${puntos.saldo} puntos. '
                    'Con 100 puntos obtienes \$10 de descuento.',
                    style: const TextStyle(fontSize: 13, height: 1.35, color: MarksColores.azul),
                  ),
                ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: MarksColores.borde),
          ),
          Row(
            children: [
              const Icon(PhosphorIconsLight.plusCircle, size: 18, color: MarksColores.verdeOscuro),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  puntosAGanar > 0
                      ? 'Con esta compra ganas $puntosAGanar puntos'
                      : 'Esta compra no suma puntos (mínimo \$10)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.verdeOscuro,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}