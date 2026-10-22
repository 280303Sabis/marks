import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/opinion.dart';
import '../models/producto.dart';
import '../screens/opiniones_producto_screen.dart';
import '../services/api_service.dart';
import '../services/opiniones_service.dart';
import '../services/producto_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import 'campos_registro.dart' show fechaLarga;
import 'opiniones_ui.dart';
import 'soft_ui.dart';

/// Muestra la hoja con el producto escaneado.
/// Devuelve el producto que el cliente eligió agregar al carrito
/// (si es granel, ya trae el peso y el importe calculados por la API),
/// o null si eligió "Seguir escaneando" o cerró la hoja.
Future<Producto?> mostrarHojaProducto(
  BuildContext context,
  Producto producto, {
  required int sucursalId,
}) {
  return showModalBottomSheet<Producto>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: MarksColores.azul.withValues(alpha: 0.35),
    builder: (_) => _HojaProducto(producto: producto, sucursalId: sucursalId),
  );
}

/// Muestra un peso con 3 decimales (ej. 1.250 kg).
String _kg(double peso) => '${peso.toStringAsFixed(3)} kg';

class _HojaProducto extends StatefulWidget {
  final Producto producto;
  final int sucursalId;

  const _HojaProducto({required this.producto, required this.sucursalId});

  @override
  State<_HojaProducto> createState() => _HojaProductoState();
}

class _HojaProductoState extends State<_HojaProducto> {
  final TextEditingController _peso = TextEditingController();
  String _unidad = 'kg';
  bool _calculando = false;
  String? _errorPeso;

  /// Producto con peso e importe que calculó la API (granel con peso escrito).
  Producto? _conPeso;

  /// Calificación del producto (PASO 13). null mientras carga o si falló.
  OpinionesProducto? _opiniones;

  Producto get p => widget.producto;

  /// Granel que todavía necesita que el cliente escriba el peso.
  bool get _pidePeso => p.esGranel && !p.tienePeso && p.sePuedeVender;

  /// Peso e importe que se muestran (de la báscula o del cálculo).
  double? get _pesoMostrado => p.pesoKg ?? _conPeso?.pesoKg;
  double? get _importeMostrado => p.importe ?? _conPeso?.importe;

  /// Lo que se agregaría al carrito con lo que hay en pantalla (null = todavía no).
  Producto? get _listoParaAgregar {
    if (!p.sePuedeVender) return null;
    if (!p.esGranel) return p;
    if (p.tienePeso) return p;   // vino de la etiqueta de báscula
    return _conPeso;             // peso escrito y total calculado por la API
  }

  String get _textoBoton {
    if (p.caducado) return 'Producto caducado';
    if (p.agotado) return 'Sin existencias';
    if (_pidePeso && _conPeso == null) return 'Calcula el total primero';
    return 'Agregar al carrito';
  }

  String? get _avisoNoVenta {
    if (p.caducado) {
      return 'Este producto ya caducó y no se puede vender. '
          'Déjalo en su lugar y avisa a un empleado para que lo retire.';
    }
    if (p.agotado) {
      return 'No hay existencias registradas en esta sucursal.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _cargarOpiniones();
  }

  @override
  void dispose() {
    _peso.dispose();
    super.dispose();
  }

  /// Trae el promedio de estrellas. Si falla, la hoja se muestra sin calificación.
  Future<void> _cargarOpiniones() async {
    try {
      final datos = await OpinionesService.deProducto(p.id, limite: 1);
      if (mounted) setState(() => _opiniones = datos);
    } on ApiException {
      // Sin calificación: no es necesaria para comprar
    }
  }

  /// Abre la pantalla de opiniones y, al volver, actualiza el promedio.
  Future<void> _verOpiniones() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpinionesProductoScreen(productoId: p.id, nombre: p.nombre),
      ),
    );
    if (mounted) _cargarOpiniones();
  }

  /// Si el cliente cambia el peso o la unidad, el total anterior ya no sirve.
  void _invalidarTotal() {
    if (_conPeso != null || _errorPeso != null) {
      setState(() {
        _conPeso = null;
        _errorPeso = null;
      });
    }
  }

  void _cambiarUnidad(String unidad) {
    if (unidad == _unidad) return;
    setState(() {
      _unidad = unidad;
      _conPeso = null;
      _errorPeso = null;
    });
  }

  /// Pide a la API que valide el peso y calcule el importe.
  Future<void> _calcular() async {
    final texto = _peso.text.trim();
    if (texto.isEmpty) {
      setState(() => _errorPeso = 'Escribe el peso que marcó la báscula');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _calculando = true;
      _errorPeso = null;
    });
    try {
      final resultado = await ProductoService.escanear(
        p.codigoBarras,
        widget.sucursalId,
        peso: texto,
        unidad: _unidad,
      );
      if (!mounted) return;
      setState(() => _conPeso = resultado);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorPeso = e.mensaje);
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = _avisoNoVenta;
    final listo = _listoParaAgregar;
    final peso = _pesoMostrado;
    final importe = _importeMostrado;

    return Padding(
      // Sube la hoja cuando aparece el teclado
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: MarksColores.fondo,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barrita para indicar que se puede deslizar
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: MarksColores.borde,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Ícono, nombre y categoría
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconoCirculo(
                      icono: p.esGranel ? PhosphorIconsLight.scales : PhosphorIconsLight.package,
                      color: p.sePuedeVender ? MarksColores.verde : MarksColores.textoSuave,
                      tamano: 56,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.nombre,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: MarksColores.azul,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.categoria,
                            style: const TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                          ),
                          // Calificación (PASO 13)
                          if (_opiniones != null && _opiniones!.activas)
                            _FilaCalificacion(
                              resumen: _opiniones!.resumen,
                              alTocar: _verOpiniones,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Etiquetas
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (p.caducado)
                      const _Etiqueta(
                        texto: 'Caducado',
                        color: MarksColores.error,
                        icono: PhosphorIconsLight.warningCircle,
                      ),
                    if (p.agotado)
                      const _Etiqueta(
                        texto: 'Agotado',
                        color: MarksColores.error,
                        icono: PhosphorIconsLight.prohibit,
                      ),
                    if (p.esGranel)
                      const _Etiqueta(
                        texto: 'A granel',
                        color: MarksColores.azul,
                        icono: PhosphorIconsLight.scales,
                      ),
                    if (p.tieneOferta)
                      _Etiqueta(
                        texto: 'Oferta -${p.descuento} %',
                        color: MarksColores.alerta,
                        icono: PhosphorIconsLight.tag,
                      ),
                    if (p.esLocal)
                      const _Etiqueta(
                        texto: 'Producto local NL',
                        color: MarksColores.verdeOscuro,
                        icono: PhosphorIconsLight.leaf,
                      ),
                    if (p.caducidadProxima && !p.caducado)
                      const _Etiqueta(
                        texto: 'Por caducar',
                        color: MarksColores.error,
                        icono: PhosphorIconsLight.clock,
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // Precio
                TarjetaSuave(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formato.precio(p.precioFinal),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: p.tieneOferta ? MarksColores.verdeOscuro : MarksColores.azul,
                            ),
                          ),
                          if (p.esGranel)
                            const Padding(
                              padding: EdgeInsets.only(left: 6, bottom: 3),
                              child: Text(
                                'por kg',
                                style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                              ),
                            ),
                          const SizedBox(width: 10),
                          if (p.tieneOferta)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                Formato.precio(p.precio),
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: MarksColores.textoSuave,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Información adicional
                      if (p.esLocal && p.productor != null)
                        _LineaInfo(
                          icono: PhosphorIconsLight.storefront,
                          texto: 'Hecho por ${p.productor}',
                        ),
                      if (p.fechaCaducidad != null)
                        _LineaInfo(
                          icono: PhosphorIconsLight.calendarBlank,
                          texto: p.caducado
                              ? 'Caducó el ${fechaLarga(p.fechaCaducidad!)}'
                              : 'Caduca el ${fechaLarga(p.fechaCaducidad!)}',
                          color: (p.caducado || p.caducidadProxima) ? MarksColores.error : null,
                        ),
                      if (p.esGranel && peso == null)
                        const _LineaInfo(
                          icono: PhosphorIconsLight.scales,
                          texto: 'El total depende del peso del producto.',
                        ),
                      if (peso != null)
                        _LineaInfo(
                          icono: PhosphorIconsLight.scales,
                          texto: p.desdeBascula
                              ? 'Peso de la báscula: ${_kg(peso)}'
                              : 'Peso: ${_kg(peso)}',
                        ),
                      _LineaInfo(
                        icono: PhosphorIconsLight.barcode,
                        texto: p.codigoBarras,
                      ),

                      // Total del granel (calculado por la API)
                      if (importe != null) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: MarksColores.borde),
                        const SizedBox(height: 12),
                        _FilaTotal(importe: importe),
                      ],
                    ],
                  ),
                ),

                // Captura del peso (granel sin etiqueta de báscula)
                if (_pidePeso) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '¿Cuánto pesa?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MarksColores.azul,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pésalo en la báscula de la tienda y escribe lo que marca.',
                    style: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _peso,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            LengthLimitingTextInputFormatter(7),
                          ],
                          onChanged: (_) => _invalidarTotal(),
                          onSubmitted: (_) => _calcular(),
                          decoration: InputDecoration(
                            hintText: _unidad == 'kg' ? 'Ej. 1.25' : 'Ej. 850',
                            prefixIcon: const Icon(PhosphorIconsLight.scales),
                            errorText: _errorPeso,
                            errorMaxLines: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SelectorUnidad(unidad: _unidad, alCambiar: _cambiarUnidad),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BotonSecundario(
                    texto: _calculando ? 'Calculando...' : 'Calcular total',
                    icono: PhosphorIconsLight.calculator,
                    onPressed: _calculando ? null : _calcular,
                  ),
                ],

                // Aviso cuando no se puede vender
                if (aviso != null) ...[
                  const SizedBox(height: 14),
                  _AvisoNoVenta(texto: aviso),
                ],
                const SizedBox(height: 22),

                // Botones
                BotonPrincipal(
                  texto: _textoBoton,
                  icono: PhosphorIconsLight.shoppingCartSimple,
                  onPressed: listo != null ? () => Navigator.of(context).pop(listo) : null,
                ),
                const SizedBox(height: 12),
                BotonSecundario(
                  texto: 'Seguir escaneando',
                  icono: PhosphorIconsLight.scan,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta de color suave (Oferta, Local, Agotado, Caducado...).
class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData icono;

  const _Etiqueta({required this.texto, required this.color, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Renglón pequeño con ícono y texto dentro de la tarjeta de precio.
class _LineaInfo extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color? color;

  const _LineaInfo({required this.icono, required this.texto, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? MarksColores.textoSuave;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icono, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 13, color: c))),
        ],
      ),
    );
  }
}

/// Renglón "Total  $68.63" para el granel.
class _FilaTotal extends StatelessWidget {
  final double importe;

  const _FilaTotal({required this.importe});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Total',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MarksColores.azul),
        ),
        const Spacer(),
        Text(
          Formato.precio(importe),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: MarksColores.verdeOscuro,
          ),
        ),
      ],
    );
  }
}

/// Selector de unidad: kg o g.
class _SelectorUnidad extends StatelessWidget {
  final String unidad;
  final ValueChanged<String> alCambiar;

  const _SelectorUnidad({required this.unidad, required this.alCambiar});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MarksColores.blanco,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opcion in const ['kg', 'g'])
            GestureDetector(
              onTap: () => alCambiar(opcion),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: unidad == opcion ? MarksColores.verde : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  opcion,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: unidad == opcion ? MarksColores.blanco : MarksColores.azul,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Recuadro rojo suave que explica por qué no se puede agregar el producto.
class _AvisoNoVenta extends StatelessWidget {
  final String texto;

  const _AvisoNoVenta({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MarksColores.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(PhosphorIconsLight.info, size: 18, color: MarksColores.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13, height: 1.4, color: MarksColores.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// "★★★★½ 4.5 (12 opiniones) >" debajo del nombre. Al tocarla abre las opiniones.
class _FilaCalificacion extends StatelessWidget {
  final ResumenOpiniones resumen;
  final VoidCallback alTocar;

  const _FilaCalificacion({required this.resumen, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Estrellas(valor: resumen.promedio, tamano: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  resumen.vacio
                      ? 'Sin opiniones todavía'
                      : '${resumen.promedio.toStringAsFixed(1)}  (${textoOpiniones(resumen.total)})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: resumen.vacio ? FontWeight.w400 : FontWeight.w600,
                    color: resumen.vacio ? MarksColores.textoSuave : MarksColores.azul,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(PhosphorIconsLight.caretRight, size: 14, color: MarksColores.textoSuave),
            ],
          ),
        ),
      ),
    );
  }
}