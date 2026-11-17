import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Abre una hoja que escucha en español y devuelve lo transcrito (o null si
/// se canceló). Requiere internet y la app en primer plano.
Future<String?> dictar(
  BuildContext context, {
  required String titulo,
  required String ayuda,
}) async {
  final servicio = FlutterBackgroundService();
  final id = DateTime.now().microsecondsSinceEpoch.toString();
  StreamSubscription<Map<String, dynamic>?>? reserva;
  bool reservado = false;
  if (await servicio.isRunning()) {
    final listo = Completer<bool>();
    reserva = servicio.on('vozDictadoListo').listen((datos) {
      if (datos?['id'] == id && !listo.isCompleted) {
        listo.complete(datos?['ok'] == true);
      }
    });
    servicio.invoke('vozDictado', {'id': id, 'activo': true});
    reservado = await listo.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    await reserva.cancel();
    if (!reservado) {
      servicio.invoke('vozDictado', {'id': id, 'activo': false});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El micrófono está ocupado por la alarma. Intenta después.',
            ),
          ),
        );
      }
      return null;
    }
  }
  if (!context.mounted) {
    if (reservado) servicio.invoke('vozDictado', {'id': id, 'activo': false});
    return null;
  }
  try {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => _DictadoSheet(titulo: titulo, ayuda: ayuda),
    );
  } finally {
    if (reservado) servicio.invoke('vozDictado', {'id': id, 'activo': false});
  }
}

class _DictadoSheet extends StatefulWidget {
  final String titulo;
  final String ayuda;
  const _DictadoSheet({required this.titulo, required this.ayuda});

  @override
  State<_DictadoSheet> createState() => _DictadoSheetState();
}

class _DictadoSheetState extends State<_DictadoSheet> {
  final _voz = SpeechToText();
  StreamSubscription<Map<String, dynamic>?>? _alarmas;
  Timer? _limiteDictado;

  /// Lo confirmado en tandas anteriores (cada pausa larga cierra una tanda).
  String _acumulado = '';
  String _parcial = '';
  bool _escuchando = false;
  bool _interrumpido = false;
  String? _error;

  String get _texto =>
      [_acumulado, _parcial].where((t) => t.trim().isNotEmpty).join(' ').trim();

  @override
  void initState() {
    super.initState();
    _alarmas = FlutterBackgroundService().on('liberarDictado').listen((
      _,
    ) async {
      _interrumpido = true;
      await _voz.cancel();
      FlutterBackgroundService().invoke('dictadoLiberado');
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      } else {
        setState(() {
          _escuchando = false;
          _error =
              'Dictado detenido para grabar la alarma. Cierra y vuelve a abrir el dictado después.';
        });
      }
    });
    // La reserva del servicio dura 3 minutos: cerrar antes de que expire.
    _limiteDictado = Timer(
      const Duration(minutes: 2, seconds: 50),
      () => _terminar(true),
    );
    _iniciar();
  }

  Future<void> _iniciar() async {
    final ok = await _voz.initialize(
      onError: (SpeechRecognitionError e) {
        if (!mounted) return;
        setState(() {
          _escuchando = false;
          // "no match" solo significa silencio: se puede volver a hablar.
          if (e.errorMsg != 'error_no_match') _error = _explicar(e.errorMsg);
        });
      },
      onStatus: (estado) {
        if (!mounted) return;
        if (estado == 'done' || estado == 'notListening') {
          setState(() {
            _acumulado = _texto;
            _parcial = '';
            _escuchando = false;
          });
        }
      },
    );
    if (!mounted || _interrumpido) return;
    if (!ok) {
      setState(() {
        _error =
            'El reconocimiento de voz no está disponible. Revisa el permiso '
            'de micrófono y que tengas instalada la app de Google.';
      });
      return;
    }
    await _escuchar();
  }

  Future<void> _escuchar() async {
    if (_interrumpido) return;
    final locales = await _voz.locales();
    final espanol = locales.where((l) => l.localeId.startsWith('es')).toList();
    final preferido = espanol.firstWhere(
      (l) => l.localeId.contains('BO'),
      orElse: () => espanol.isNotEmpty
          ? espanol.first
          : (locales.isNotEmpty ? locales.first : LocaleName('es_ES', '')),
    );
    if (!mounted || _interrumpido) return;
    setState(() {
      _error = null;
      _escuchando = true;
    });
    await _voz.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _parcial = r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: preferido.localeId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 6),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  String _explicar(String codigo) => switch (codigo) {
    'error_network' ||
    'error_network_timeout' ||
    'error_server' => 'Sin conexión: el dictado necesita internet.',
    'error_audio' || 'error_permission' || 'error_insufficient_permissions' =>
      'No se pudo usar el micrófono. Revisa el permiso.',
    'error_busy' => 'El micrófono está ocupado. Intenta de nuevo.',
    _ => 'Error de reconocimiento ($codigo). Intenta de nuevo.',
  };

  Future<void> _terminar(bool usar) async {
    _interrumpido = true;
    await _voz.stop();
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      setState(() => _escuchando = false);
      return;
    }
    Navigator.pop(context, usar && _texto.isNotEmpty ? _texto : null);
  }

  @override
  void dispose() {
    _limiteDictado?.cancel();
    _alarmas?.cancel();
    _voz.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.titulo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(widget.ayuda, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                _escuchando ? Icons.mic : Icons.mic_off,
                color: _escuchando ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(_escuchando ? 'Escuchando…' : 'En pausa'),
              const Spacer(),
              if (!_escuchando && _error == null)
                TextButton.icon(
                  onPressed: _escuchar,
                  icon: const Icon(Icons.mic),
                  label: const Text('Seguir hablando'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 100, maxHeight: 260),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _texto.isEmpty ? '…' : _texto,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(onPressed: _escuchar, child: const Text('Reintentar')),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => _terminar(false),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _texto.isEmpty ? null : () => _terminar(true),
                icon: const Icon(Icons.check),
                label: const Text('Usar este texto'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
