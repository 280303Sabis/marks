import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marks_app/screens/bienvenida_screen.dart';
import 'package:marks_app/theme/tema.dart';

void main() {
  testWidgets('La bienvenida muestra los botones de inicio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: temaMarks(), home: const BienvenidaScreen()),
    );

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}