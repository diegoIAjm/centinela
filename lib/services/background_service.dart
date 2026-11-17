import 'dart:async';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'alarma_service.dart';
import 'informe_service.dart';
import 'notificacion_alarma.dart';
import 'voice_service.dart';

const _canalNotificacion = 'centinela_vigilancia';
const _idNotificacion = 7001;

Future<void> configurarServicioSegundoPlano() async {
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _canalNotificacion,
          'Centinela',
          description: 'Protección con micrófono y ubicación activos',
          importance: Importance.low,
        ),
      );
  await FlutterBackgroundService().configure(
    iosConfiguration: IosConfiguration(autoStart: false),
    androidConfiguration: AndroidConfiguration(
      onStart: _iniciarServicio,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _canalNotificacion,
      initialNotificationTitle: 'Centinela',
      initialNotificationContent: 'Iniciando protección…',
      foregroundServiceNotificationId: _idNotificacion,
      foregroundServiceTypes: [
        AndroidForegroundType.microphone,
        AndroidForegroundType.location,
      ],
    ),
  );
}

/// Esperar confirmación de sensores, no solamente del proceso Android.
Future<void> iniciarServicioSegundoPlano() async {
  final servicio = FlutterBackgroundService();
  final listo = Completer<void>();
  final sub = servicio.on('estado').listen((datos) {
    if (listo.isCompleted || datos == null) return;
    if (datos['error'] != null) {
      listo.completeError(StateError(datos['error'] as String));
    } else if (datos['listo'] == true) {
      listo.complete();
    }
  });
  try {
    if (!await servicio.isRunning()) {
      if (!await servicio.startService()) {
        throw StateError('Android no pudo iniciar la protección');
      }
    }
    servicio.invoke('consultarEstado');
    await listo.future.timeout(const Duration(seconds: 20));
  } finally {
    await sub.cancel();
  }
}

Future<void> detenerServicioSegundoPlano() async {
  FlutterBackgroundService().invoke('detener');
}

@pragma('vm:entry-point')
void _iniciarServicio(ServiceInstance servicio) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final alarma = AlarmaService();
  final voz = VoiceService();
  bool listo = false;
  String? error;
  Timer? pausa;
  String? pausaEtiqueta;
  bool pausaIndefinida = false;
  Future<void> comandos = Future.value();
  String? idDictado;
  Completer<bool>? dictadoCancelado;

  // Con PIN falso la UI y la notificación deben verse como tras un PIN real.
  bool encubierto() => alarma.estado == EstadoAlarma.falsaAlarma;

  void publicar() {
    servicio.invoke('estado', {
      'listo': listo,
      'vigilando': alarma.vigilando || encubierto(),
      'pausado': alarma.sensoresPausados,
      'alarma': alarma.estado.name,
      'pausaEtiqueta': pausaEtiqueta,
      'pausaIndefinida': pausaIndefinida,
      'error': encubierto() ? null : error,
      'bitacora': encubierto() ? const <String>[] : alarma.bitacora,
      'vozEstado': encubierto() ? null : voz.estado,
      'vozError': encubierto() || !voz.conError ? null : voz.error,
    });
  }

  Future<void> notificar() async {
    if (servicio is AndroidServiceInstance) {
      await servicio.setForegroundNotificationInfo(
        title: 'Centinela',
        content: (error != null || voz.conError) && !encubierto()
            ? 'Protección con incidencias. Abre la app.'
            : alarma.sensoresPausados
            ? 'Protección pausada'
            : 'Protección activa',
      );
    }
  }

  void ejecutar(Future<void> Function() accion) {
    comandos = comandos
        .then((_) => accion())
        .catchError((Object e) {
          error = e.toString();
        })
        .then((_) async {
          publicar();
          await notificar();
        });
  }

  // FIX AUDITORÍA: los ACK no pasan por la cola que está esperando cancelarlos.
  servicio.on('dictadoCancelado').listen((datos) {
    if (datos?['id'] == idDictado && dictadoCancelado?.isCompleted == false) {
      dictadoCancelado!.complete(datos?['ok'] == true);
    }
  });
  alarma.cancelarDictado = () async {
    final id = idDictado;
    if (id == null) return;
    final confirmacion = dictadoCancelado = Completer<bool>();
    servicio.invoke('cancelarDictado', {'id': id});
    try {
      final ok = await confirmacion.future.timeout(const Duration(seconds: 4));
      if (!ok) debugPrint('📝 dictado: cancelación UI falló; continúa alarma');
    } catch (e) {
      debugPrint('📝 dictado: UI sin confirmación; continúa alarma: $e');
    } finally {
      dictadoCancelado = null;
      if (idDictado == id) idDictado = null;
    }
  };
  voz.onEstadoCambiado = () {
    publicar();
    unawaited(notificar());
  };

  alarma.onEstadoCambiado = (estado) {
    publicar();
    // Full-screen intent: enciende la pantalla y abre la alarma aunque la
    // app esté cerrada. Se retira al cancelar o al usar el PIN falso.
    unawaited(
      estado == EstadoAlarma.activa
          ? mostrarNotificacionAlarma()
          : cancelarNotificacionAlarma(),
    );
  };
  alarma.onError = (mensaje) {
    error = mensaje;
    publicar();
    unawaited(notificar());
  };
  alarma.onBitacora = publicar;
  alarma.onIncidenteFinalizado = (id) =>
      servicio.invoke('incidenteFinalizado', {'id': id});
  servicio.on('consultarEstado').listen((_) => publicar());
  servicio
      .on('configVozActualizada')
      .listen((_) => ejecutar(voz.actualizarConfiguracion));
  servicio
      .on('reservarVozDictado')
      .listen(
        (datos) => ejecutar(() async {
          final id = datos?['id'] as String?;
          if (alarma.estado != EstadoAlarma.inactiva ||
              idDictado != null ||
              id == null) {
            servicio.invoke('vozDictadoReservada', {
              'id': datos?['id'],
              'ok': false,
            });
            return;
          }
          idDictado = id;
          try {
            await voz.reservarParaDictado(true);
          } catch (e) {
            idDictado = null;
            servicio.invoke('vozDictadoReservada', {'id': id, 'ok': false});
            rethrow;
          }
          servicio.invoke('vozDictadoReservada', {
            'id': datos?['id'],
            'ok': idDictado == id && alarma.estado == EstadoAlarma.inactiva,
          });
        }),
      );
  servicio
      .on('liberarVozDictado')
      .listen(
        (datos) => ejecutar(() async {
          // FIX AUDITORÍA: una hoja antigua no libera la reserva de otra sesión.
          if (datos?['id'] != idDictado && idDictado != null) return;
          idDictado = null;
          await voz.reservarParaDictado(false);
        }),
      );
  servicio.on('activarAlarma').listen((_) => ejecutar(alarma.activarAlarma));
  void cancelar(String mensajeCierre) => ejecutar(() async {
    error = null;
    await alarma.cancelarAlarma(mensajeCierre: mensajeCierre);
  });
  servicio
      .on('cancelarAlarma')
      .listen((_) => cancelar('✅ Falsa alarma, todo bien'));
  servicio
      .on('estoyASalvo')
      .listen((_) => cancelar('✅ Estoy a salvo, falsa alarma'));
  servicio.on('falsaAlarma').listen((_) => ejecutar(alarma.activarAlarmaFalsa));
  servicio
      .on('pausar')
      .listen(
        (datos) => ejecutar(() async {
          if (alarma.estado != EstadoAlarma.inactiva) return;
          final indefinida = datos?['indefinida'] == true;
          final minutos = datos?['duracionMinutos'];
          final duracion = minutos is int && minutos > 0 ? minutos : 30;
          await alarma.pausarSensores();
          pausa?.cancel();
          pausaEtiqueta = datos?['etiqueta'] as String?;
          pausaIndefinida = indefinida;
          pausa = indefinida
              ? null
              : Timer(Duration(minutes: duracion), () {
                  ejecutar(() async {
                    pausaEtiqueta = null;
                    pausaIndefinida = false;
                    alarma.reanudarSensores();
                  });
                });
        }),
      );
  servicio
      .on('reanudar')
      .listen(
        (_) => ejecutar(() async {
          pausa?.cancel();
          pausaEtiqueta = null;
          pausaIndefinida = false;
          alarma.reanudarSensores();
        }),
      );
  servicio
      .on('detener')
      .listen(
        (_) => ejecutar(() async {
          pausa?.cancel();
          pausaEtiqueta = null;
          pausaIndefinida = false;
          await alarma.detener();
          await servicio.stopSelf();
        }),
      );

  // Recién arrancado no hay alarma en curso: lo que quedó abierto (servicio
  // cerrado a la fuerza en plena alarma) pasa al historial.
  try {
    await InformeService().finalizarAbiertos();
  } catch (e) {
    debugPrint('⚠️ No se pudieron cerrar incidentes abiertos: $e');
  }

  try {
    await alarma.iniciarVigilancia();
    // FIX AUDITORÍA: voz opcional no impide iniciar vigilancia por sacudidas.
    try {
      await voz.iniciar();
    } catch (e) {
      debugPrint('🎤 voz: inicio falló; continúan los sensores: $e');
    }
    listo = true;
    publicar();
    await notificar();
  } catch (e) {
    error = 'No se pudo iniciar la vigilancia: $e';
    publicar();
    await alarma.detener();
    await servicio.stopSelf();
  }
}
