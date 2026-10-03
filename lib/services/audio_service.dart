import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _contadorBloque = 0;
  String? _rutaActual;
  bool _grabando = false;

  // Callback cuando termina un bloque
  Function(File archivo)? onBloqueCompletado;

  bool get grabando => _grabando;

  // Iniciar grabación en bloques de 5 minutos
  Future<void> iniciarGrabacion() async {
    if (_grabando) return;

    // No usar record.hasPermission(): sin Activity (servicio) siempre es false.
    if (!await Permission.microphone.isGranted) {
      throw Exception('Permiso de micrófono denegado');
    }

    _grabando = true;
    _contadorBloque = 0;
    try {
      await _iniciarBloque();
    } catch (_) {
      _grabando = false;
      rethrow;
    }
  }

  Future<void> _iniciarBloque() async {
    if (!_grabando) return;

    final dir = await getApplicationDocumentsDirectory();
    final carpetaAudios = Directory('${dir.path}/centinela_audios');
    if (!await carpetaAudios.exists()) {
      await carpetaAudios.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _rutaActual =
        '${carpetaAudios.path}/audio_${_contadorBloque}_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000, // 64 kbps, calidad aceptable y archivo pequeño
        sampleRate: 44100,
      ),
      path: _rutaActual!,
    );

    // Programar el fin del bloque en 5 minutos
    _timer = Timer(const Duration(minutes: 5), () async {
      await _finalizarBloque();
    });
  }

  Future<void> _finalizarBloque() async {
    if (!_grabando) return;

    await _recorder.stop();
    _contadorBloque++;

    // Notificar que hay un bloque listo
    if (_rutaActual != null) {
      final archivo = File(_rutaActual!);
      if (await archivo.exists()) {
        onBloqueCompletado?.call(archivo);
      }
    }

    // Iniciar el siguiente bloque si seguimos grabando
    if (_grabando) {
      await _iniciarBloque();
    }
  }

  Future<String?> detenerGrabacion() async {
    _grabando = false;
    _timer?.cancel();
    _timer = null;
    String? rutaDetenida = _rutaActual;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _rutaActual = null;
    return rutaDetenida;
  }

  Future<void> dispose() async {
    await detenerGrabacion();
    await _recorder.dispose();
  }
}
