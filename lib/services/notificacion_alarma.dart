import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const idNotificacionAlarma = 999;
const payloadAlarma = 'alarma_activa';
const _canalAlarma = 'centinela_alarma_critica';

final _plugin = FlutterLocalNotificationsPlugin();
bool _iniciado = false;

/// Inicializa el plugin en el isolate actual. En la UI se pasa [alTocar] para
/// navegar a la alarma; en el servicio basta con poder mostrar/cancelar.
Future<NotificationAppLaunchDetails?> iniciarNotificaciones({
  void Function(NotificationResponse)? alTocar,
}) async {
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: alTocar,
  );
  _iniciado = true;
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _canalAlarma,
          'Alarma crítica',
          description: 'Muestra la alarma sobre la pantalla de bloqueo',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
  return _plugin.getNotificationAppLaunchDetails();
}

bool abiertaPorAlarma(NotificationAppLaunchDetails? detalles) =>
    detalles?.didNotificationLaunchApp == true &&
    detalles?.notificationResponse?.payload == payloadAlarma;

/// En Android 14+ el full-screen intent es un permiso especial: si falta,
/// se abre su pantalla de ajustes. En versiones anteriores devuelve true.
Future<bool> solicitarPermisoPantallaCompleta() async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  return await android?.requestFullScreenIntentPermission() ?? false;
}

Future<void> mostrarNotificacionAlarma() async {
  try {
    if (!_iniciado) await iniciarNotificaciones();
    await _plugin.show(
      id: idNotificacionAlarma,
      title: '🚨 ALERTA CENTINELA',
      body: 'Desliza para ver y cancelar',
      payload: payloadAlarma,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _canalAlarma,
          'Alarma crítica',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ No se pudo mostrar la notificación de alarma: $e');
  }
}

Future<void> cancelarNotificacionAlarma() async {
  try {
    if (!_iniciado) await iniciarNotificaciones();
    await _plugin.cancel(id: idNotificacionAlarma);
  } catch (e) {
    debugPrint('❌ No se pudo quitar la notificación de alarma: $e');
  }
}
