import 'dart:async';

import 'package:flutter/services.dart';

/// El controlador de horarios no depende de Vosk: se puede sustituir el motor.
abstract class MotorVoz {
  Stream<Map<String, dynamic>> get eventos;
  Future<void> iniciar();
  Future<void> detener();
  Future<void> mantenerServicio(bool mantener);
}

class MotorVozLocal implements MotorVoz {
  static const canal = MethodChannel('centinela_voz');
  final _eventos = StreamController<Map<String, dynamic>>.broadcast();
  MotorVozLocal() {
    canal.setMethodCallHandler((call) async {
      if (call.method == 'evento' && call.arguments is Map) {
        _eventos.add(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }
  @override
  Stream<Map<String, dynamic>> get eventos => _eventos.stream;
  @override
  Future<void> iniciar() => canal.invokeMethod<void>('iniciar');
  @override
  Future<void> detener() => canal.invokeMethod<void>('detener');
  @override
  Future<void> mantenerServicio(bool mantener) =>
      canal.invokeMethod<void>('mantenerServicio', mantener);
  static Future<bool> modeloDisponible() async =>
      await canal.invokeMethod<bool>('modeloDisponible') ?? false;
  static Future<void> descargarModelo() =>
      canal.invokeMethod<void>('descargarModelo');
}
