/// Cada escenario va en su propio archivo: el reconocedor es un singleton
/// que registra su canal una sola vez por proceso de pruebas.
library;

import 'dart:async';

import 'package:centinela/widgets/dictado_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';

void _servicioPrueba(ServiceInstance servicio) {}

/// Abre la hoja de dictado sin el servicio de vigilancia y simula el plugin.
/// `locales` nunca responde, como pasa en Android 13+ sin reconocimiento en
/// el dispositivo.
Future<List<String>> abrirDictado(
  WidgetTester tester, {
  Future<void> Function(Future<void> Function(String, Object) evento)? luego,
}) async {
  const servicio = MethodChannel(
    'id.flutter/background_service/android/method',
    JSONMethodCodec(),
  );
  const voz = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final messenger = tester.binding.defaultBinaryMessenger;
  final idiomas = <String>[];
  messenger.setMockMethodCallHandler(servicio, (call) async {
    if (call.method == 'isServiceRunning') return false;
    return true;
  });
  messenger.setMockMethodCallHandler(voz, (call) async {
    if (call.method == 'locales') return Completer<Object?>().future;
    if (call.method == 'listen') {
      idiomas.add((call.arguments as Map)['localeId'] as String);
    }
    return true;
  });
  FlutterBackgroundServiceAndroid.registerWith();
  await FlutterBackgroundService().configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: _servicioPrueba,
      isForegroundMode: true,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => dictar(context, titulo: 'Prueba', ayuda: 'Habla'),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 6));

  Future<void> evento(String metodo, Object argumento) async {
    final listo = Completer<void>();
    tester.binding.channelBuffers.push(
      voz.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(metodo, argumento),
      ),
      (_) => listo.complete(),
    );
    await listo.future;
    await tester.pump();
  }

  await luego?.call(evento);
  await tester.tap(find.text('Cancelar'));
  await tester.pump(const Duration(seconds: 3));
  messenger.setMockMethodCallHandler(voz, null);
  messenger.setMockMethodCallHandler(servicio, null);
  return idiomas;
}
