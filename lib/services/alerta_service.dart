import 'package:centinela_nativo/centinela_nativo.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

class AlertaService {
  final _db = DatabaseService();

  /// Envía el primer SMS de emergencia sin esperar al audio.
  Future<ResultadoSms> enviarSMSUbicacionInmediata({
    required String linkUbicacion,
  }) async {
    final mensaje = StringBuffer()
      ..writeln('🚨 ALERTA CENTINELA 🚨')
      ..writeln('📍 Ubicación: $linkUbicacion')
      ..writeln('🎧 Audio: procesando...');
    return _enviarMensajeAlerta(mensaje.toString(), 'SMS ubicación');
  }

  /// SMS con el link de cada fragmento de audio y la ubicación actual.
  Future<ResultadoSms> enviarSMSResultadoAudio({
    required String? urlAudio,
    required int fragmento,
    String? linkUbicacion,
  }) async {
    final subido = urlAudio != null && urlAudio.isNotEmpty;
    final nombre = fragmento == 1 ? 'Audio' : 'Audio $fragmento';
    final mensaje = StringBuffer()
      ..writeln(subido ? '📎 $nombre listo:' : '⚠️ $nombre no se pudo subir')
      ..writeln('📍 Ubicación: ${linkUbicacion ?? 'no disponible'}');
    if (subido) mensaje.writeln('🎧 Audio: $urlAudio');
    return _enviarMensajeAlerta(mensaje.toString(), 'SMS audio $fragmento');
  }

  /// SMS 3: lo envía la víctima a mano desde el detalle del incidente.
  Future<ResultadoSms> enviarSMSInforme({
    required String urlPdf,
    required String fechaIncidente,
  }) {
    final mensaje = StringBuffer()
      ..writeln('📄 INFORME CENTINELA')
      ..writeln('Incidente del $fechaIncidente')
      ..writeln('Informe de denuncia: $urlPdf');
    return _enviarMensajeAlerta(mensaje.toString(), 'SMS informe');
  }

  /// Avisa a los contactos que la alarma terminó.
  Future<ResultadoSms> enviarSMSCierre(String mensaje) =>
      _enviarMensajeAlerta(mensaje, 'SMS cierre');

  Future<ResultadoSms> _enviarMensajeAlerta(
    String mensaje,
    String etiqueta,
  ) async {
    final contactos = await _db.obtenerContactos();
    if (contactos.isEmpty) {
      throw StateError('No hay contactos de emergencia registrados');
    }
    final resultado = await CentinelaNativo.enviarSms(
      contactos.map((c) => c.telefono).toList(),
      mensaje,
    );
    debugPrint(
      '✉️ $etiqueta: ${resultado.enviados}/${contactos.length} enviados, '
      'fallidos ${resultado.fallidos}, sin confirmar ${resultado.sinConfirmar}',
    );
    return resultado;
  }

}
