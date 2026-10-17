import 'package:flutter/material.dart';

import 'colores.dart';

/// Tema general de MARK'S.
/// Estilo limpio: fuente Poppins, esquinas redondeadas y sin bordes duros.
/// Usa únicamente los colores definidos en colores.dart.
ThemeData temaMarks() {
  final esquema = ColorScheme.fromSeed(
    seedColor: MarksColores.verde,
    primary: MarksColores.verde,
    surface: MarksColores.blanco,
    error: MarksColores.error,
  );

  // Campo sin borde visible (la profundidad la da la sombra suave)
  final bordeLimpio = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide.none,
  );

  OutlineInputBorder bordeColor(Color color, double grosor) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color, width: grosor),
      );

  final formaBoton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: MarksColores.fondo,

    // Jerarquía de textos
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: MarksColores.azul),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: MarksColores.azul),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: MarksColores.azul),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: MarksColores.azul),
      bodyLarge: TextStyle(fontSize: 16, color: MarksColores.azul),
      bodyMedium: TextStyle(fontSize: 14, color: MarksColores.azul),
      bodySmall: TextStyle(fontSize: 13, color: MarksColores.textoSuave),
    ),

    // Barra superior plana y limpia
    appBarTheme: const AppBarTheme(
      backgroundColor: MarksColores.fondo,
      foregroundColor: MarksColores.azul,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: MarksColores.azul,
      ),
    ),

    // Campos de texto
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarksColores.blanco,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      hintStyle: const TextStyle(color: MarksColores.textoSuave, fontSize: 15),
      prefixIconColor: MarksColores.textoSuave,
      suffixIconColor: MarksColores.textoSuave,
      errorStyle: const TextStyle(fontSize: 12.5, color: MarksColores.error),
      border: bordeLimpio,
      enabledBorder: bordeLimpio,
      disabledBorder: bordeLimpio,
      focusedBorder: bordeColor(MarksColores.verde, 1.6),
      errorBorder: bordeColor(MarksColores.error, 1.2),
      focusedErrorBorder: bordeColor(MarksColores.error, 1.6),
    ),

    // Botón principal (verde)
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarksColores.verde,
        foregroundColor: MarksColores.blanco,
        disabledBackgroundColor: MarksColores.verde.withValues(alpha: 0.5),
        disabledForegroundColor: MarksColores.blanco,
        elevation: 0,
        minimumSize: const Size.fromHeight(56),
        shape: formaBoton,
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Botón secundario (blanco)
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: MarksColores.blanco,
        foregroundColor: MarksColores.azul,
        side: BorderSide.none,
        minimumSize: const Size.fromHeight(56),
        shape: formaBoton,
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Enlaces
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MarksColores.verdeOscuro,
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Mensajes flotantes
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MarksColores.azul,
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', color: MarksColores.blanco),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    // Ventanas de diálogo
    dialogTheme: DialogThemeData(
      backgroundColor: MarksColores.blanco,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: MarksColores.verde),
    iconTheme: const IconThemeData(color: MarksColores.azul),
  );
}