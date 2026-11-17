import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Configuración compartida entre la UI y el isolate del servicio.
class ConfigVoz {
  static const clave = 'centinela_config_voz';
  static const palabrasIniciales = [
    'ayuda',
    'socorro',
    'auxilio',
    'peligro',
    'emergencia',
    'policia',
    // Insultos y amenazas (sin acentos: la comparación los ignora).
    'hijo de puta',
    'puta',
    'puto',
    'mierda',
    'carajo',
    'cabron',
    'cabrona',
    'pendejo',
    'pendeja',
    'cojudo',
    'cojuda',
    'idiota',
    'imbecil',
    'estupido',
    'estupida',
    'desgraciado',
    'desgraciada',
    'maldito',
    'maldita',
    'te voy a matar',
    'sueltame',
    'no me toques',
  ];

  /// Sube al cambiar [palabrasIniciales] para añadirlas una sola vez a las
  /// listas ya guardadas; lo que el usuario borre después no vuelve.
  static const _versionPalabras = 2;

  final bool decibelios;
  final bool palabrasActivas;
  final double umbral;
  final List<String> palabras;

  const ConfigVoz({
    this.decibelios = false,
    this.palabrasActivas = false,
    this.umbral = 7,
    this.palabras = palabrasIniciales,
  });

  bool get activa => decibelios || palabrasActivas;

  static String normalizar(String texto) =>
      _limpiar(texto).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static String _limpiar(String texto) {
    var resultado = texto.toLowerCase();
    const originales = 'áéíóúüñ';
    const reemplazos = 'aeiouun';
    for (var i = 0; i < originales.length; i++) {
      resultado = resultado.replaceAll(originales[i], reemplazos[i]);
    }
    return resultado;
  }

  String? detectarPalabra(String texto) {
    final frase = ' ${normalizar(texto)} ';
    for (final palabra in palabras) {
      final normal = normalizar(palabra);
      if (normal.isNotEmpty && frase.contains(' $normal ')) return palabra;
    }
    if (!texto.contains('*')) return null;
    // Android censura las palabras ofensivas por defecto ("p***"), así que
    // el texto censurado se compara letra por letra con la lista.
    final fichas = _limpiar(
      texto,
    ).replaceAll(RegExp(r'[^a-z0-9*]+'), ' ').trim().split(' ');
    for (final palabra in palabras) {
      final normal = normalizar(palabra);
      if (normal.isNotEmpty && _contieneCensurada(fichas, normal.split(' '))) {
        return palabra;
      }
    }
    return null;
  }

  static bool _contieneCensurada(List<String> fichas, List<String> buscadas) {
    for (var i = 0; i + buscadas.length <= fichas.length; i++) {
      var coincide = true;
      for (var j = 0; j < buscadas.length && coincide; j++) {
        coincide = _coincideCensurada(fichas[i + j], buscadas[j]);
      }
      if (coincide) return true;
    }
    return false;
  }

  /// "p***" coincide con "puta": misma longitud y mismas letras visibles.
  /// Se exige la primera letra para que "****" no coincida con cualquier cosa.
  static bool _coincideCensurada(String ficha, String palabra) {
    if (ficha.length != palabra.length || ficha.startsWith('*')) return false;
    for (var i = 0; i < ficha.length; i++) {
      if (ficha[i] != '*' && ficha[i] != palabra[i]) return false;
    }
    return true;
  }

  static Future<ConfigVoz> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // La UI y el servicio tienen caches diferentes.
    final guardado = prefs.getString(clave);
    if (guardado == null) return const ConfigVoz();
    try {
      final datos = jsonDecode(guardado) as Map<String, dynamic>;
      final guardadas = (datos['palabras'] as List? ?? palabrasIniciales)
          .cast<String>();
      return ConfigVoz(
        decibelios: datos['decibelios'] == true,
        palabrasActivas: datos['palabrasActivas'] == true,
        umbral: ((datos['umbral'] as num?)?.toDouble() ?? 7).clamp(1, 20),
        palabras: List<String>.unmodifiable(
          datos['versionPalabras'] == _versionPalabras
              ? guardadas
              : {...guardadas, ...palabrasIniciales},
        ),
      );
    } catch (e) {
      debugPrint('🎤 Configuración de voz inválida: $e');
      return const ConfigVoz();
    }
  }

  Future<void> guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      clave,
      jsonEncode({
        'decibelios': decibelios,
        'palabrasActivas': palabrasActivas,
        'umbral': umbral.clamp(1, 20),
        'versionPalabras': _versionPalabras,
        'palabras': palabras
            .map(normalizar)
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList(),
      }),
    );
  }
}

/// Instancia exclusiva del isolate del Foreground Service. La UI solo guarda
/// ConfigVoz y manda comandos al servicio; nunca inicia este reconocedor.
class VoiceService {
  static final VoiceService _instancia = VoiceService._();
  factory VoiceService() => _instancia;
  VoiceService._() : _voz = SpeechToText(), _ahora = DateTime.now;

  @visibleForTesting
  VoiceService.paraPruebas(SpeechToText motor, {DateTime Function()? ahora})
    : _voz = motor,
      _ahora = ahora ?? DateTime.now;

  final SpeechToText _voz;
  final DateTime Function() _ahora;
  ConfigVoz _config = const ConfigVoz();
  void Function(String motivo)? onAmenazaVoz;
  // FIX AUDITORÍA: estado observable desde el isolate del servicio.
  void Function()? onEstadoCambiado;
  String _estado = 'detenida';
  String? _error;
  String get estado => _estado;
  String? get error => _error;
  bool get conError => _error != null && _puedeEscuchar;

  void _publicarEstado(String estado, {String? error}) {
    if (_estado == estado && _error == error) return;
    _estado = estado;
    _error = error;
    onEstadoCambiado?.call();
  }

  void _publicarSuspension() {
    _inicioSonidoAlto = null;
    _publicarEstado(
      !_activo
          ? 'detenida'
          : !_config.activa
          ? 'desactivada'
          : _pausado
          ? 'pausada'
          : _reservado
          ? 'reservada'
          : _dictando
          ? 'dictado'
          : 'esperando',
    );
  }

  void _fallar(Object error) {
    _inicioSonidoAlto = null;
    _esperaLarga = true;
    if (_reintentoRapido) {
      _reintento?.cancel();
      _reintento = null;
    }
    debugPrint('🎤 voz: $error');
    if (_puedeEscuchar) _publicarEstado('error', error: error.toString());
  }

  bool _activo = false;
  bool _pausado = false;
  bool _reservado = false;
  bool _dictando = false;
  bool _disparado = false;
  bool _inicializado = false;
  String _locale = 'es_ES';
  int _generacion = 0;
  DateTime? _inicioSonidoAlto;
  static const _duracionSonidoAlto = Duration(milliseconds: 500);
  // Terminar por silencio es normal: se vuelve a escuchar casi enseguida para
  // reducir los huecos. Un error real conserva la espera larga para no saturar
  // al motor, por ejemplo sin internet.
  static const _reinicioRapido = Duration(milliseconds: 500);
  static const _reinicioLento = Duration(seconds: 3);
  static const _erroresDeSilencio = {'error_speech_timeout', 'error_no_match'};
  Timer? _reintento;
  bool _reintentoRapido = false;
  bool _esperaLarga = false;
  Timer? _vigilante;
  Future<void> _cola = Future.value();

  bool get _puedeEscuchar =>
      _activo &&
      !_pausado &&
      !_reservado &&
      !_dictando &&
      !_disparado &&
      _config.activa;

  Future<void> _orden(Future<void> Function() accion) {
    final tarea = _cola.then((_) => accion());
    _cola = tarea.catchError((Object e) {
      _fallar(e);
      _programar();
    });
    return tarea;
  }

  Future<void> iniciar() {
    _activo = true;
    _vigilante ??= Timer.periodic(const Duration(seconds: 3), (_) {
      if (_puedeEscuchar && !_voz.isListening) _programar();
    });
    return actualizarConfiguracion();
  }

  Future<void> actualizarConfiguracion() => _orden(() async {
    _config = await ConfigVoz.cargar();
    _publicarSuspension();
    await _cancelar();
    await _escuchar();
  });

  Future<void> detener() {
    _activo = false;
    _publicarSuspension();
    _vigilante?.cancel();
    _vigilante = null;
    return _orden(_cancelar);
  }

  Future<void> pausar() {
    _pausado = true;
    _publicarSuspension();
    return _orden(_cancelar);
  }

  Future<void> reanudar() {
    _pausado = false;
    _publicarSuspension();
    return _orden(_escuchar);
  }

  Future<void> reservarMicrofonoParaGrabacion() {
    // Bloquea callbacks y reintentos antes de cualquier await.
    _reservado = true;
    _publicarSuspension();
    debugPrint('🎤 voz: micrófono reservado para grabación');
    return _orden(_cancelar);
  }

  Future<void> liberarMicrofonoDeGrabacion() {
    _reservado = false;
    _disparado = false;
    _publicarSuspension();
    return _orden(_escuchar);
  }

  Future<void> reservarParaDictado(bool reservar) {
    _dictando = reservar;
    _publicarSuspension();
    return _orden(reservar ? _cancelar : _escuchar);
  }

  Future<void> _cancelar() async {
    _inicioSonidoAlto = null;
    ++_generacion;
    _reintento?.cancel();
    _reintento = null;
    // FIX AUDITORÍA: un canal nativo bloqueado no retiene la cola.
    await _voz.cancel().timeout(const Duration(seconds: 5));
  }

  void _programar({bool rapido = false}) {
    if (!_puedeEscuchar) return;
    final usarRapido = rapido && !_esperaLarga;
    if (_reintento != null && (!usarRapido || _reintentoRapido)) return;
    _reintento?.cancel();
    _reintentoRapido = usarRapido;
    _reintento = Timer(usarRapido ? _reinicioRapido : _reinicioLento, () {
      _reintento = null;
      unawaited(_orden(usarRapido ? _reiniciar : _escuchar));
    });
  }

  /// El plugin no cancela el temporizador de pausa de la sesión anterior al
  /// iniciar otra; sin este cancel quedaría huérfano y haría un stop tardío.
  Future<void> _reiniciar() async {
    if (!_puedeEscuchar || _voz.isListening) return;
    await _voz.cancel().timeout(const Duration(seconds: 5));
    await _escuchar();
  }

  Future<void> _escuchar() async {
    if (!_puedeEscuchar || _voz.isListening) return;
    _inicioSonidoAlto = null;
    final generacion = _generacion;
    try {
      _publicarEstado('iniciando', error: _error);
      // Los diálogos de permisos requieren Activity: Home/ConfigVoz los pide
      // con permission_handler antes de iniciar el servicio.
      if (!await Permission.microphone.isGranted) {
        throw StateError('Concede el permiso de micrófono desde la app');
      }
      if (!_inicializado) {
        _inicializado = await _voz
            .initialize(
              onStatus: (estado) {
                if (!_puedeEscuchar) return;
                if (estado == 'listening') {
                  _esperaLarga = false;
                  _publicarEstado('escuchando');
                }
                if (estado == 'done' || estado == 'notListening') {
                  _inicioSonidoAlto = null;
                  if (_error == null) _publicarEstado('esperando');
                  // 'notListening' puede llegar antes del resultado final;
                  // 'done' indica que la sesión ya terminó.
                  _programar(rapido: estado == 'done');
                }
              },
              onError: (error) {
                if (_erroresDeSilencio.contains(error.errorMsg)) {
                  _inicioSonidoAlto = null;
                  _programar(rapido: true);
                  return;
                }
                _fallar(error.errorMsg);
                if (error.errorMsg.contains('language')) {
                  _locale = _locale == 'es_ES' ? 'es_MX' : 'es_ES';
                }
                _programar();
              },
              options: [SpeechToText.androidNoBluetooth],
            )
            .timeout(const Duration(seconds: 5));
        if (!_inicializado) throw StateError('Motor de voz no disponible');
      }
      if (!_puedeEscuchar || generacion != _generacion) return;
      await _voz
          .listen(
            onResult: (resultado) {
              if (!_puedeEscuchar ||
                  generacion != _generacion ||
                  !_config.palabrasActivas) {
                return;
              }
              if (kDebugMode) {
                debugPrint('🗣️ Oído: "${resultado.recognizedWords}"');
              }
              final palabra = _config.detectarPalabra(
                resultado.recognizedWords,
              );
              // No se filtra por confianza: Android suele entregar -1 (sin
              // dato). Tampoco se espera al resultado final: en una discusión
              // sin pausas podría tardar demasiado en llegar.
              if (palabra != null) {
                debugPrint('🗣️ Palabra clave: $palabra');
                _amenaza('Palabra clave: $palabra');
              }
            },
            onSoundLevelChange: (nivel) {
              if (generacion != _generacion) return;
              if (!_puedeEscuchar || !_config.decibelios || !nivel.isFinite) {
                _inicioSonidoAlto = null;
                return;
              }
              // Android entrega RMS relativo, NO dB SPL calibrados.
              if (nivel < _config.umbral) {
                _inicioSonidoAlto = null;
                return;
              }
              // Exige 500 ms continuos sobre el umbral; un descenso reinicia.
              final ahora = _ahora();
              _inicioSonidoAlto ??= ahora;
              if (ahora.difference(_inicioSonidoAlto!) >= _duracionSonidoAlto) {
                _inicioSonidoAlto = null;
                debugPrint('🔊 Nivel alto: ${nivel.toStringAsFixed(1)}');
                _amenaza('Nivel alto: ${nivel.toStringAsFixed(1)}');
              }
            },
            listenOptions: SpeechListenOptions(
              localeId: _locale,
              partialResults: true,
              cancelOnError: true,
              listenMode: ListenMode.dictation,
              listenFor: const Duration(minutes: 1),
              pauseFor: const Duration(seconds: 3),
            ),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('🎤 voz: sesión solicitada ($_locale)');
      _programar(); // También cubre un listen rechazado sin callback.
    } catch (e) {
      _fallar(e);
      if (e is TimeoutException) {
        // FIX AUDITORÍA: timeout no cancela la operación nativa por sí solo.
        try {
          await _cancelar();
        } catch (cancelacion) {
          _fallar(cancelacion);
        }
      }
      _programar();
    }
  }

  void _amenaza(String motivo) {
    if (!_puedeEscuchar) return;
    _disparado = true;
    onAmenazaVoz?.call(motivo);
  }
}
