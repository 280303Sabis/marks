import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/producto.dart';
import '../models/sucursal.dart';
import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../services/producto_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/hoja_producto.dart';
import '../widgets/soft_ui.dart';
import 'carrito_screen.dart';

/// Escáner de códigos de barras con la cámara del celular.
class EscanerScreen extends StatefulWidget {
  final Sucursal sucursal;

  const EscanerScreen({super.key, required this.sucursal});

  @override
  State<EscanerScreen> createState() => _EscanerScreenState();
}

class _EscanerScreenState extends State<EscanerScreen> {
  static final RegExp _codigoValido = RegExp(r'^[A-Za-z0-9-]{1,20}$');
  static const Duration _esperaMismoCodigo = Duration(seconds: 3);

  final MobileScannerController _camara = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
    ],
  );

  bool _ocupado = false;          // buscando o mostrando un producto
  String? _ultimoCodigo;          // para no repetir el mismo código
  DateTime _ultimaVez = DateTime(2000);

  @override
  void initState() {
    super.initState();
    CarritoService.instancia.cargar(); // lee el carrito guardado en el celular
  }

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Lectura de códigos
  // ---------------------------------------------------------------
  void _alDetectar(BarcodeCapture captura) {
    if (_ocupado || captura.barcodes.isEmpty) return;
    final codigo = captura.barcodes.first.rawValue?.trim();
    if (codigo == null || codigo.isEmpty) return;

    // El mismo código justo después de cerrar la hoja se ignora
    final reciente = DateTime.now().difference(_ultimaVez) < _esperaMismoCodigo;
    if (codigo == _ultimoCodigo && reciente) return;

    _buscar(codigo);
  }

  Future<void> _buscar(String codigo) async {
    setState(() => _ocupado = true);
    HapticFeedback.mediumImpact(); // vibración corta: "lo leí"

    try {
      final producto = await ProductoService.escanear(codigo, widget.sucursal.id);
      if (!mounted) return;

      final elegido = await mostrarHojaProducto(
        context,
        producto,
        sucursalId: widget.sucursal.id,
      );
      if (elegido != null && mounted) {
        await _agregar(elegido, codigo);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _mensaje(e.mensaje, error: true);
    } finally {
      _ultimoCodigo = codigo;
      _ultimaVez = DateTime.now();
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Agrega al carrito el producto que el cliente eligió en la hoja.
  Future<void> _agregar(Producto producto, String codigoLeido) async {
    final resultado = await CarritoService.instancia.agregar(
      producto,
      codigoLeido: codigoLeido,
      sucursalId: widget.sucursal.id,
    );
    if (!mounted) return;

    // Granel: se muestra el peso y el total que calculó la API
    final nombre = producto.tienePeso
        ? '${producto.nombre} (${producto.pesoKg!.toStringAsFixed(3)} kg, '
            '${Formato.precio(producto.importe!)})'
        : producto.nombre;

    switch (resultado) {
      case ResultadoAgregar.agregado:
        _mensaje('$nombre se agregó a tu carrito');
      case ResultadoAgregar.sumado:
        _mensaje('Sumaste otro: $nombre');
      case ResultadoAgregar.limitePiezas:
        _mensaje('Máximo ${CarritoService.maxPiezas} piezas del mismo producto', error: true);
      case ResultadoAgregar.etiquetaRepetida:
        _mensaje('Esta etiqueta de báscula ya está en tu carrito', error: true);
      case ResultadoAgregar.carritoLleno:
        _mensaje('Tu carrito llegó al máximo de ${CarritoService.maxLineas} productos', error: true);
      case ResultadoAgregar.otraSucursal:
        _mensaje('Tu carrito es de otra sucursal. Vacíalo para comprar aquí', error: true);
    }
  }

  /// Abre el carrito. Mientras está abierto, la cámara no lee códigos.
  Future<void> _abrirCarrito() async {
    setState(() => _ocupado = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarritoScreen(sucursal: widget.sucursal)),
    );
    if (mounted) setState(() => _ocupado = false);
  }

  void _mensaje(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: error ? MarksColores.error : MarksColores.azul,
      ));
  }

  /// Para etiquetas dañadas: el cliente escribe el código.
  Future<void> _escribirCodigo() async {
    final controlador = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Escribe el código'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword, // letras y números, sin autocorrector
          decoration: const InputDecoration(
            hintText: 'Ej. 7501000000012',
            prefixIcon: Icon(PhosphorIconsLight.barcode),
          ),
          onSubmitted: (t) => Navigator.of(contexto).pop(t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(controlador.text),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );

    final limpio = codigo?.trim() ?? '';
    if (limpio.isEmpty || !mounted) return;
    if (!_codigoValido.hasMatch(limpio)) {
      _mensaje('El código solo puede tener letras, números y guiones', error: true);
      return;
    }
    await _buscar(limpio);
  }

  // ---------------------------------------------------------------
  // Pantalla
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Cámara: solo lee los códigos que están DENTRO del recuadro verde
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, medidas) => MobileScanner(
                controller: _camara,
                onDetect: _alDetectar,
                scanWindow: _zonaEscaneo(medidas.biggest),
                errorBuilder: (context, error) => _ErrorCamara(
                  error: error,
                  alEscribir: _escribirCodigo,
                ),
              ),
            ),
          ),

          // 2. Oscurecido con recuadro verde
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _MarcoEscaner())),
          ),

          // 3. Barra superior: regresar, sucursal, linterna
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  _BotonRedondo(
                    icono: PhosphorIconsLight.arrowLeft,
                    descripcion: 'Regresar',
                    alTocar: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsLight.storefront,
                              color: MarksColores.blanco, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.sucursal.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MarksColores.blanco,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _camara,
                    builder: (context, estado, _) {
                      final encendida = estado.torchState == TorchState.on;
                      final disponible = estado.torchState != TorchState.unavailable;
                      return _BotonRedondo(
                        icono: encendida
                            ? PhosphorIconsFill.flashlight
                            : PhosphorIconsLight.flashlight,
                        descripcion: encendida ? 'Apagar linterna' : 'Encender linterna',
                        activo: encendida,
                        alTocar: disponible ? () => _camara.toggleTorch() : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 4. Panel inferior
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  decoration: BoxDecoration(
                    color: MarksColores.fondo,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: _ocupado
                                ? const CircularProgressIndicator(strokeWidth: 2.5)
                                : const Icon(PhosphorIconsLight.scan,
                                    color: MarksColores.verde, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _ocupado
                                  ? 'Buscando producto...'
                                  : 'Apunta al código de barras del producto',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: MarksColores.azul,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      BotonSecundario(
                        texto: 'Escribir el código',
                        icono: PhosphorIconsLight.keyboard,
                        onPressed: _ocupado ? null : _escribirCodigo,
                      ),

                      // Botón del carrito: se actualiza solo cuando cambia
                      ListenableBuilder(
                        listenable: CarritoService.instancia,
                        builder: (context, _) {
                          final carrito = CarritoService.instancia;
                          if (carrito.vacio) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: BotonPrincipal(
                              texto: 'Ver carrito (${carrito.articulos})  '
                                  '${Formato.precio(carrito.totalAproximado)}',
                              icono: PhosphorIconsLight.shoppingCartSimple,
                              onPressed: _ocupado ? null : _abrirCarrito,
                            ),
                          );
                        },
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

/// Recuadro verde donde se leen los códigos.
/// Lo usan el dibujo (_MarcoEscaner) y la cámara (scanWindow),
/// así lo que ve el cliente y lo que lee la cámara siempre coinciden.
Rect _zonaEscaneo(Size size) {
  final ancho = size.width * 0.78;
  final alto = ancho * 0.62;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.42),
    width: ancho,
    height: alto,
  );
}

/// Oscurece la pantalla y deja un recuadro con borde verde en el centro.
class _MarcoEscaner extends CustomPainter {
  const _MarcoEscaner();

  @override
  void paint(Canvas canvas, Size size) {
    final zona = RRect.fromRectAndRadius(_zonaEscaneo(size), const Radius.circular(24));

    final fondo = Path()..addRect(Offset.zero & size);
    final hueco = Path()..addRRect(zona);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fondo, hueco),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      zona,
      Paint()
        ..color = MarksColores.verdeMarca
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Botón redondo semitransparente sobre la cámara.
class _BotonRedondo extends StatelessWidget {
  final IconData icono;
  final String descripcion;
  final VoidCallback? alTocar;
  final bool activo;

  const _BotonRedondo({
    required this.icono,
    required this.descripcion,
    required this.alTocar,
    this.activo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: descripcion,
      child: Material(
        color: activo ? MarksColores.verdeMarca : Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: alTocar,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icono,
              size: 22,
              color: alTocar == null
                  ? MarksColores.blanco.withValues(alpha: 0.4)
                  : MarksColores.blanco,
            ),
          ),
        ),
      ),
    );
  }
}

/// Se muestra si la cámara no se puede usar (por ejemplo, sin permiso).
class _ErrorCamara extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback alEscribir;

  const _ErrorCamara({required this.error, required this.alEscribir});

  @override
  Widget build(BuildContext context) {
    final sinPermiso = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return Container(
      color: MarksColores.fondo,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconoCirculo(
              icono: PhosphorIconsLight.cameraSlash,
              color: MarksColores.error,
              tamano: 72,
            ),
            const SizedBox(height: 18),
            Text(
              sinPermiso ? 'Sin permiso para usar la cámara' : 'No se pudo abrir la cámara',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: MarksColores.azul,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sinPermiso
                  ? 'Para escanear, permite el acceso a la cámara en Ajustes > Aplicaciones > MARK\'S > Permisos.'
                  : 'Cierra la pantalla e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.4, color: MarksColores.textoSuave),
            ),
            const SizedBox(height: 22),
            BotonPrincipal(
              texto: 'Escribir el código',
              icono: PhosphorIconsLight.keyboard,
              onPressed: alEscribir,
            ),
          ],
        ),
      ),
    );
  }
}