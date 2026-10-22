import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/opinion.dart';
import '../theme/colores.dart';
import 'soft_ui.dart';

// Piezas visuales de las opiniones (PASO 13): estrellas, resumen,
// tarjeta de una opinión y visor de fotos. Las usan la pantalla
// de opiniones del producto, Opinar y Mis opiniones.

/// Amarillo de las estrellas.
const Color colorEstrella = Color(0xFFF2B01E);

const List<String> _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// "22 oct 2026"
String fechaOpinion(DateTime? f) =>
    f == null ? '' : '${f.day} ${_meses[f.month - 1]} ${f.year}';

/// "12 opiniones" / "1 opinión"
String textoOpiniones(int total) => total == 1 ? '1 opinión' : '$total opiniones';

/// Estrellas para mostrar (no se tocan). Acepta medias: 4.5 dibuja 4 y media.
class Estrellas extends StatelessWidget {
  final double valor; // 0 a 5
  final double tamano;

  const Estrellas({super.key, required this.valor, this.tamano = 16});

  @override
  Widget build(BuildContext context) {
    final redondeado = (valor * 2).round() / 2; // a la media estrella más cercana
    return Semantics(
      label: '${valor.toStringAsFixed(1)} de 5 estrellas',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                redondeado >= i
                    ? PhosphorIconsFill.star
                    : redondeado >= i - 0.5
                        ? PhosphorIconsFill.starHalf
                        : PhosphorIconsLight.star,
                size: tamano,
                color: colorEstrella,
              ),
          ],
        ),
      ),
    );
  }
}

/// Estrellas para elegir de 1 a 5 (pantalla Opinar).
class SelectorEstrellas extends StatelessWidget {
  final int valor; // 0 = todavía no elige
  final ValueChanged<int> alCambiar;
  final double tamano;

  const SelectorEstrellas({
    super.key,
    required this.valor,
    required this.alCambiar,
    this.tamano = 40,
  });

  static const List<String> textos = ['', 'Muy malo', 'Malo', 'Regular', 'Bueno', 'Excelente'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: valor == i,
            label: '$i ${i == 1 ? 'estrella' : 'estrellas'}: ${textos[i]}',
            child: InkResponse(
              onTap: () => alCambiar(i),
              radius: tamano * 0.75,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  valor >= i ? PhosphorIconsFill.star : PhosphorIconsLight.star,
                  size: tamano,
                  color: colorEstrella,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Promedio grande y barritas de 5 a 1 estrellas.
class ResumenEstrellas extends StatelessWidget {
  final ResumenOpiniones resumen;

  const ResumenEstrellas({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            Text(
              resumen.promedio.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                height: 1,
                color: MarksColores.azul,
              ),
            ),
            const SizedBox(height: 6),
            Estrellas(valor: resumen.promedio, tamano: 15),
            const SizedBox(height: 4),
            Text(
              textoOpiniones(resumen.total),
              style: const TextStyle(fontSize: 12, color: MarksColores.textoSuave),
            ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (var e = 5; e >= 1; e--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        child: Text(
                          '$e',
                          style: const TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                        ),
                      ),
                      const Icon(PhosphorIconsFill.star, size: 11, color: colorEstrella),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: resumen.proporcion(e),
                            minHeight: 7,
                            backgroundColor: MarksColores.borde,
                            color: colorEstrella,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${resumen.cuantas(e)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta con una opinión: autor, estrellas, fecha, comentario y fotos.
class TarjetaOpinion extends StatelessWidget {
  final Opinion opinion;

  /// Si no es null, aparece el botón de bandera para reportar.
  final VoidCallback? onReportar;

  /// Muestra el nombre del producto arriba (en "Mis opiniones").
  final bool mostrarProducto;

  /// Botones extra al final (Editar / Borrar en el PASO 13.5).
  final Widget? pie;

  const TarjetaOpinion({
    super.key,
    required this.opinion,
    this.onReportar,
    this.mostrarProducto = false,
    this.pie,
  });

  @override
  Widget build(BuildContext context) {
    final o = opinion;
    return TarjetaSuave(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mostrarProducto && o.producto != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Text(
                o.producto!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MarksColores.azul,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.esMia ? '${o.autor} (tú)' : o.autor,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MarksColores.azul,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Estrellas(valor: o.estrellas.toDouble(), tamano: 14),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            o.editada
                                ? '${fechaOpinion(o.creadaEn)} · editada'
                                : fechaOpinion(o.creadaEn),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: MarksColores.textoSuave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onReportar != null)
                IconButton(
                  tooltip: 'Reportar opinión',
                  icon: const Icon(PhosphorIconsLight.flag, size: 20),
                  color: MarksColores.textoSuave,
                  onPressed: onReportar,
                ),
            ],
          ),
          if (o.oculta)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MarksColores.alerta.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsLight.eyeSlash, size: 16, color: MarksColores.alerta),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Un administrador ocultó esta opinión. Solo tú puedes verla.',
                        style: TextStyle(fontSize: 12.5, height: 1.35, color: MarksColores.alerta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (o.tieneComentario)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Text(
                o.comentario!.trim(),
                style: const TextStyle(fontSize: 14, height: 1.4, color: MarksColores.azul),
              ),
            ),
          if (o.fotos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < o.fotos.length; i++)
                    MiniaturaFoto(
                      foto: o.fotos[i],
                      onTap: () => abrirVisorFotos(context, o.fotos, i),
                    ),
                ],
              ),
            ),
          if (pie != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: pie!,
            ),
        ],
      ),
    );
  }
}

/// Foto pequeña y cuadrada de una opinión.
class MiniaturaFoto extends StatelessWidget {
  final FotoOpinion foto;
  final VoidCallback? onTap;
  final double tamano;

  const MiniaturaFoto({super.key, required this.foto, this.onTap, this.tamano = 76});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: 'Foto de la opinión',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            foto.urlCompleta,
            width: tamano,
            height: tamano,
            fit: BoxFit.cover,
            // Se decodifica pequeña: ahorra memoria en listas largas
            cacheWidth: (tamano * 3).round(),
            loadingBuilder: (context, child, progreso) => progreso == null
                ? child
                : Container(width: tamano, height: tamano, color: MarksColores.borde),
            errorBuilder: (context, error, pila) => Container(
              width: tamano,
              height: tamano,
              color: MarksColores.borde,
              child: const Icon(PhosphorIconsLight.imageBroken, color: MarksColores.textoSuave),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre las fotos en pantalla completa (se puede deslizar y hacer zoom).
Future<void> abrirVisorFotos(BuildContext context, List<FotoOpinion> fotos, int inicial) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _VisorFotos(fotos: fotos, inicial: inicial),
    ),
  );
}

class _VisorFotos extends StatefulWidget {
  final List<FotoOpinion> fotos;
  final int inicial;

  const _VisorFotos({required this.fotos, required this.inicial});

  @override
  State<_VisorFotos> createState() => _VisorFotosState();
}

class _VisorFotosState extends State<_VisorFotos> {
  late final PageController _paginas = PageController(initialPage: widget.inicial);
  late int _actual = widget.inicial;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_actual + 1} de ${widget.fotos.length}'),
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(PhosphorIconsLight.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _paginas,
        itemCount: widget.fotos.length,
        onPageChanged: (i) => setState(() => _actual = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.fotos[i].urlCompleta,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progreso) => progreso == null
                  ? child
                  : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (context, error, pila) => const Icon(
                PhosphorIconsLight.imageBroken,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}