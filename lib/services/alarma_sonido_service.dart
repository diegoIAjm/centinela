import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AlarmaSonidoService {
  final AudioPlayer _player = AudioPlayer();
  String? _rutaTono;

  Future<void> iniciar() async {
    try {
      final ruta = await _crearTono();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(DeviceFileSource(ruta), volume: 1.0);
      debugPrint('🔊 Alarma sonora iniciada');
    } catch (e) {
      debugPrint('❌ No se pudo reproducir la alarma sonora: $e');
    }
  }

  Future<void> detener() async {
    await _player.stop();
    debugPrint('🔇 Alarma sonora detenida');
  }

  Future<String> _crearTono() async {
    if (_rutaTono != null && await File(_rutaTono!).exists()) {
      return _rutaTono!;
    }

    final directorio = await getTemporaryDirectory();
    final archivo = File('${directorio.path}/centinela_alarma.wav');
    const sampleRate = 44100;
    const duracionSegundos = 1;
    final muestras = sampleRate * duracionSegundos;
    final datos = BytesBuilder();

    for (var i = 0; i < muestras; i++) {
      final tiempo = i / sampleRate;
      final frecuencia = tiempo < 0.5 ? 880.0 : 660.0;
      final amplitud = sin(2 * pi * frecuencia * tiempo) * 0.8;
      final valor = (amplitud * 32767).round();
      datos.add(
        Uint8List(2)..buffer.asByteData().setInt16(0, valor, Endian.little),
      );
    }

    final contenido = BytesBuilder()
      ..add(_ascii('RIFF'))
      ..add(_int32(36 + datos.length))
      ..add(_ascii('WAVE'))
      ..add(_ascii('fmt '))
      ..add(_int32(16))
      ..add(_int16(1))
      ..add(_int16(1))
      ..add(_int32(sampleRate))
      ..add(_int32(sampleRate * 2))
      ..add(_int16(2))
      ..add(_int16(16))
      ..add(_ascii('data'))
      ..add(_int32(datos.length))
      ..add(datos.takeBytes());

    await archivo.writeAsBytes(contenido.takeBytes(), flush: true);
    _rutaTono = archivo.path;
    return archivo.path;
  }

  Uint8List _ascii(String texto) => Uint8List.fromList(texto.codeUnits);

  Uint8List _int16(int valor) {
    final bytes = ByteData(2)..setInt16(0, valor, Endian.little);
    return bytes.buffer.asUint8List();
  }

  Uint8List _int32(int valor) {
    final bytes = ByteData(4)..setInt32(0, valor, Endian.little);
    return bytes.buffer.asUint8List();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
