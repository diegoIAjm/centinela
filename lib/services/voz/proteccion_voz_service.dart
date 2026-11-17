import 'dart:async';

import '../../models/configuracion_voz.dart';
import 'configuracion_voz_store.dart';
import 'motor_voz.dart';

/// Vive únicamente en el isolate del servicio. Todas las operaciones de
/// micrófono se serializan, incluida la entrega al grabador de evidencia.
class ProteccionVozService {
  final MotorVoz motor;
  final Future<void> Function() activarAlarma;
  final void Function() alCambiar;
  final DateTime Function() reloj;
  ConfiguracionVoz config = const ConfiguracionVoz();
  String estado = 'desactivada';
  String? error;
  String? ultimaDeteccion;
  DateTime? fechaDeteccion;
  bool _disponible = false;
  bool _escuchando = false;
  bool _microfonoLiberado = true;
  bool _bloqueadaPorError = false;
  bool _wakeLock = false;
  bool _disparando = false;
  DateTime? _dictadoHasta;
  Future<void> _cola = Future.value();
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _store = ConfiguracionVozStore();

  ProteccionVozService({
    required this.motor,
    required this.activarAlarma,
    required this.alCambiar,
    DateTime Function()? reloj,
  }) : reloj = reloj ?? DateTime.now;

  Map<String, dynamic> get resumen => {
    'estado': estado,
    'error': error,
    'modoPrueba': config.modoPrueba,
    'ultimaDeteccion': ultimaDeteccion,
    'fechaDeteccion': fechaDeteccion?.toIso8601String(),
  };

  Future<void> _serial(Future<void> Function() accion) {
    final tarea = _cola.then((_) => accion());
    _cola = tarea.catchError((Object e) {
      error = 'Voz no disponible: $e';
      estado = 'error';
      _bloqueadaPorError = true;
      alCambiar();
    });
    return _cola;
  }

  Future<void> iniciar() async {
    if (_sub != null) return;
    _sub = motor.eventos.listen(_evento);
    await recargar();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(evaluar()),
    );
  }

  Future<void> recargar() => _serial(() async {
    await _parar();
    try {
      config = await _store.cargar();
      error = null;
      _bloqueadaPorError = false;
    } catch (e) {
      config = const ConfiguracionVoz();
      rethrow;
    }
    await _evaluar();
  });

  bool get dictadoActivo => _dictadoHasta?.isAfter(reloj()) ?? false;

  Future<void> disponible(bool valor) async {
    // Cambiar inmediatamente invalida resultados encolados antes de liberar el micrófono.
    _disponible = valor;
    await evaluar();
    if (!valor && !_microfonoLiberado) {
      throw StateError('No se pudo liberar el micrófono de voz.');
    }
  }

  Future<void> dictado(bool activo) async {
    _dictadoHasta = activo ? reloj().add(const Duration(minutes: 3)) : null;
    await evaluar();
    if (activo && !_microfonoLiberado) {
      throw StateError('La escucha aún está usando el micrófono.');
    }
  }

  Future<void> evaluar() => _serial(_evaluar);

  Future<void> _evaluar() async {
    final mantener = config.habilitada && _disponible && !_bloqueadaPorError;
    if (mantener != _wakeLock) {
      await motor.mantenerServicio(mantener);
      _wakeLock = mantener;
    }
    final ocupado = _dictadoHasta?.isAfter(reloj()) ?? false;
    final siguiente = _bloqueadaPorError
        ? 'error'
        : !config.habilitada
        ? 'desactivada'
        : !_disponible
        ? 'suspendida'
        : ocupado
        ? 'dictado'
        : !config.contiene(reloj())
        ? 'esperando'
        : 'escuchando';
    if (siguiente != 'escuchando') {
      await _parar();
    } else if (!_escuchando) {
      _microfonoLiberado = false;
      await motor.iniciar();
      _escuchando = true;
    }
    if (estado != siguiente) {
      estado = siguiente;
      alCambiar();
    }
  }

  Future<void> _parar() async {
    // Detener nativo también si el inicio falló parcialmente.
    _microfonoLiberado = false;
    await motor.detener();
    _microfonoLiberado = true;
    _escuchando = false;
  }

  void _evento(Map<String, dynamic> e) {
    if (e['tipo'] == 'error') {
      _bloqueadaPorError = true;
      unawaited(
        _serial(() async {
          await _parar();
          _bloqueadaPorError = true;
          error = e['mensaje'] as String? ?? 'Falló el micrófono.';
          await _evaluar();
          alCambiar();
        }),
      );
      return;
    }
    if (e['tipo'] != 'texto' ||
        !_escuchando ||
        _bloqueadaPorError ||
        !_disponible ||
        _disparando ||
        (_dictadoHasta?.isAfter(reloj()) ?? false) ||
        !config.contiene(reloj())) {
      return;
    }
    final frase = fraseCoincidente(e['texto'] as String? ?? '', config.frases);
    if (frase == null) return;
    final transcurrido = fechaDeteccion == null
        ? null
        : reloj().difference(fechaDeteccion!);
    if (transcurrido != null &&
        !transcurrido.isNegative &&
        transcurrido.inSeconds < 30) {
      return;
    }
    ultimaDeteccion = frase; // Nunca se conserva la conversación completa.
    fechaDeteccion = reloj();
    alCambiar();
    if (!config.modoPrueba) {
      _disparando = true;
      // No se espera dentro de _cola: la alarma nos pide detener el micrófono.
      unawaited(
        activarAlarma()
            .catchError((Object e) {
              error = 'No se pudo activar la alarma por voz: $e';
              alCambiar();
            })
            .whenComplete(() => _disparando = false),
      );
    }
  }

  Future<void> cerrar() async {
    _timer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await disponible(false);
  }
}
