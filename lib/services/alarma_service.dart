import 'dart:async';
import 'dart:io';
import 'package:centinela_nativo/centinela_nativo.dart';
import 'package:flutter/foundation.dart';
import 'audio_service.dart';
import 'alerta_service.dart';
import 'ubicacion_service.dart';
import 'sensor_service.dart';
import 'cloudinary_service.dart';
import 'alarma_sonido_service.dart';
import 'informe_service.dart';

enum EstadoAlarma { inactiva, activa, falsaAlarma, cancelada }

/// Primer fragmento corto para que el primer audio llegue rápido; luego
/// fragmentos más largos mientras la alarma siga activa.
const _primerFragmento = Duration(seconds: 10);
const _siguientesFragmentos = Duration(seconds: 30);

/// Datos de una alarma concreta (se descartan al cancelar).
class _Incidente {
  final int sesion;
  bool contactosAvisados = false;
  int fragmentos = 0;

  /// id en el historial (tabla incidentes); null si no se pudo crear.
  final Future<int?> registro;
  _Incidente(this.sesion, this.registro);
}

/// Esta instancia pertenece exclusivamente al isolate del servicio.
class AlarmaService {
  final _audio = AudioService();
  final _alerta = AlertaService();
  final _sensores = SensorService();
  final _sonido = AlarmaSonidoService();
  EstadoAlarma _estado = EstadoAlarma.inactiva;
  EstadoAlarma get estado => _estado;
  bool get sensoresPausados => _sensores.pausado;
  bool get vigilando => _sensores.activo && !_sensores.pausado;
  bool get grabando => _audio.grabando;
  int _sesion = 0;
  _Incidente? _incidente;
  Future<void>? _captura;
  Future<void>? _arranque;
  Future<void>? _ubicacion;
  Future<void> _envios = Future.value();
  Completer<void>? _fin;
  bool _cancelando = false;
  String? linkUbicacionActual;
  void Function(EstadoAlarma)? onEstadoCambiado;
  void Function(String)? onError;

  /// Alarma cancelada de verdad: la UI ofrece completar el informe.
  void Function(int idIncidente)? onIncidenteFinalizado;
  final _informes = InformeService();

  /// Qué pasó en la última alarma, para mostrarlo en pantalla.
  final bitacora = <String>[];
  void Function()? onBitacora;

  void _registrar(String evento) {
    final t = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    bitacora.add('${dos(t.hour)}:${dos(t.minute)}:${dos(t.second)}  $evento');
    if (bitacora.length > 40) bitacora.removeAt(0);
    debugPrint('📋 $evento');
    onBitacora?.call();
  }

  void _fallo(String evento) {
    _registrar('❌ $evento');
    onError?.call(evento);
  }

  void _cambiar(EstadoAlarma estado) {
    _estado = estado;
    onEstadoCambiado?.call(estado);
  }

  Future<void> iniciarVigilancia() async {
    _sensores.onAmenazaDetectada = (_) => unawaited(activarAlarma());
    await _sensores.iniciar();
  }

  Future<void> pausarSensores() async => _sensores.pausar();
  void reanudarSensores() => _sensores.reanudar();

  Future<void> activarAlarma() async {
    if (_cancelando || _estado != EstadoAlarma.inactiva) return;
    final sesion = ++_sesion;
    final incidente = _incidente = _Incidente(
      sesion,
      _informes
          .crearIncidente(fecha: DateTime.now())
          .then<int?>((id) => id)
          .catchError((Object e) {
            debugPrint('❌ No se pudo registrar el incidente: $e');
            return null;
          }),
    );
    final fin = Completer<void>();
    _fin = fin;
    bitacora.clear();
    _registrar('🚨 Alarma activada');
    _cambiar(EstadoAlarma.activa);
    // Con permiso "Mostrar sobre otras apps" se abre directo aunque la app
    // esté cerrada; si no, queda la notificación de pantalla completa.
    unawaited(CentinelaNativo.abrirAlarma().catchError((_) => false));
    _arranque = _prepararCaptura(incidente, fin.future);
    await _arranque;
  }

  Future<void> _prepararCaptura(_Incidente incidente, Future<void> fin) async {
    try {
      await _sensores.detener();
      if (incidente.sesion != _sesion) return;
      // Ubicación + SMS y grabación arrancan en paralelo.
      final ubicacion = _ubicacion = _enviarUbicacion(incidente);
      _captura = _grabar(incidente, ubicacion, fin);
      if (_estado == EstadoAlarma.activa) await _sonido.iniciar();
      if (_estado != EstadoAlarma.activa) await _sonido.detener();
    } catch (e) {
      _fallo('No se pudo iniciar la alarma: $e');
    }
  }

  Future<void> _enviarUbicacion(_Incidente incidente) async {
    try {
      final ubicaciones = UbicacionService();
      final pos = await ubicaciones.obtenerUbicacion(
        limite: const Duration(seconds: 3),
      );
      linkUbicacionActual = pos == null
          ? 'Ubicación no disponible'
          : ubicaciones.generarLinkMapa(pos.latitude, pos.longitude);
      _registrar('📍 Ubicación: $linkUbicacionActual');
      if (pos != null) {
        // En paralelo: el SMS no espera a la base de datos.
        unawaited(
          incidente.registro
              .then((id) async {
                if (id == null) return;
                await _informes.actualizarUbicacion(
                  id,
                  pos.latitude,
                  pos.longitude,
                );
              })
              .catchError((_) {}),
        );
      }
      if (incidente.sesion != _sesion) return;
      final r = await _alerta.enviarSMSUbicacionInmediata(
        linkUbicacion: linkUbicacionActual ?? 'Ubicación no disponible',
      );
      _registrarSms('SMS de ubicación', r, incidente);
    } catch (e) {
      _fallo('SMS de ubicación no enviado: $e');
    }
  }

  void _registrarSms(String que, ResultadoSms r, _Incidente incidente) {
    if (r.enviados > 0) incidente.contactosAvisados = true;
    if (r.enviados == 0) {
      _fallo('$que no enviado (fallaron: ${r.fallidos.join(', ')})');
    } else if (r.fallidos.isNotEmpty) {
      _registrar(
        '⚠️ $que: ${r.enviados}/${r.despachados}, falló ${r.fallidos.join(', ')}',
      );
    } else {
      _registrar('✉️ $que enviado a ${r.enviados} contacto(s)');
    }
  }

  Future<void> _grabar(
    _Incidente incidente,
    Future<void> ubicacion,
    Future<void> fin,
  ) async {
    try {
      while (incidente.sesion == _sesion) {
        final numero = ++incidente.fragmentos;
        await _audio.iniciarGrabacion();
        final duracion = numero == 1 ? _primerFragmento : _siguientesFragmentos;
        _registrar('🎙️ Grabando audio $numero (${duracion.inSeconds} s)…');
        if (incidente.sesion == _sesion) {
          await Future.any([Future<void>.delayed(duracion), fin]);
        }
        final ruta = await _audio.detenerGrabacion();
        // El último fragmento (cortado al cancelar) también se sube para el
        // historial, aunque ya no se envíe por SMS.
        if (ruta != null) {
          // La subida va en paralelo: el siguiente fragmento empieza ya.
          _envios = _envios.then(
            (_) => _enviarAudio(incidente, ubicacion, ruta, numero),
          );
        }
      }
    } catch (e) {
      _fallo('No se pudo grabar audio: $e');
    } finally {
      await _audio.detenerGrabacion();
    }
  }

  Future<void> _enviarAudio(
    _Incidente incidente,
    Future<void> ubicacion,
    String ruta,
    int numero,
  ) async {
    try {
      // Tras PIN falso la sesión sigue igual: el envío continúa en secreto.
      final vigente = incidente.sesion == _sesion;
      if (vigente) _registrar('☁️ Subiendo audio $numero a Cloudinary…');
      final link = UbicacionService().obtenerLinkUbicacion(
        limite: const Duration(seconds: 3),
      );
      final subida = await subirAudioACloudinary(ruta);
      final url = subida.url;
      if (url != null) {
        final id = await incidente.registro;
        if (id != null) await _informes.agregarAudio(id, url);
        await File(ruta).delete();
      }
      // Alarma ya cancelada: el audio queda en el historial, sin SMS.
      if (incidente.sesion != _sesion) return;
      linkUbicacionActual = await link;
      if (url != null) {
        _registrar('✅ Audio $numero subido: $url');
      } else {
        _fallo('Audio $numero no subido → ${subida.error}');
      }
      // El SMS de audio nunca debe adelantarse al de ubicación.
      await ubicacion;
      if (incidente.sesion != _sesion) return;
      final r = await _alerta.enviarSMSResultadoAudio(
        urlAudio: url,
        fragmento: numero,
        linkUbicacion: linkUbicacionActual,
      );
      _registrarSms('SMS de audio $numero', r, incidente);
    } catch (e) {
      _fallo('Audio $numero no enviado: $e');
    }
  }

  /// Detiene grabación, SMS pendientes y sonido, y vuelve a vigilar.
  /// Si [mensajeCierre] no es null y algún contacto ya recibió una alerta,
  /// se les envía ese aviso.
  Future<void> cancelarAlarma({String? mensajeCierre}) async {
    if (_cancelando || _estado == EstadoAlarma.inactiva) return;
    _cancelando = true;
    ++_sesion;
    _fin?.complete();
    _fin = null;
    final incidente = _incidente;
    final ubicacion = _ubicacion;
    final envios = _envios;
    _incidente = null;
    _ubicacion = null;
    _cambiar(EstadoAlarma.cancelada);
    _registrar('🛑 Alarma detenida');
    try {
      await _arranque;
      await _captura;
      await _sonido.detener();
      await iniciarVigilancia();
      _cambiar(EstadoAlarma.inactiva);
    } finally {
      _cancelando = false;
    }
    if (incidente == null) return;
    if (mensajeCierre != null) {
      unawaited(_avisarCierre(incidente, ubicacion, envios, mensajeCierre));
    }
    // Recién ahora aparece en el historial (con PIN falso sigue oculto).
    final id = await incidente.registro;
    if (id != null) {
      try {
        await _informes.finalizarIncidente(id);
        onIncidenteFinalizado?.call(id);
      } catch (e) {
        debugPrint('❌ No se pudo cerrar el incidente $id: $e');
      }
    }
  }

  Future<void> _avisarCierre(
    _Incidente incidente,
    Future<void>? ubicacion,
    Future<void> envios,
    String mensaje,
  ) async {
    try {
      // Que el aviso de cierre no llegue antes que un SMS en curso.
      await ubicacion;
      await envios.timeout(const Duration(seconds: 20), onTimeout: () {});
      if (!incidente.contactosAvisados) {
        _registrar('ℹ️ Ningún contacto recibió alertas: no se envía el cierre');
        return;
      }
      final r = await _alerta.enviarSMSCierre(mensaje);
      _registrarSms('Aviso "$mensaje"', r, incidente);
    } catch (e) {
      _fallo('No se pudo avisar el cierre: $e');
    }
  }

  Future<void> activarAlarmaFalsa() async {
    if (_estado != EstadoAlarma.activa) return;
    _cambiar(EstadoAlarma.falsaAlarma);
    await _sonido.detener();
  }

  Future<void> detener() async {
    ++_sesion;
    _fin?.complete();
    _fin = null;
    await _arranque;
    await _captura;
    await _sensores.detener();
    await _sonido.detener();
  }
}
