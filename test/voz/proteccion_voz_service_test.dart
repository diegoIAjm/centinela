import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centinela/models/configuracion_voz.dart';
import 'package:centinela/services/voz/configuracion_voz_store.dart';
import 'package:centinela/services/voz/motor_voz.dart';
import 'package:centinela/services/voz/proteccion_voz_service.dart';

class MotorFalso implements MotorVoz {
  final canal = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  bool escuchando = false;
  bool despierto = false;
  bool fallar = false;
  bool fallarDetencion = false;
  int inicios = 0;
  @override
  Stream<Map<String, dynamic>> get eventos => canal.stream;
  @override
  Future<void> iniciar() async {
    if (fallar) throw StateError('Sin modelo');
    escuchando = true;
    inicios++;
  }

  @override
  Future<void> detener() async {
    if (fallarDetencion) throw StateError('Micrófono bloqueado');
    escuchando = false;
  }

  @override
  Future<void> mantenerServicio(bool mantener) async {
    despierto = mantener;
  }

  void decir(String texto) => canal.add({'tipo': 'texto', 'texto': texto});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime ahora;
  late MotorFalso motor;
  late ProteccionVozService voz;
  late int alarmas;
  Future<void> guardar({bool prueba = true, bool habilitada = true}) async {
    await ConfiguracionVozStore().guardar(
      ConfiguracionVoz(habilitada: habilitada, modoPrueba: prueba),
    );
    await voz.recargar();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      ConfiguracionVozStore.clave: jsonEncode(
        const ConfiguracionVoz(habilitada: true).toMap(),
      ),
    });
    ahora = DateTime(2026, 10, 20, 6, 59);
    motor = MotorFalso();
    alarmas = 0;
    voz = ProteccionVozService(
      motor: motor,
      activarAlarma: () async {
        alarmas++;
      },
      alCambiar: () {},
      reloj: () => ahora,
    );
  });
  tearDown(() async {
    await voz.cerrar();
    await motor.canal.close();
  });

  test(
    'Servicio armado espera, inicia a las 7 y libera micrófono a las 12',
    () async {
      await voz.iniciar();
      await voz.disponible(true);
      expect(voz.estado, 'esperando');
      expect(motor.escuchando, isFalse);
      ahora = DateTime(2026, 10, 20, 7);
      await voz.evaluar();
      expect(motor.escuchando, isTrue);
      expect(voz.estado, 'escuchando');
      await voz.evaluar();
      expect(motor.inicios, 1);
      ahora = DateTime(2026, 10, 20, 12);
      await voz.evaluar();
      expect(motor.escuchando, isFalse);
      expect(voz.estado, 'esperando');
    },
  );
  test(
    'Prueba detecta frase pero nunca activa alarma; deduplica resultados',
    () async {
      ahora = DateTime(2026, 10, 20, 8);
      await voz.iniciar();
      await voz.disponible(true);
      motor.decir('centinela necesito ayuda');
      motor.decir('centinela necesito ayuda');
      expect(voz.ultimaDeteccion, 'centinela necesito ayuda');
      expect(alarmas, 0);
    },
  );
  test(
    'Real activa una vez, no acepta texto fuera del horario ni al pausar',
    () async {
      ahora = DateTime(2026, 10, 20, 8);
      await voz.iniciar();
      await guardar(prueba: false);
      await voz.disponible(true);
      motor.decir('centinela necesito ayuda');
      motor.decir('centinela necesito ayuda');
      await Future<void>.delayed(Duration.zero);
      expect(alarmas, 1);
      ahora = DateTime(2026, 10, 20, 12);
      motor.decir('centinela necesito ayuda');
      expect(alarmas, 1);
      ahora = DateTime(2026, 10, 21, 8);
      await voz.disponible(false);
      motor.decir('centinela necesito ayuda');
      expect(alarmas, 1);
      expect(motor.escuchando, isFalse);
      expect(motor.despierto, isFalse);
    },
  );
  test('Recargar deshabilitada libera micrófono y wake lock', () async {
    ahora = DateTime(2026, 10, 20, 8);
    await voz.iniciar();
    await voz.disponible(true);
    await guardar(habilitada: false);
    expect(voz.estado, 'desactivada');
    expect(motor.despierto, isFalse);
    expect(motor.escuchando, isFalse);
  });
  test('Dictado pausa y reanuda; la reserva caduca', () async {
    ahora = DateTime(2026, 10, 20, 8);
    await voz.iniciar();
    await voz.disponible(true);
    await voz.dictado(true);
    expect(voz.estado, 'dictado');
    expect(motor.escuchando, isFalse);
    motor.decir('centinela necesito ayuda');
    expect(voz.ultimaDeteccion, isNull);
    await voz.dictado(false);
    expect(motor.escuchando, isTrue);
    await voz.dictado(true);
    ahora = ahora.add(const Duration(minutes: 4));
    await voz.evaluar();
    expect(motor.escuchando, isTrue);
  });
  test(
    'Error de motor visible; no anuncia escucha y reintento explícito',
    () async {
      ahora = DateTime(2026, 10, 20, 8);
      motor.fallar = true;
      await voz.iniciar();
      await voz.disponible(true);
      expect(voz.estado, 'error');
      expect(voz.error, contains('Sin modelo'));
      await voz.evaluar();
      expect(motor.despierto, isFalse);
      motor.fallar = false;
      await voz.recargar();
      expect(voz.estado, 'escuchando');
      expect(voz.error, isNull);
    },
  );
  test('Configuración corrupta falla cerrada, sin escucha', () async {
    SharedPreferences.setMockInitialValues({
      ConfiguracionVozStore.clave: '{roto',
    });
    await voz.iniciar();
    await voz.disponible(true);
    expect(voz.estado, 'error');
    expect(motor.escuchando, isFalse);
  });
  test(
    'La alarma espera a que voz libere el micrófono sin bloquear la cola',
    () async {
      ahora = DateTime(2026, 10, 20, 8);
      await voz.iniciar();
      await guardar(prueba: false);
      await voz.disponible(true);
      final fin = Completer<void>();
      // Usar el controlador real con una alarma que vuelve a entrar en su cola.
      await voz.cerrar();
      voz = ProteccionVozService(
        motor: motor,
        activarAlarma: () async {
          await voz.disponible(false);
          expect(motor.escuchando, isFalse);
          fin.complete();
        },
        alCambiar: () {},
        reloj: () => ahora,
      );
      await voz.iniciar();
      await voz.disponible(true);
      motor.decir('centinela necesito ayuda');
      await fin.future.timeout(const Duration(seconds: 2));
      expect(voz.estado, 'suspendida');
    },
  );
  test(
    'No entrega el micrófono al grabador o dictado si detener falló',
    () async {
      ahora = DateTime(2026, 10, 20, 8);
      await voz.iniciar();
      await voz.disponible(true);
      motor.fallarDetencion = true;
      await expectLater(voz.disponible(false), throwsStateError);
      expect(voz.estado, 'error');
      await expectLater(voz.dictado(true), throwsStateError);
      motor.fallarDetencion = false;
    },
  );
}
