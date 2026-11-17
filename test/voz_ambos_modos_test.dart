import 'dart:async';
import 'dart:convert';

import 'package:centinela/services/voice_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Simula el canal nativo del reconocedor con ambos modos configurables.
class _Banco {
  _Banco(this.tester);

  final WidgetTester tester;
  static const canal = MethodChannel('plugin.csdcorp.com/speech_to_text');
  static const permisos = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  final amenazas = <String>[];
  var escuchas = 0;
  var ahora = DateTime(2026);
  late VoiceService voz;

  static Map<String, Object> config({
    required bool decibelios,
    required bool palabras,
  }) => {
    'decibelios': decibelios,
    'palabrasActivas': palabras,
    'umbral': 7,
    'palabras': ['idiota', 'te voy a matar'],
    'versionPalabras': 2,
  };

  Future<void> iniciar({bool decibelios = true, bool palabras = true}) async {
    SharedPreferences.setMockInitialValues({
      ConfigVoz.clave: jsonEncode(
        config(decibelios: decibelios, palabras: palabras),
      ),
    });
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permisos, (_) async => 1);
    messenger.setMockMethodCallHandler(canal, (llamada) async {
      if (llamada.method == 'listen') escuchas++;
      return true;
    });
    voz = VoiceService.paraPruebas(
      SpeechToText.withMethodChannel(),
      ahora: () => ahora,
    );
    voz.onAmenazaVoz = amenazas.add;
    await voz.iniciar();
    await estado('listening');
  }

  Future<void> terminar() async {
    await voz.detener();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(canal, null);
    messenger.setMockMethodCallHandler(permisos, null);
  }

  Future<void> _evento(String metodo, Object argumento) async {
    final fin = Completer<void>();
    tester.binding.channelBuffers.push(
      canal.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(metodo, argumento),
      ),
      (_) => fin.complete(),
    );
    await fin.future;
  }

  Future<void> estado(String valor) => _evento('notifyStatus', valor);

  Future<void> nivel(double valor) => _evento('soundLevelChange', valor);

  Future<void> error(String mensaje) => _evento(
    'notifyError',
    jsonEncode({'errorMsg': mensaje, 'permanent': true}),
  );

  /// tipo 0 = parcial, 2 = final; confianza -1 = el motor no la informa.
  Future<void> texto(String palabras, {int tipo = 0}) => _evento(
    'textRecognition',
    jsonEncode({
      'alternates': [
        {'recognizedWords': palabras, 'confidence': -1},
      ],
      'resultType': tipo,
    }),
  );

  /// Grito sostenido: un nivel cada 100 ms durante [milisegundos].
  Future<void> grito(int milisegundos, {double valor = 9}) async {
    for (var t = 0; t <= milisegundos; t += 100) {
      await nivel(valor);
      ahora = ahora.add(const Duration(milliseconds: 100));
    }
  }

  /// Mismo ciclo que hace AlarmaService al activar y cancelar una alarma.
  Future<void> cicloDeAlarma() async {
    await voz.reservarMicrofonoParaGrabacion();
    await voz.liberarMicrofonoDeGrabacion();
    await estado('listening');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ambos modos activos', () {
    testWidgets('Palabra dicha en voz baja activa', (tester) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.nivel(3);
      await b.texto('eres un idiota');
      expect(b.amenazas, ['Palabra clave: idiota']);
      await b.terminar();
    });

    testWidgets('Grito sin palabra clave activa', (tester) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.grito(600);
      expect(b.amenazas, hasLength(1));
      expect(b.amenazas.single, startsWith('Nivel alto'));
      await b.terminar();
    });

    testWidgets('Grito con texto sin palabra clave de por medio activa', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.nivel(9);
      await b.texto('hola');
      b.ahora = b.ahora.add(const Duration(milliseconds: 300));
      await b.nivel(9);
      await b.texto('hola como estas');
      b.ahora = b.ahora.add(const Duration(milliseconds: 300));
      await b.nivel(9);
      expect(b.amenazas, hasLength(1));
      expect(b.amenazas.single, startsWith('Nivel alto'));
      await b.terminar();
    });

    testWidgets('Palabra a media subida de volumen activa una sola vez', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.nivel(9);
      b.ahora = b.ahora.add(const Duration(milliseconds: 200));
      await b.texto('te voy a matar');
      b.ahora = b.ahora.add(const Duration(seconds: 1));
      await b.nivel(9);
      expect(b.amenazas, ['Palabra clave: te voy a matar']);
      await b.terminar();
    });

    testWidgets('Tras una alarma por palabra, el volumen vuelve a activar', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.texto('idiota');
      await b.cicloDeAlarma();
      await b.grito(600);
      expect(b.amenazas, hasLength(2));
      expect(b.amenazas.last, startsWith('Nivel alto'));
      await b.terminar();
    });

    testWidgets('Tras una alarma por volumen, la palabra vuelve a activar', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.grito(600);
      await b.cicloDeAlarma();
      await b.texto('idiota');
      expect(b.amenazas, hasLength(2));
      expect(b.amenazas.last, 'Palabra clave: idiota');
      await b.terminar();
    });

    testWidgets('Tras reiniciar la sesión funcionan los dos', (tester) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.texto('nada importante', tipo: 2);
      await b.estado('done');
      await tester.pump(const Duration(seconds: 3));
      expect(b.escuchas, 2);
      await b.estado('listening');
      await b.texto('idiota');
      expect(b.amenazas, ['Palabra clave: idiota']);
      await b.cicloDeAlarma();
      await b.texto('nada importante', tipo: 2);
      await b.estado('done');
      await tester.pump(const Duration(seconds: 3));
      await b.estado('listening');
      await b.grito(600);
      expect(b.amenazas, hasLength(2));
      expect(b.amenazas.last, startsWith('Nivel alto'));
      await b.terminar();
    });
  });

  group('Reinicio de la escucha', () {
    for (final mensaje in ['error_speech_timeout', 'error_no_match']) {
      testWidgets('$mensaje reinicia rápido y no cuenta como error', (
        tester,
      ) async {
        final b = _Banco(tester);
        await b.iniciar();
        await b.estado('notListening');
        await b.estado('doneNoResult');
        await b.error(mensaje);
        expect(b.voz.conError, isFalse);
        expect(b.escuchas, 1);
        await tester.pump(const Duration(milliseconds: 499));
        expect(b.escuchas, 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(b.escuchas, 2);
        await b.terminar();
      });
    }

    for (final errorPrimero in [true, false]) {
      testWidgets(
        'Un error real espera 3 s (error ${errorPrimero ? 'antes' : 'después'} '
        'de done)',
        (tester) async {
          final b = _Banco(tester);
          await b.iniciar();
          if (errorPrimero) await b.error('error_network');
          await b.estado('doneNoResult');
          if (!errorPrimero) await b.error('error_network');
          expect(b.voz.conError, isTrue);
          await tester.pump(const Duration(milliseconds: 2999));
          expect(b.escuchas, 1);
          await tester.pump(const Duration(milliseconds: 1));
          expect(b.escuchas, 2);
          await b.terminar();
        },
      );
    }

    testWidgets('Tras recuperarse de un error vuelve al reinicio rápido', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.error('error_network');
      await tester.pump(const Duration(seconds: 3));
      expect(b.escuchas, 2);
      await b.estado('listening');
      expect(b.voz.conError, isFalse);
      await b.estado('doneNoResult');
      await tester.pump(const Duration(milliseconds: 500));
      expect(b.escuchas, 3);
      await b.terminar();
    });

    testWidgets('notListening espera a done para no perder el resultado', (
      tester,
    ) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.estado('notListening');
      await tester.pump(const Duration(seconds: 1));
      expect(b.escuchas, 1);
      await b.estado('doneNoResult');
      await tester.pump(const Duration(milliseconds: 500));
      expect(b.escuchas, 2);
      await b.terminar();
    });

    testWidgets('No reinicia con el micrófono reservado', (tester) async {
      final b = _Banco(tester);
      await b.iniciar();
      await b.estado('doneNoResult');
      await b.voz.reservarMicrofonoParaGrabacion();
      await tester.pump(const Duration(seconds: 5));
      expect(b.escuchas, 1);
      await b.voz.liberarMicrofonoDeGrabacion();
      expect(b.escuchas, 2);
      await b.terminar();
    });
  });

  group('Cambiar la configuración sin reiniciar el servicio', () {
    Future<void> cambiar(_Banco b, bool decibelios, bool palabras) async {
      await ConfigVoz(
        decibelios: decibelios,
        palabrasActivas: palabras,
        umbral: 7,
        palabras: const ['idiota'],
      ).guardar();
      await b.voz.actualizarConfiguracion();
      await b.estado('listening');
    }

    testWidgets('De solo palabras a ambos: los dos activan', (tester) async {
      final b = _Banco(tester);
      await b.iniciar(decibelios: false);
      await b.grito(600);
      expect(b.amenazas, isEmpty);
      await cambiar(b, true, true);
      await b.grito(600);
      expect(b.amenazas.single, startsWith('Nivel alto'));
      await b.cicloDeAlarma();
      await b.texto('idiota');
      expect(b.amenazas.last, 'Palabra clave: idiota');
      await b.terminar();
    });

    testWidgets('De solo volumen a ambos: los dos activan', (tester) async {
      final b = _Banco(tester);
      await b.iniciar(palabras: false);
      await b.texto('idiota');
      expect(b.amenazas, isEmpty);
      await cambiar(b, true, true);
      await b.texto('idiota');
      expect(b.amenazas, ['Palabra clave: idiota']);
      await b.cicloDeAlarma();
      await b.grito(600);
      expect(b.amenazas.last, startsWith('Nivel alto'));
      await b.terminar();
    });
  });
}
