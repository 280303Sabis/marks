import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/sucursal.dart';
import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/carrito_service.dart';
import '../services/compras_service.dart';
import '../services/opiniones_service.dart';
import '../services/sucursal_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/soft_ui.dart';
import 'aviso_privacidad_screen.dart';
import 'bienvenida_screen.dart';
import 'carrito_screen.dart';
import 'escaner_screen.dart';
import 'mi_perfil_screen.dart';
import 'mis_compras_screen.dart';
import 'mis_opiniones_screen.dart';
import 'mis_puntos_screen.dart';
import 'sucursal_screen.dart';
import 'ticket_screen.dart';

/// Pantalla de inicio del cliente (tablero).
/// Solo se llega aquí con el correo ya confirmado.
class InicioScreen extends StatefulWidget {
  final Usuario usuario;

  const InicioScreen({super.key, required this.usuario});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  late Usuario _usuario;
  Sucursal? _sucursal;
  bool _cargandoSucursal = true;
  List<String> _porSalir = const []; // compras pagadas que el guardia aún no valida (PASO 12)
  int _porCalificar = 0; // productos comprados sin opinión (PASO 13)
  bool _pidiendoAviso = false; // ya se está mostrando el aviso nuevo (PASO 14)

  @override
  void initState() {
    super.initState();
    _usuario = widget.usuario;
    _cargarSucursal();
    CarritoService.instancia.cargar(); // para mostrar el carrito guardado
    CarritoService.instancia.addListener(_alCambiarCarrito); // puntos nuevos al pagar
    _cargarPorSalir();
    _cargarPorCalificar();
    // PASO 14: en cuanto se dibuje el Inicio, revisa si falta aceptar el aviso nuevo
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarAviso());
  }

  @override
  void dispose() {
    CarritoService.instancia.removeListener(_alCambiarCarrito);
    super.dispose();
  }

  /// Después de pagar, el carrito guarda el saldo nuevo de puntos (PASO 11)
  /// y queda una compra por salir (PASO 12).
  void _alCambiarCarrito() {
    final carrito = CarritoService.instancia;
    final saldo = carrito.puntosSaldo;
    if (!mounted || saldo == null) return; // todavía no ha pagado en esta sesión
    if (saldo != _usuario.puntos) {
      setState(() => _usuario = _usuario.copiarCon(puntos: saldo));
    }
    if (carrito.vacio) _cargarPorSalir();
  }

  /// Revisa si hay compras pagadas que todavía no pasan por la salida.
  Future<void> _cargarPorSalir() async {
    try {
      final lista = await ComprasService.listar();
      if (!mounted) return;
      setState(() => _porSalir = lista.porSalir);
    } catch (_) {
      // Sin conexión: el aviso simplemente no se muestra
    }
  }

  /// Cuántos productos comprados faltan por calificar (PASO 13).
  Future<void> _cargarPorCalificar() async {
    try {
      final mias = await OpinionesService.mias();
      if (!mounted) return;
      setState(() => _porCalificar = mias.pendientes.length);
    } catch (_) {
      // Sin conexión: la tarjeta dice el texto normal
    }
  }

  Future<void> _cargarSucursal() async {
    final guardada = await SucursalService.leerSeleccion();
    if (!mounted) return;
    setState(() {
      _sucursal = guardada;
      _cargandoSucursal = false;
    });
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

   /// Mi perfil (PASO 14). Al regresar se recarga el usuario (pudo cambiar su nombre).
  Future<void> _abrirMiPerfil() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MiPerfilScreen(usuario: _usuario)),
    );
    if (mounted) _recargarUsuario();
  }

  /// Vuelve a leer los datos del usuario desde la API.
  Future<void> _recargarUsuario() async {
    try {
      final actualizado = await AuthService.usuarioActual();
      if (!mounted || actualizado == null) return;
      setState(() => _usuario = actualizado);
      _revisarAviso(); // por si el aviso cambió con la app abierta
    } catch (_) {
      // Sin conexión: se quedan los datos que ya tenía
    }
    await _cargarPorSalir();
    await _cargarPorCalificar();
  }

  /// Mis compras (PASO 12).
  Future<void> _abrirMisCompras() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisComprasScreen()),
    );
    if (mounted) {
      _cargarPorSalir();
      _cargarPorCalificar(); // pudo calificar desde un ticket
    }
  }

  /// Mis opiniones (PASO 13). Al regresar se actualiza "por calificar".
  Future<void> _abrirMisOpiniones() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisOpinionesScreen()),
    );
    if (mounted) _cargarPorCalificar();
  }

  /// Mis puntos (PASO 12). Al regresar se actualiza el saldo.
  Future<void> _abrirMisPuntos() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisPuntosScreen()),
    );
    if (mounted) _recargarUsuario();
  }

  /// Abre el QR de la compra que falta pasar por la salida.
  Future<void> _abrirCompraPorSalir() async {
    if (_porSalir.isEmpty) return;
    try {
      final venta = await ComprasService.verCompra(_porSalir.first);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TicketScreen(venta: venta)),
      );
    } on ApiException catch (e) {
      if (mounted) _mensaje(e.mensaje);
    }
    if (mounted) _cargarPorSalir();
  }

  /// Abre "Elige tu sucursal". Devuelve la sucursal elegida (o la actual).
  Future<Sucursal?> _elegirSucursal() async {
    final elegida = await Navigator.of(context).push<Sucursal>(
      MaterialPageRoute(builder: (_) => SucursalScreen(actual: _sucursal)),
    );
    if (elegida != null && mounted) {
      setState(() => _sucursal = elegida);
      _mensaje('Vas a comprar en ${elegida.nombre}');
    }
    return _sucursal;
  }

  Future<void> _escanear() async {
    // Primero se necesita saber en qué tienda está el cliente
    final sucursal = _sucursal ?? await _elegirSucursal();
    if (sucursal == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EscanerScreen(sucursal: sucursal)));
  }

  /// Abre el carrito. Si el cliente toca "Escanear productos" (carrito vacío),
  /// se abre el escáner.
  Future<void> _abrirCarrito() async {
    final sucursal = _sucursal ?? await _elegirSucursal();
    if (sucursal == null || !mounted) return;
    final irAEscanear = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CarritoScreen(sucursal: sucursal)),
    );
    if (irAEscanear == true && mounted) await _escanear();
  }

  Future<void> _cerrarSesion() async {
    // Si hay productos en el carrito, se avisa que también se vaciará
    final carrito = CarritoService.instancia;
    await carrito.cargar();
    if (!mounted) return;
    final avisoCarrito = carrito.vacio
        ? ''
        : ' Tu carrito (${carrito.articulos} '
            '${carrito.articulos == 1 ? 'artículo' : 'artículos'}) también se vaciará.';

    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Cerrar sesión?',
      mensaje: 'Para volver a entrar tendrás que escribir tu correo y tu contraseña.$avisoCarrito',
      textoConfirmar: 'Cerrar sesión',
      icono: PhosphorIconsLight.signOut,
      peligro: true,
    );
        if (!confirmar) return;
    await _terminarSesion();
  }

  /// Borra el carrito y la sesión del celular y regresa a la bienvenida.
  Future<void> _terminarSesion() async {
    // El carrito se borra del celular para que la siguiente persona no lo vea
    await CarritoService.instancia.vaciar();
    await AuthService.cerrarSesion();
    if (!mounted) return;

    // Regresa a la bienvenida y borra el historial de pantallas
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BienvenidaScreen()),
      (_) => false,
    );
  }

  /// PASO 14: si el Aviso de Privacidad cambió desde que lo aceptó,
  /// se le pide aceptarlo antes de seguir. Si no lo acepta, se cierra la sesión.
  Future<void> _revisarAviso() async {
    if (!mounted || _pidiendoAviso || !_usuario.avisoPendiente) return;
    _pidiendoAviso = true;
    final acepto = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AvisoPrivacidadScreen(paraAceptar: true),
      ),
    );
    _pidiendoAviso = false;
    if (!mounted) return;
    if (acepto == true) {
      setState(() => _usuario = _usuario.copiarCon(avisoPendiente: false));
      _mensaje('Gracias. Aceptaste el Aviso de Privacidad');
    } else {
      await _terminarSesion();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              color: MarksColores.verde,
              onRefresh: _recargarUsuario, // deslizar hacia abajo para actualizar
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                children: [
                  // Saludo, carrito y cerrar sesión
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, ${_usuario.nombre}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: MarksColores.azul,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _usuario.correo,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: MarksColores.textoSuave,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _BotonCarrito(alTocar: _abrirCarrito),
                      const SizedBox(width: 10),
                      Tooltip(
                        message: 'Cerrar sesión',
                        child: TarjetaSuave(
                          radio: 18,
                          padding: const EdgeInsets.all(13),
                          onTap: _cerrarSesion,
                          child: const Icon(
                            PhosphorIconsLight.signOut,
                            size: 22,
                            color: MarksColores.azul,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Tu sucursal
                  _TarjetaSucursalActual(
                    sucursal: _sucursal,
                    cargando: _cargandoSucursal,
                    alTocar: _elegirSucursal,
                  ),
                  const SizedBox(height: 16),

                  // Carrito pendiente (solo si tiene productos)
                  _TarjetaCarrito(alTocar: _abrirCarrito),

                  // Compra pagada que falta pasar por la salida (PASO 12)
                  if (_porSalir.isNotEmpty)
                    _AvisoPorSalir(
                      cantidad: _porSalir.length,
                      alTocar: _abrirCompraPorSalir,
                    ),

                  // Tarjeta de puntos destacada (al tocarla abre Mis puntos)
                  _TarjetaPuntos(puntos: _usuario.puntos, alTocar: _abrirMisPuntos),
                  const SizedBox(height: 24),

                  // Accesos rápidos
                  const Text(
                    'Accesos rápidos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: MarksColores.azul,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: 140, // altura fija de cada tarjeta
                    ),
                    children: [
                      _Acceso(
                        icono: PhosphorIconsLight.scan,
                        color: MarksColores.verde,
                        titulo: 'Escanear',
                        texto: 'Agrega productos',
                        onTap: _escanear,
                      ),
                      _Acceso(
                        icono: PhosphorIconsLight.receipt,
                        color: MarksColores.azul,
                        titulo: 'Mis compras',
                        texto: 'Historial y tickets',
                        onTap: _abrirMisCompras,
                      ),
                      _Acceso(
                        icono: PhosphorIconsLight.chatText,
                        color: MarksColores.alerta,
                        titulo: 'Mis opiniones',
                        texto: _porCalificar > 0
                            ? '$_porCalificar por calificar'
                            : 'Califica tus productos',
                        destacado: _porCalificar > 0,
                        onTap: _abrirMisOpiniones,
                      ),
                      _Acceso(
                        icono: PhosphorIconsLight.gift,
                        color: MarksColores.verde,
                        titulo: 'Mis puntos',
                        texto: 'Saldo y movimientos',
                        onTap: _abrirMisPuntos,
                      ),
                      _Acceso(
                        icono: PhosphorIconsLight.mapPin,
                        color: MarksColores.alerta,
                        titulo: 'Sucursal',
                        texto: _sucursal == null ? 'Elige tu tienda' : 'Cambiar tienda',
                        onTap: _elegirSucursal,
                      ),
                      _Acceso(
                        icono: PhosphorIconsLight.userCircle,
                        color: MarksColores.verdeOscuro,
                        titulo: 'Mi perfil',
                        texto: 'Cuenta y privacidad',
                        onTap: _abrirMiPerfil,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón del carrito con la cantidad de artículos (como en las tiendas en línea).
/// Se actualiza solo cuando cambia el carrito.
class _BotonCarrito extends StatelessWidget {
  final VoidCallback alTocar;

  const _BotonCarrito({required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CarritoService.instancia,
      builder: (context, _) {
        final articulos = CarritoService.instancia.articulos;
        return Tooltip(
          message: 'Mi carrito',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TarjetaSuave(
                radio: 18,
                padding: const EdgeInsets.all(13),
                onTap: alTocar,
                child: const Icon(
                  PhosphorIconsLight.shoppingCartSimple,
                  size: 22,
                  color: MarksColores.azul,
                ),
              ),
              if (articulos > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: IgnorePointer(
                    child: Container(
                      height: 22,
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MarksColores.verde,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: MarksColores.fondo, width: 2),
                      ),
                      child: Text(
                        articulos > 99 ? '99+' : '$articulos',
                        style: const TextStyle(
                          color: MarksColores.blanco,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tarjeta "Continúa tu compra": solo aparece si el carrito tiene productos.
class _TarjetaCarrito extends StatelessWidget {
  final VoidCallback alTocar;

  const _TarjetaCarrito({required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CarritoService.instancia,
      builder: (context, _) {
        final carrito = CarritoService.instancia;
        if (carrito.vacio) return const SizedBox.shrink();
        final n = carrito.articulos;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TarjetaSuave(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            onTap: alTocar,
            child: Row(
              children: [
                const IconoCirculo(
                  icono: PhosphorIconsLight.shoppingCartSimple,
                  color: MarksColores.verde,
                  tamano: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Continúa tu compra',
                        style: TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$n ${n == 1 ? 'artículo' : 'artículos'}  ·  '
                        '${Formato.precio(carrito.totalAproximado)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.azul,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Ver carrito',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.verdeOscuro,
                  ),
                ),
                const Icon(PhosphorIconsLight.caretRight, size: 18, color: MarksColores.verdeOscuro),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta "Tu sucursal": muestra la tienda elegida o invita a elegir una.
class _TarjetaSucursalActual extends StatelessWidget {
  final Sucursal? sucursal;
  final bool cargando;
  final VoidCallback alTocar;

  const _TarjetaSucursalActual({
    required this.sucursal,
    required this.cargando,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final tiene = sucursal != null;

    return TarjetaSuave(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: cargando ? null : alTocar,
      child: Row(
        children: [
          IconoCirculo(
            icono: PhosphorIconsLight.storefront,
            color: tiene ? MarksColores.verde : MarksColores.alerta,
            tamano: 46,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tiene ? 'Tu sucursal' : 'Sin sucursal',
                  style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                ),
                const SizedBox(height: 2),
                Text(
                  cargando
                      ? 'Cargando...'
                      : (tiene ? sucursal!.nombre : 'Elige dónde vas a comprar'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.azul,
                  ),
                ),
              ],
            ),
          ),
          Text(
            tiene ? 'Cambiar' : 'Elegir',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: MarksColores.verdeOscuro,
            ),
          ),
          const Icon(PhosphorIconsLight.caretRight, size: 18, color: MarksColores.verdeOscuro),
        ],
      ),
    );
  }
}

/// Aviso naranja: hay compras pagadas que todavía no pasan por la salida.
class _AvisoPorSalir extends StatelessWidget {
  final int cantidad;
  final VoidCallback alTocar;

  const _AvisoPorSalir({required this.cantidad, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: MarksColores.alerta.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: alTocar,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: MarksColores.alerta.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const IconoCirculo(
                  icono: PhosphorIconsLight.qrCode,
                  color: MarksColores.alerta,
                  tamano: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cantidad == 1
                            ? 'Tienes una compra por salir'
                            : 'Tienes $cantidad compras por salir',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MarksColores.azul,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Toca para mostrar tu QR al guardia',
                        style: TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
                      ),
                    ],
                  ),
                ),
                const Icon(PhosphorIconsLight.caretRight, size: 18, color: MarksColores.azul),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta verde destacada con el saldo de puntos. Al tocarla abre Mis puntos.
class _TarjetaPuntos extends StatelessWidget {
  final int puntos;
  final VoidCallback alTocar;

  const _TarjetaPuntos({required this.puntos, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: MarksColores.verde,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SombrasMarks.verde,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus puntos',
                    style: TextStyle(
                      color: MarksColores.blanco,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$puntos',
                    style: const TextStyle(
                      color: MarksColores.blanco,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '100 puntos = \$10 de descuento · Ver movimientos',
                    style: TextStyle(color: MarksColores.blanco, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: MarksColores.blanco.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsLight.star,
                color: MarksColores.blanco,
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de acceso rápido: ícono arriba, título y descripción abajo.
class _Acceso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String texto;
  final VoidCallback onTap;
  final bool destacado; // texto en color (ej. "2 por calificar")

  const _Acceso({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.texto,
    required this.onTap,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return TarjetaSuave(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconoCirculo(icono: icono, color: color, tamano: 44),
          const Spacer(),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: MarksColores.azul,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: destacado ? FontWeight.w600 : FontWeight.w400,
              color: destacado ? MarksColores.alerta : MarksColores.textoSuave,
            ),
          ),
        ],
      ),
    );
  }
}