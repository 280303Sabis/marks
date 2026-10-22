import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/puntos.dart';
import '../services/api_service.dart';
import '../services/compras_service.dart';
import '../theme/colores.dart';
import '../utils/formato.dart';
import '../widgets/soft_ui.dart';

/// Mis puntos (PASO 12): saldo, reglas del programa y estado de cuenta.
class MisPuntosScreen extends StatefulWidget {
  const MisPuntosScreen({super.key});

  @override
  State<MisPuntosScreen> createState() => _MisPuntosScreenState();
}

class _MisPuntosScreenState extends State<MisPuntosScreen> {
  EstadoCuentaPuntos? _datos;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _datos == null;
      _error = null;
    });
    try {
      final datos = await ComprasService.misPuntos();
      if (!mounted) return;
      setState(() => _datos = datos);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
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
                    'Mis puntos',
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
    final d = _datos;
    if (d == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TarjetaError(mensaje: _error ?? 'No se pudieron cargar tus puntos.'),
          const SizedBox(height: 16),
          BotonSecundario(
            texto: 'Reintentar',
            icono: PhosphorIconsLight.arrowClockwise,
            onPressed: _cargar,
          ),
        ],
      );
    }

    final r = d.reglas;
    final bloques = r.puntosPorBloque > 0 ? d.saldo ~/ r.puntosPorBloque : 0;
    final equivale = bloques * r.valorBloque;

    return RefreshIndicator(
      color: MarksColores.verde,
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // Saldo
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: MarksColores.verde,
              borderRadius: BorderRadius.circular(24),
              boxShadow: SombrasMarks.verde,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tu saldo',
                  style: TextStyle(color: MarksColores.blanco, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${d.saldo} puntos',
                  style: const TextStyle(
                    color: MarksColores.blanco,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  equivale > 0
                      ? 'Puedes usar hasta ${Formato.precio(equivale)} de descuento'
                      : 'Te faltan ${r.puntosPorBloque - d.saldo} puntos para tu primer descuento',
                  style: const TextStyle(color: MarksColores.blanco, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reglas
          TarjetaSuave(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cómo funcionan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.azul,
                  ),
                ),
                const SizedBox(height: 10),
                _Regla(
                  icono: PhosphorIconsLight.shoppingCartSimple,
                  texto: 'Ganas 1 punto por cada \$${r.pesosPorPunto} '
                      'que pagas con tarjeta.',
                ),
                _Regla(
                  icono: PhosphorIconsLight.plant,
                  texto: 'Los productos locales de Nuevo León cuentan '
                      'x${r.multiplicadorLocal}.',
                ),
                _Regla(
                  icono: PhosphorIconsLight.tag,
                  texto: '${r.puntosPorBloque} puntos = \$${r.valorBloque.toStringAsFixed(0)} de '
                      'descuento, hasta el ${r.maxPorcentajeCanje}% de tu compra.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Estado de cuenta
          const Text(
            'Movimientos',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: MarksColores.azul),
          ),
          const SizedBox(height: 10),
          if (d.movimientos.isEmpty)
            const TarjetaSuave(
              padding: EdgeInsets.all(18),
              child: Text(
                'Aún no tienes movimientos. Haz tu primera compra para empezar a sumar.',
                style: TextStyle(fontSize: 13.5, color: MarksColores.textoSuave),
              ),
            )
          else
            TarjetaSuave(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < d.movimientos.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: MarksColores.borde),
                    _FilaMovimiento(movimiento: d.movimientos[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Una regla del programa con su ícono.
class _Regla extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Regla({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: MarksColores.verdeOscuro),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13.5, height: 1.35, color: MarksColores.azul),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un renglón del estado de cuenta.
class _FilaMovimiento extends StatelessWidget {
  final MovimientoPuntos movimiento;

  const _FilaMovimiento({required this.movimiento});

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final color = m.esGanancia ? MarksColores.verdeOscuro : MarksColores.error;
    final titulo = switch (m.tipo) {
      'GANADOS' => 'Puntos ganados',
      'CANJEADOS' => 'Puntos usados',
      _ => 'Ajuste',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          IconoCirculo(
            icono: m.esGanancia ? PhosphorIconsLight.plusCircle : PhosphorIconsLight.minusCircle,
            color: color,
            tamano: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MarksColores.azul,
                  ),
                ),
                Text(
                  m.folio != null
                      ? '${m.folio} · ${Formato.fecha(m.fecha)}'
                      : '${m.nota} · ${Formato.fecha(m.fecha)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                m.esGanancia ? '+${m.puntos}' : '${m.puntos}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
              ),
              Text(
                'Saldo ${m.saldoFinal}',
                style: const TextStyle(fontSize: 11.5, color: MarksColores.textoSuave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}