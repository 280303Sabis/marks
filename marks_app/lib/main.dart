import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/arranque_screen.dart';
import 'theme/tema.dart';

void main() {
  runApp(const MarksApp());
}

class MarksApp extends StatelessWidget {
  const MarksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MARK'S",
      debugShowCheckedModeBanner: false, // quita la etiqueta "DEBUG"
      theme: temaMarks(),

      // Español de México (calendario, botones del sistema, etc.)
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX'), Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      home: const ArranqueScreen(),
    );
  }
}