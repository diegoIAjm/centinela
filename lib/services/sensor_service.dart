import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'detector_agitado.dart';
import 'detector_ruido.dart';

enum TipoSensor { agitado, ruido }

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // ====== SENSOR DE AGITADO ======
  StreamSubscription? _acelerometroSub;
  final _agitado = DetectorAgitado();
  final _reloj = Stopwatch()..start();

  // ====== SENSOR DE RUIDO ======
  final AudioRecorder _recorderRuido = AudioRecorder();
  StreamSubscription? _streamRuido;
  final _ruido = DetectorRuido();
  static const double _umbralRuidoDb = -20.0; // dBFS: 0 es el maximo digital

  /// Desactivado: por ahora la alarma solo se dispara al agitar. Así el
  /// micrófono queda libre y solo se usa para grabar evidencia.
  static const _detectarRuido = false;

  bool _activo = false;
  bool get activo => _activo;

  bool _pausado = false;
  bool get pausado => _pausado;

  // Callback cuando se detecta una amenaza
  Function(TipoSensor)? onAmenazaDetectada;

  /// Iniciar todos los sensores
  Future<void> iniciar() async {
    if (_activo) return;
    _pausado = false;
    _agitado.resetear();
    _ruido.resetear();
    debugPrint('🎯 Sensores iniciados');

    try {
      if (_detectarRuido) await _iniciarDetectorRuido();
      _iniciarAcelerometro();
      _activo = true;
    } catch (_) {
      await detener();
      rethrow;
    }
  }

  /// Pausar temporalmente (para conciertos, carreras, etc.)
  void pausar() {
    _pausado = true;
    debugPrint('⏸️ Sensores pausados');
  }

  /// Reanudar
  void reanudar() {
    _pausado = false;
    _agitado.resetear();
    _ruido.resetear();
    debugPrint('▶️ Sensores reanudados');
  }

  /// Detener todo
  Future<void> detener() async {
    _activo = false;
    await _acelerometroSub?.cancel();
    _acelerometroSub = null;
    await _streamRuido?.cancel();
    _streamRuido = null;
    if (await _recorderRuido.isRecording()) {
      await _recorderRuido.stop();
    }
    debugPrint('🛑 Sensores detenidos');
  }

  // ====== ACELERÓMETRO ======
  void _iniciarAcelerometro() {
    _acelerometroSub =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 20),
        ).listen((event) {
          if (_pausado || !_activo) return;

          // Magnitud de la aceleración
          final magnitud = sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );

          if (_agitado.agregar(magnitud, _reloj.elapsed)) {
            onAmenazaDetectada?.call(TipoSensor.agitado);
          }
        });
  }

  // ====== DETECTOR DE RUIDO (AMPLITUD DE AUDIO) ======
  Future<void> _iniciarDetectorRuido() async {
    // record.hasPermission() exige una Activity y en el servicio no hay:
    // devolvería false aunque el permiso esté concedido.
    if (!await Permission.microphone.isGranted) {
      throw StateError('Sin permiso de micrófono para detector de ruido');
    }

    // Grabar a un archivo temporal y leer la amplitud
    final stream = await _recorderRuido.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _streamRuido = stream.listen((data) {
      if (_pausado || !_activo || data.length < 2) return;

      // Calcular el nivel RMS (amplitud) de la muestra
      double suma = 0;
      for (int i = 0; i < data.length; i += 2) {
        // PCM 16-bit little-endian
        if (i + 1 < data.length) {
          int sample = (data[i + 1] << 8) | data[i];
          if (sample > 32767) sample -= 65536; // signed
          suma += sample * sample;
        }
      }
      final rms = sqrt(suma / (data.length / 2));
      if (rms <= 0) return;
      final dbRelativo = 20 * (log(rms / 32768) / ln10);

      // Detectar si supera el umbral de forma sostenida
      if (_ruido.agregar(dbRelativo > _umbralRuidoDb, _reloj.elapsed)) {
        debugPrint('🔊 Ruido sostenido (${dbRelativo.toStringAsFixed(1)} dB)');
        onAmenazaDetectada?.call(TipoSensor.ruido);
      }
    });
  }

  Future<void> dispose() async {
    await detener();
    await _recorderRuido.dispose();
  }
}
