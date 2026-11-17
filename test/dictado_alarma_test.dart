import 'dart:async';
import 'dart:convert';

import 'package:centinela/widgets/dictado_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';

void _servicioPrueba(ServiceInstance servicio) {}

void main() {
  testWidgets(
    'Alarma cancela dictado, conserva parcial y no cierra la alarma',
    (tester) async {
      const servicio = MethodChannel(
        'id.flutter/background_service/android/method',
        JSONMethodCodec(),
      );
      const eventos = MethodChannel(
        'id.flutter/background_service/android/event',
        JSONMethodCodec(),
      );
      const voz = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final messenger = tester.binding.defaultBinaryMessenger;
      final operaciones = <String>[];
      String? id;
      String? textoFormulario;

      Future<void> enviar(MethodChannel canal, MethodCall llamada) async {
        final listo = Completer<void>();
        tester.binding.channelBuffers.push(
          canal.name,
          canal.codec.encodeMethodCall(llamada),
          (_) => listo.complete(),
        );
        await listo.future;
      }

      messenger.setMockMethodCallHandler(eventos, (_) async => null);
      messenger.setMockMethodCallHandler(servicio, (call) async {
        if (call.method == 'isServiceRunning') return true;
        if (call.method == 'sendData') {
          final datos = Map<String, dynamic>.from(call.arguments as Map);
          final metodo = datos['method'] as String;
          operaciones.add(metodo);
          if (metodo == 'reservarVozDictado') {
            id = datos['args']['id'] as String;
            await enviar(
              servicio,
              MethodCall('onReceiveData', {
                'method': 'vozDictadoReservada',
                'args': {'id': id, 'ok': true},
              }),
            );
          }
          if (metodo == 'dictadoCancelado') {
            expect(datos['args']['ok'], isTrue);
          }
        }
        return true;
      });
      messenger.setMockMethodCallHandler(voz, (call) async {
        operaciones.add('voz:${call.method}');
        if (call.method == 'locales') return ['es_ES:Español'];
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

      final navegador = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navegador,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  textoFormulario = await dictar(
                    context,
                    titulo: 'Dictado',
                    ayuda: 'Relato',
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await enviar(
        voz,
        MethodCall(
          'textRecognition',
          jsonEncode({
            'alternates': [
              {
                'recognizedWords': 'Texto parcial conservado',
                'confidence': 1.0,
              },
            ],
            'resultType': 0,
          }),
        ),
      );
      await tester.pump();
      expect(find.text('Texto parcial conservado'), findsOneWidget);

      unawaited(
        navegador.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('ALARMA ACTIVA')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await enviar(
        servicio,
        MethodCall('onReceiveData', {
          'method': 'cancelarDictado',
          'args': {'id': id},
        }),
      );
      await tester.pumpAndSettle();
      await tester.pump();
      expect(textoFormulario, 'Texto parcial conservado');
      expect(find.text('ALARMA ACTIVA'), findsOneWidget);
      expect(
        operaciones.indexOf('voz:cancel'),
        lessThan(operaciones.indexOf('dictadoCancelado')),
      );
      expect(operaciones, contains('liberarVozDictado'));
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(voz, null);
      messenger.setMockMethodCallHandler(servicio, null);
      messenger.setMockMethodCallHandler(eventos, null);
    },
  );
}
