import 'package:flutter/material.dart';

/// Colores tomados del logo (azul marino y dorado) y colores de estado con
/// contraste suficiente sobre fondo claro.
abstract final class Paleta {
  static const marino = Color(0xFF0C1B3C);
  static const marinoMedio = Color(0xFF243A6B);
  static const dorado = Color(0xFFB8913F);
  static const fondo = Color(0xFFF3F4F7);
  static const superficie = Colors.white;
  static const borde = Color(0xFFD7DBE3);
  static const texto = Color(0xFF1B1F27);
  static const textoSecundario = Color(0xFF555D6D);

  static const exito = Color(0xFF1E6B35);
  static const exitoFondo = Color(0xFFE5F2E9);
  static const aviso = Color(0xFF8A5200);
  static const avisoFondo = Color(0xFFFFF2D9);
  static const peligro = Color(0xFFB3261E);
  static const peligroFondo = Color(0xFFFBE9E7);
  static const info = marinoMedio;
  static const infoFondo = Color(0xFFE8ECF5);
}

ThemeData temaCentinela() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Paleta.marino,
    primary: Paleta.marino,
    onPrimary: Colors.white,
    secondary: Paleta.dorado,
    error: Paleta.peligro,
    surface: Paleta.superficie,
    onSurface: Paleta.texto,
  );
  final redondeo = BorderRadius.circular(10);
  const tamanoBoton = Size(64, 52);
  const textoBoton = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  final base = ThemeData(useMaterial3: true, colorScheme: esquema);

  return base.copyWith(
    scaffoldBackgroundColor: Paleta.fondo,
    textTheme: base.textTheme
        .copyWith(
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.35),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.35),
          bodySmall: const TextStyle(fontSize: 13, height: 1.3),
        )
        .apply(bodyColor: Paleta.texto, displayColor: Paleta.texto),
    appBarTheme: const AppBarTheme(
      backgroundColor: Paleta.marino,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: Paleta.superficie,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Paleta.borde),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Paleta.marino,
        foregroundColor: Colors.white,
        minimumSize: tamanoBoton,
        textStyle: textoBoton,
        shape: RoundedRectangleBorder(borderRadius: redondeo),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Paleta.marino,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: tamanoBoton,
        textStyle: textoBoton,
        shape: RoundedRectangleBorder(borderRadius: redondeo),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Paleta.marino,
        minimumSize: tamanoBoton,
        textStyle: textoBoton,
        side: const BorderSide(color: Paleta.marino, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: redondeo),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Paleta.marino,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Paleta.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: redondeo,
        borderSide: const BorderSide(color: Paleta.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: redondeo,
        borderSide: const BorderSide(color: Paleta.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: redondeo,
        borderSide: const BorderSide(color: Paleta.marino, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: redondeo,
        borderSide: const BorderSide(color: Paleta.peligro),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: redondeo,
        borderSide: const BorderSide(color: Paleta.peligro, width: 2),
      ),
      labelStyle: const TextStyle(color: Paleta.textoSecundario),
      helperStyle: const TextStyle(color: Paleta.textoSecundario),
      helperMaxLines: 2,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Paleta.marino,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Paleta.marino : null,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Paleta.marino,
      thumbColor: Paleta.marino,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Paleta.marino,
    ),
    dividerTheme: const DividerThemeData(color: Paleta.borde, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: redondeo),
      contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Paleta.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: Paleta.marino,
    ),
  );
}
