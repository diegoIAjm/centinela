import 'dart:async';
import 'dart:convert';

import 'package:centinela/services/voice_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Palabras completas, acentos, mayúsculas y frases', () {
    const config = ConfigVoz(
      palabras: ['policia', 'ayuda', 'estoy en peligro'],
    );
    expect(config.detectarPalabra('¡POLICÍA, por favor!'), 'policia');
    expect(config.detectarPalabra('Necesito ayuda.'), 'ayuda');
    expect(
      config.detectarPalabra('Estoy en peligro ahora'),
      'estoy en peligro',
    );
    expect(config.detectarPalabra('El ayudante llegó'), isNull);
    expect(config.detectarPalabra('Sin coincidencias'), isNull);
  });

  test('Palabras censuradas por Android', () {
    const config = ConfigVoz(palabras: ['puta', 'ayuda']);
    expect(config.detectarPalabra('eres una P***'), 'puta');
    expect(config.detectarPalabra('p***'), 'puta');
    const frase = ConfigVoz(palabras: ['hijo de puta']);
    expect(frase.detectarPalabra('hijo de p***'), 'hijo de puta');
    expect(frase.detectarPalabra('p***'), isNull);
    // Otra longitud, otra letra o sin letra visible no coinciden.
    expect(config.detectarPalabra('p*****'), isNull);
    expect(config.detectarPalabra('m***'), isNull);
    expect(config.detectarPalabra('****'), isNull);
  });

  test('Añade las palabras nuevas una vez, sin revivir las borradas', () async {
    SharedPreferences.setMockInitialValues({
      ConfigVoz.clave: jsonEncode({
        'palabras': ['mi frase'],
      }),
    });
    final migrada = await ConfigVoz.cargar();
    expect(migrada.palabras, containsAll(['mi frase', 'ayuda', 'idiota']));

    await const ConfigVoz(palabras: ['mi frase']).guardar();
    expect((await ConfigVoz.cargar()).palabras, ['mi frase']);
  });

  group('Palabras y volumen son independientes', () {
    Future<List<String>> probar(
      WidgetTester tester, {
      required bool decibelios,
      required bool palabras,
      required Future<void> Function(
        Future<void> Function(String metodo, Object argumento) evento,
        void Function(Duration) avanzar,
      )
      acciones,
    }) async {
      SharedPreferences.setMockInitialValues({
        ConfigVoz.clave: jsonEncode({
          'decibelios': decibelios,
          'palabrasActivas': palabras,
          'umbral': 7,
          'palabras': ['idiota'],
          'versionPalabras': 2,
        }),
      });
      const canal = MethodChannel('plugin.csdcorp.com/speech_to_text');
      const permisos = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permisos, (_) async => 1);
      messenger.setMockMethodCallHandler(canal, (_) async => true);
      var ahora = DateTime(2026);
      final voz = VoiceService.paraPruebas(
        SpeechToText.withMethodChannel(),
        ahora: () => ahora,
      );
      final amenazas = <String>[];
      voz.onAmenazaVoz = amenazas.add;
      await voz.iniciar();
      Future<void> evento(String metodo, Object argumento) async {
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

      // Sin este estado el plugin descarta los niveles de sonido.
      await evento('notifyStatus', 'listening');
      await acciones(evento, (duracion) => ahora = ahora.add(duracion));
      await voz.detener();
      messenger.setMockMethodCallHandler(canal, null);
      messenger.setMockMethodCallHandler(permisos, null);
      return amenazas;
    }

    // resultType 0 = parcial; confidence -1 = el motor no da puntuación.
    String resultado(String texto, {int tipo = 0, double confianza = -1}) =>
        jsonEncode({
          'alternates': [
            {'recognizedWords': texto, 'confidence': confianza},
          ],
          'resultType': tipo,
        });

    testWidgets('Palabra parcial sin puntuación activa la alarma', (
      tester,
    ) async {
      final amenazas = await probar(
        tester,
        decibelios: false,
        palabras: true,
        acciones: (evento, _) async {
          await evento('textRecognition', resultado('hola que tal'));
          await evento('textRecognition', resultado('eres un idiota'));
        },
      );
      expect(amenazas, ['Palabra clave: idiota']);
    });

    testWidgets('Palabra final con confianza baja o nula activa la alarma', (
      tester,
    ) async {
      final amenazas = await probar(
        tester,
        decibelios: false,
        palabras: true,
        acciones: (evento, _) => evento(
          'textRecognition',
          resultado('idiota', tipo: 2, confianza: 0),
        ),
      );
      expect(amenazas, ['Palabra clave: idiota']);
    });

    testWidgets('Solo volumen: las palabras no activan, el volumen sí', (
      tester,
    ) async {
      final amenazas = await probar(
        tester,
        decibelios: true,
        palabras: false,
        acciones: (evento, avanzar) async {
          await evento('textRecognition', resultado('idiota', tipo: 2));
          await evento('soundLevelChange', 8.0);
          avanzar(const Duration(milliseconds: 500));
          await evento('soundLevelChange', 8.0);
        },
      );
      expect(amenazas, ['Nivel alto: 8.0']);
    });

    testWidgets('Solo palabras: el volumen no activa', (tester) async {
      final amenazas = await probar(
        tester,
        decibelios: false,
        palabras: true,
        acciones: (evento, avanzar) async {
          await evento('soundLevelChange', 15.0);
          avanzar(const Duration(seconds: 2));
          await evento('soundLevelChange', 15.0);
        },
      );
      expect(amenazas, isEmpty);
    });

    testWidgets('Ambos activos: dispara una sola vez', (tester) async {
      final amenazas = await probar(
        tester,
        decibelios: true,
        palabras: true,
        acciones: (evento, avanzar) async {
          await evento('textRecognition', resultado('idiota'));
          await evento('soundLevelChange', 8.0);
          avanzar(const Duration(seconds: 1));
          await evento('soundLevelChange', 8.0);
        },
      );
      expect(amenazas, ['Palabra clave: idiota']);
    });
  });

  test('Persiste los dos modos, umbral y lista vacía', () async {
    SharedPreferences.setMockInitialValues({});
    await const ConfigVoz(
      decibelios: true,
      palabrasActivas: false,
      umbral: 19.5,
      palabras: [],
    ).guardar();
    final config = await ConfigVoz.cargar();
    expect(config.decibelios, isTrue);
    expect(config.palabrasActivas, isFalse);
    expect(config.umbral, 19.5);
    expect(config.palabras, isEmpty);
  });

  testWidgets('Reserva, pausa, dictado, callbacks tardíos y reintento', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      ConfigVoz.clave: jsonEncode({
        'decibelios': true,
        'palabrasActivas': true,
        'umbral': 7,
        'palabras': ['ayuda'],
      }),
    });
    const canal = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const permisos = MethodChannel('flutter.baseflow.com/permissions/methods');
    final llamadas = <String>[];
    var motorDisponible = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permisos, (_) async => 1);
    messenger.setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call.method);
      if (call.method == 'initialize') return motorDisponible;
      return true;
    });
    Future<void> evento(String metodo, Object argumento) async {
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

    var ahora = DateTime(2026);
    final voz = VoiceService.paraPruebas(
      SpeechToText.withMethodChannel(),
      ahora: () => ahora,
    );
    final amenazas = <String>[];
    voz.onAmenazaVoz = amenazas.add;
    await voz.iniciar();
    expect(voz.conError, isTrue);
    expect(llamadas.where((m) => m == 'listen'), isEmpty);
    motorDisponible = true;
    await tester.pump(const Duration(seconds: 3));
    expect(llamadas.where((m) => m == 'listen').length, 1);
    await evento('notifyStatus', 'listening');
    expect(voz.estado, 'escuchando');
    expect(voz.conError, isFalse);
    await evento('soundLevelChange', 8.0);
    expect(amenazas, isEmpty);
    ahora = ahora.add(const Duration(milliseconds: 499));
    await tester.pump(const Duration(milliseconds: 499));
    await evento('soundLevelChange', 8.0);
    expect(amenazas, isEmpty);
    // Bajar del umbral descarta el tiempo acumulado.
    await evento('soundLevelChange', 6.0);
    await evento('soundLevelChange', 8.0);
    ahora = ahora.add(const Duration(milliseconds: 499));
    await tester.pump(const Duration(milliseconds: 499));
    await evento('soundLevelChange', 8.0);
    expect(amenazas, isEmpty);
    ahora = ahora.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await evento('soundLevelChange', 8.0);
    expect(amenazas, hasLength(1));
    await voz.reservarMicrofonoParaGrabacion();
    await voz.reanudar(); // La reserva del PIN falso tiene prioridad.
    await evento('soundLevelChange', 9.0);
    await voz.actualizarConfiguracion();
    await tester.pump(const Duration(seconds: 10));
    expect(llamadas.where((m) => m == 'listen').length, 1);
    expect(amenazas, hasLength(1));

    await voz.liberarMicrofonoDeGrabacion();
    expect(llamadas.where((m) => m == 'listen').length, 2);
    await voz.pausar();
    await voz.actualizarConfiguracion();
    await tester.pump(const Duration(seconds: 10));
    expect(llamadas.where((m) => m == 'listen').length, 2);
    await voz.reanudar();
    expect(llamadas.where((m) => m == 'listen').length, 3);

    await voz.reservarParaDictado(true);
    await tester.pump(const Duration(seconds: 10));
    expect(llamadas.where((m) => m == 'listen').length, 3);
    await voz.reservarParaDictado(false);
    expect(llamadas.where((m) => m == 'listen').length, 4);

    await evento('notifyStatus', 'notListening');
    await tester.pump(const Duration(seconds: 2));
    expect(llamadas.where((m) => m == 'listen').length, 4);
    await tester.pump(const Duration(seconds: 1));
    expect(llamadas.where((m) => m == 'listen').length, 5);
    await evento(
      'notifyError',
      jsonEncode({'errorMsg': 'error_network', 'permanent': true}),
    );
    expect(voz.conError, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(llamadas.where((m) => m == 'listen').length, 6);
    await voz.detener();
    await tester.pump(const Duration(seconds: 10));
    expect(llamadas.where((m) => m == 'listen').length, 6);
    messenger.setMockMethodCallHandler(canal, null);
    messenger.setMockMethodCallHandler(permisos, null);
  });

  testWidgets('Timeouts de listen y cancel no bloquean la cola', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      ConfigVoz.clave: jsonEncode({'decibelios': true}),
    });
    const canal = MethodChannel('plugin.csdcorp.com/speech_to_text');
    const permisos = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger = tester.binding.defaultBinaryMessenger;
    var bloquearListen = true;
    var bloquearCancel = false;
    var escuchas = 0;
    messenger.setMockMethodCallHandler(permisos, (_) async => 1);
    messenger.setMockMethodCallHandler(canal, (call) async {
      if (call.method == 'listen') {
        escuchas++;
        if (bloquearListen) return Completer<bool>().future;
      }
      if (call.method == 'cancel' && bloquearCancel) {
        return Completer<bool>().future;
      }
      return true;
    });
    final voz = VoiceService.paraPruebas(SpeechToText.withMethodChannel());
    var iniciado = false;
    final inicio = voz.iniciar().then((_) => iniciado = true);
    for (var i = 0; i < 15 && !iniciado; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      iniciado,
      isTrue,
      reason: 'listen debe terminar incluso sin respuesta nativa',
    );
    await inicio;
    expect(voz.conError, isTrue);
    bloquearListen = false;
    await tester.pump(const Duration(seconds: 3));
    expect(escuchas, 2);

    bloquearCancel = true;
    final pausa = expectLater(voz.pausar(), throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await pausa;
    bloquearCancel = false;
    await voz.reanudar();
    expect(escuchas, 3);
    await voz.detener();
    messenger.setMockMethodCallHandler(canal, null);
    messenger.setMockMethodCallHandler(permisos, null);
  });
}
