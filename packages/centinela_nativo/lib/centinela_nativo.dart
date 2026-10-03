import 'package:flutter/services.dart';

class ResultadoSms {
  final int despachados;
  final List<String> fallidos;
  final List<String> sinConfirmar;

  const ResultadoSms(this.despachados, this.fallidos, this.sinConfirmar);

  int get enviados => despachados - fallidos.length;
}

/// Funciona tanto en la UI como en el isolate del servicio en segundo plano.
class CentinelaNativo {
  static const _canal = MethodChannel('centinela_nativo');

  static Future<ResultadoSms> enviarSms(
    List<String> telefonos,
    String mensaje,
  ) async {
    final r = await _canal.invokeMapMethod<String, Object?>('enviarSms', {
      'telefonos': telefonos,
      'mensaje': mensaje,
    });
    return ResultadoSms(
      r?['despachados'] as int? ?? 0,
      List<String>.from(r?['fallidos'] as List? ?? const []),
      List<String>.from(r?['sinConfirmar'] as List? ?? const []),
    );
  }

  static Future<bool> abrirAlarma() async =>
      await _canal.invokeMethod<bool>('abrirAlarma') ?? false;

  static Future<({bool pantallaCompleta, bool superponer})>
  puedeAbrirSobreBloqueo() async {
    final r = await _canal.invokeMapMethod<String, bool>(
      'puedeAbrirSobreBloqueo',
    );
    return (
      pantallaCompleta: r?['pantallaCompleta'] ?? false,
      superponer: r?['superponer'] ?? false,
    );
  }
}
