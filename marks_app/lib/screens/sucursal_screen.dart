import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/sucursal.dart';
import '../services/api_service.dart';
import '../services/carrito_service.dart';
import '../services/sucursal_service.dart';
import '../theme/colores.dart';
import '../widgets/soft_ui.dart';

/// Lista de sucursales para elegir dónde se va a comprar.
/// Al confirmar, guarda la elección y devuelve la sucursal elegida.
/// Si el carrito tiene productos de otra sucursal, avisa que se vaciará,
/// porque los precios, ofertas y existencias cambian de una tienda a otra.
class SucursalScreen extends StatefulWidget {
  final Sucursal? actual;

  const SucursalScreen({super.key, this.actual});

  @override
  State<SucursalScreen> createState() => _SucursalScreenState();
}

class _SucursalScreenState extends State<SucursalScreen> {
  late Future<List<Sucursal>> _sucursales;
  Sucursal? _elegida;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _elegida = widget.actual;
    _sucursales = SucursalService.obtenerSucursales();
  }

  void _reintentar() {
    setState(() => _sucursales = SucursalService.obtenerSucursales());
  }

  Future<void> _confirmar() async {
    final elegida = _elegida;
    if (elegida == null || _guardando) return;

    // Carrito con productos de otra sucursal: se pregunta antes de cambiar
    final carrito = CarritoService.instancia;
    await carrito.cargar();
    if (!mounted) return;
    if (!carrito.vacio && carrito.sucursalId != elegida.id) {
      final aceptar = await _confirmarVaciarCarrito(carrito.articulos);
      if (!aceptar || !mounted) return;
      await carrito.vaciar();
      if (!mounted) return;
    }

    setState(() => _guardando = true);
    await SucursalService.guardarSeleccion(elegida);
    if (!mounted) return;
    Navigator.of(context).pop(elegida);
  }

  /// Pregunta si se vacía el carrito. Devuelve true si el cliente acepta.
  Future<bool> _confirmarVaciarCarrito(int articulos) async {
    final respuesta = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Cambiar de sucursal?'),
        content: Text(
          'Tienes $articulos ${articulos == 1 ? 'artículo' : 'artículos'} en tu carrito. '
          'Se vaciará porque los precios, ofertas y existencias cambian en cada tienda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Vaciar y cambiar', style: TextStyle(color: MarksColores.error)),
          ),
        ],
      ),
    );
    return respuesta == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EncabezadoMarks(
            subtitulo: 'Elige tu sucursal',
            tamanoLogo: 32,
            onRegresar: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: FutureBuilder<List<Sucursal>>(
                  future: _sucursales,
                  builder: (context, estado) {
                    // Cargando
                    if (estado.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Error
                    if (estado.hasError) {
                      final error = estado.error;
                      return ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          TarjetaError(
                            mensaje: error is ApiException
                                ? error.mensaje
                                : 'No se pudieron cargar las sucursales.',
                          ),
                          const SizedBox(height: 20),
                          BotonPrincipal(
                            texto: 'Reintentar',
                            icono: PhosphorIconsLight.arrowClockwise,
                            onPressed: _reintentar,
                          ),
                        ],
                      );
                    }

                    final sucursales = estado.data ?? const <Sucursal>[];

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      children: [
                        const Text(
                          '¿Dónde vas a comprar hoy?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: MarksColores.azul,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Los precios, ofertas y existencias dependen de la tienda.',
                          style: TextStyle(fontSize: 14, color: MarksColores.textoSuave),
                        ),
                        const SizedBox(height: 22),

                        if (sucursales.isEmpty)
                          const TarjetaSuave(
                            child: Text(
                              'Por ahora no hay sucursales disponibles.',
                              style: TextStyle(color: MarksColores.textoSuave),
                            ),
                          ),

                        for (final s in sucursales) ...[
                          _TarjetaSucursal(
                            sucursal: s,
                            seleccionada: _elegida?.id == s.id,
                            alTocar: _guardando ? null : () => setState(() => _elegida = s),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // Botón fijo abajo
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: BotonPrincipal(
                    texto: 'Comprar aquí',
                    icono: PhosphorIconsLight.shoppingCart,
                    cargando: _guardando,
                    onPressed: _elegida == null ? null : _confirmar,
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

/// Tarjeta de una sucursal; con borde verde y palomita si está elegida.
class _TarjetaSucursal extends StatelessWidget {
  final Sucursal sucursal;
  final bool seleccionada;
  final VoidCallback? alTocar;

  const _TarjetaSucursal({
    required this.sucursal,
    required this.seleccionada,
    this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: MarksColores.blanco,
        borderRadius: BorderRadius.circular(22),
        boxShadow: SombrasMarks.suave,
        border: Border.all(
          color: seleccionada ? MarksColores.verde : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconoCirculo(
                  icono: PhosphorIconsLight.storefront,
                  color: seleccionada ? MarksColores.verde : MarksColores.azul,
                  tamano: 50,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sucursal.nombre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.azul,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              PhosphorIconsLight.mapPin,
                              size: 15,
                              color: MarksColores.textoSuave,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              sucursal.ubicacion,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: MarksColores.textoSuave,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: seleccionada
                      ? const Icon(
                          PhosphorIconsFill.checkCircle,
                          key: ValueKey('si'),
                          color: MarksColores.verde,
                          size: 26,
                        )
                      : const Icon(
                          PhosphorIconsLight.circle,
                          key: ValueKey('no'),
                          color: MarksColores.borde,
                          size: 26,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}