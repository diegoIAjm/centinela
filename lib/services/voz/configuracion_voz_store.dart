import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/configuracion_voz.dart';

class ConfiguracionVozStore {
  static const clave = 'proteccion_voz_v1';
  Future<ConfiguracionVoz> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // UI y servicio usan isolates distintos.
    final texto = prefs.getString(clave);
    if (texto == null) return const ConfiguracionVoz();
    final config = ConfiguracionVoz.fromMap(
      jsonDecode(texto) as Map<String, dynamic>,
    );
    final error = config.error;
    if (error != null) throw FormatException(error);
    return config;
  }

  Future<void> guardar(ConfiguracionVoz config) async {
    if (config.error != null) throw ArgumentError(config.error);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(clave, jsonEncode(config.toMap()))) {
      throw StateError('No se pudo guardar la configuración.');
    }
  }
}
