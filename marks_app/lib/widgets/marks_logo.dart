import 'package:flutter/material.dart';

import '../theme/colores.dart';

/// Logo de MARK'S: la letra A se reemplaza por una palomita, como en los mockups.
/// FittedBox lo hace más pequeño si no cabe, así nunca se sale de la pantalla.
class MarksLogo extends StatelessWidget {
  final double tamano;
  final Color color;

  const MarksLogo({super.key, this.tamano = 40, this.color = MarksColores.verde});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: tamano,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      color: color,
      letterSpacing: 0,
      height: 1,
    );

    // Espacio negativo para juntar "K", apóstrofo y "S"
    final juntar = TextStyle(letterSpacing: -tamano * 0.07);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('M', style: estilo),
            Icon(
              Icons.check_rounded,
              size: tamano * 1.05,
              color: MarksColores.verdeOscuro,
            ),
            Text.rich(
              TextSpan(
                style: estilo,
                children: [
                  const TextSpan(text: 'R'),
                  TextSpan(text: 'K', style: juntar),
                  TextSpan(text: '\u2019', style: juntar), // apóstrofo tipográfico
                  const TextSpan(text: 'S'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}