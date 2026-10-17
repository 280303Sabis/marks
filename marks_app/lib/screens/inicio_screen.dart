import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/sucursal.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/carrito_service.dart';
import '../services/sucursal_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/soft_ui.dart';
import 'bienvenida_screen.dart';
import 'carrito_screen.dart';
import 'escaner_screen.dart';
import 'sucursal_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _usuario = widget.usuario;
    _cargarSucursal();
    CarritoService.instancia.cargar(); // para mostrar el carrito guardado
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

  void _proximamente(String opcion) => _mensaje('$opcion: disponible muy pronto');

  /// Vuelve a leer los datos del usuario desde la API.
  Future<void> _recargarUsuario() async {
    try {
      final actualizado = await AuthService.usuarioActual();
      if (!mounted || actualizado == null) return;
      setState(() => _usuario = actualizado);
    } catch (_) {
      // Sin conexión: se quedan los datos que ya tenía
    }
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

    // El carrito se borra del celular para que la siguiente persona no lo vea
    await carrito.vaciar();
    await AuthService.cerrarSesion();
    if (!mounted) return;

    // Regresa a la bienvenida y borra el historial de pantallas
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BienvenidaScreen()),
      (_) => false,
    );
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

                  // Tarjeta de puntos destacada
                  _TarjetaPuntos(puntos: _usuario.puntos),
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
                        onTap: () => _proximamente('Mis compras'),
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
                        onTap: () => _proximamente('Mi perfil'),
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

/// Tarjeta verde destacada con el saldo de puntos.
class _TarjetaPuntos extends StatelessWidget {
  final int puntos;

  const _TarjetaPuntos({required this.puntos});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  'Acumulas puntos con cada compra',
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

  const _Acceso({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.texto,
    required this.onTap,
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
            style: const TextStyle(fontSize: 12.5, color: MarksColores.textoSuave),
          ),
        ],
      ),
    );
  }
}