import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// FIX AUDITORÍA: el comando entre isolates alcanza la sesión concreta de UI.
class ControlDictado {
  bool cancelado = false;
  Future<bool> Function()? _cancelar;

  Future<bool> cancelarDictado() async {
    cancelado = true;
    return await _cancelar?.call() ?? true;
  }
}

/// Abre una hoja que escucha en español y devuelve lo transcrito (o null si
/// se canceló). Requiere internet y la app en primer plano.
Future<String?> dictar(
  BuildContext context, {
  required String titulo,
  required String ayuda,
}) async {
  final servicio = FlutterBackgroundService();
  final activo = await servicio.isRunning();
  final id = DateTime.now().microsecondsSinceEpoch.toString();
  final control = ControlDictado();
  StreamSubscription<Map<String, dynamic>?>? sub;
  StreamSubscription<Map<String, dynamic>?>? cancelacion;
  try {
    if (activo) {
      cancelacion = servicio.on('cancelarDictado').listen((datos) async {
        if (datos?['id'] != id) return;
        final ok = await control.cancelarDictado();
        servicio.invoke('dictadoCancelado', {'id': id, 'ok': ok});
      });
      final listo = Completer<bool>();
      sub = servicio.on('vozDictadoReservada').listen((datos) {
        if (datos?['id'] == id && !listo.isCompleted) {
          listo.complete(datos?['ok'] == true);
        }
      });
      servicio.invoke('reservarVozDictado', {'id': id});
      final permitido = await listo.future.timeout(const Duration(seconds: 12));
      if (!permitido) throw StateError('La alarma está usando el micrófono.');
    }
    if (!context.mounted || control.cancelado) return null;
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) =>
          _DictadoSheet(titulo: titulo, ayuda: ayuda, control: control),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar el dictado: $e')),
      );
    }
    return null;
  } finally {
    // FIX AUDITORÍA: cancelar listeners inmediatamente sin retrasar el parcial
    // por la limpieza asíncrona del canal entre isolates.
    unawaited(
      sub?.cancel().catchError((Object e) {
        debugPrint('📝 dictado: limpieza de confirmación: $e');
      }),
    );
    unawaited(
      cancelacion?.cancel().catchError((Object e) {
        debugPrint('📝 dictado: limpieza de cancelación: $e');
      }),
    );
    if (activo) servicio.invoke('liberarVozDictado', {'id': id});
  }
}

class _DictadoSheet extends StatefulWidget {
  final String titulo;
  final String ayuda;
  final ControlDictado control;
  const _DictadoSheet({
    required this.titulo,
    required this.ayuda,
    required this.control,
  });

  @override
  State<_DictadoSheet> createState() => _DictadoSheetState();
}

class _DictadoSheetState extends State<_DictadoSheet> {
  // FIX AUDITORÍA: cada hoja registra callbacks propios, sin retener la anterior.
  final _voz = SpeechToText();
  bool _cerrando = false;
  Future<bool>? _cancelacion;

  /// Lo confirmado en tandas anteriores (cada pausa larga cierra una tanda).
  String _acumulado = '';
  String _parcial = '';
  bool _escuchando = false;
  String? _error;

  /// No se usa locales(): en Android 13+ el plugin nunca responde si el
  /// teléfono no tiene reconocimiento en el dispositivo o si la consulta falla.
  /// Se usa el mismo idioma que la vigilancia por voz, que sí funciona.
  String _idioma = 'es_ES';

  String get _texto =>
      [_acumulado, _parcial].where((t) => t.trim().isNotEmpty).join(' ').trim();

  @override
  void initState() {
    super.initState();
    widget.control._cancelar = _cancelarPorAlarma;
    if (!widget.control.cancelado) {
      unawaited(_iniciar());
    }
  }

  void _alError(SpeechRecognitionError e) {
    if (!mounted || _cerrando) return;
    if (e.errorMsg.contains('language') && _idioma == 'es_ES') {
      // Una sola vez: si tampoco hay es_MX, se muestra el error.
      _idioma = 'es_MX';
      unawaited(_escuchar());
      return;
    }
    setState(() {
      _escuchando = false;
      if (e.errorMsg != 'error_no_match') {
        _error = _explicar(e.errorMsg);
      }
    });
  }

  void _alEstado(String estado) {
    if (!mounted || _cerrando) return;
    if (estado == 'done' || estado == 'notListening') {
      setState(() {
        _acumulado = _texto;
        _parcial = '';
        _escuchando = false;
      });
    }
  }

  Future<void> _iniciar() async {
    try {
      // initialize() solo registra callbacks la primera vez en el singleton.
      _voz.errorListener = _alError;
      _voz.statusListener = _alEstado;
      final ok = await _voz
          .initialize(onError: _alError, onStatus: _alEstado)
          .timeout(const Duration(seconds: 5));
      if (!mounted || _cerrando) return;
      if (!ok) {
        setState(() {
          _error =
              'El reconocimiento de voz no está disponible. Revisa el permiso '
              'de micrófono y que tengas instalada la app de Google.';
        });
        return;
      }
      await _escuchar();
    } catch (e) {
      if (mounted && !_cerrando) {
        setState(() => _error = 'No se pudo dictar: $e');
      }
      debugPrint('📝 dictado: inicialización falló: $e');
    }
  }

  Future<void> _escuchar() async {
    if (_cerrando) return;
    try {
      setState(() {
        _error = null;
        _escuchando = true;
      });
      await _voz
          .listen(
            onResult: (r) {
              if (!mounted || _cerrando) return;
              setState(() => _parcial = r.recognizedWords);
            },
            listenOptions: SpeechListenOptions(
              localeId: _idioma,
              listenFor: const Duration(minutes: 2),
              pauseFor: const Duration(seconds: 6),
              partialResults: true,
              listenMode: ListenMode.dictation,
            ),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (mounted && !_cerrando) {
        setState(() {
          _error = 'No se pudo dictar: $e';
          _escuchando = false;
        });
      }
      debugPrint('📝 dictado: escucha falló: $e');
    }
  }

  String _explicar(String codigo) => switch (codigo) {
    'error_network' ||
    'error_network_timeout' ||
    'error_server' => 'Sin conexión: el dictado necesita internet.',
    'error_audio' || 'error_permission' || 'error_insufficient_permissions' =>
      'No se pudo usar el micrófono. Revisa el permiso.',
    'error_busy' => 'El micrófono está ocupado. Intenta de nuevo.',
    'error_language_unavailable' || 'error_language_not_supported' =>
      'Tu teléfono no tiene el español para dictado. Revisa los idiomas '
          'del reconocimiento de voz de Google en los ajustes del teléfono.',
    _ => 'Error de reconocimiento ($codigo). Intenta de nuevo.',
  };

  Future<bool> _cancelarMicrofono() {
    if (_cancelacion != null) return _cancelacion!;
    _cerrando = true;
    // FIX AUDITORÍA: conservar el parcial antes de cancel(), que descarta resultados.
    _acumulado = _texto;
    _parcial = '';
    return _cancelacion = () async {
      try {
        await _voz.cancel().timeout(const Duration(seconds: 2));
        debugPrint('📝 dictado: micrófono liberado; texto conservado');
        return true;
      } catch (e) {
        debugPrint('📝 dictado: no se confirmó liberación: $e');
        return false;
      }
    }();
  }

  void _devolverTexto(bool usar) {
    if (!mounted) return;
    final ruta = ModalRoute.of(context);
    if (ruta == null || !ruta.isActive) return;
    // FIX AUDITORÍA: quitar ESTA hoja, aunque la alarma ya esté encima.
    Navigator.of(
      context,
    ).removeRoute(ruta, usar && _texto.isNotEmpty ? _texto : null);
  }

  Future<bool> _cancelarPorAlarma() async {
    final ok = await _cancelarMicrofono();
    _devolverTexto(true);
    return ok;
  }

  Future<void> _terminar(bool usar) async {
    await _cancelarMicrofono();
    _devolverTexto(usar);
  }

  @override
  void dispose() {
    widget.control._cancelar = null;
    if (_voz.errorListener == _alError) _voz.errorListener = null;
    if (_voz.statusListener == _alEstado) _voz.statusListener = null;
    if (!_cerrando) unawaited(_cancelarMicrofono());
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
