import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:centinela/screens/configuracion_voz_screen.dart';
import 'package:centinela/services/voz/configuracion_voz_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const servicio = MethodChannel(
    'id.flutter/background_service/android/method',
    JSONMethodCodec(),
  );
  const motor = MethodChannel('centinela_voz');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterBackgroundServiceAndroid.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          servicio,
          (call) async => call.method == 'isServiceRunning' ? false : true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          motor,
          (call) async => call.method == 'modeloDisponible' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(servicio, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(motor, null);
  });
  testWidgets(
    'Configura y guarda un horario diario a 360 px sin desbordamiento',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: ConfiguracionVozScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNWidgets(7));
      expect(find.text('Desde 07:00'), findsOneWidget);
      expect(find.text('Hasta 12:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guardar cambios'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Guardar cambios')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      final guardada = await ConfiguracionVozStore().cargar();
      expect(guardada.habilitada, isTrue);
      expect(guardada.modoPrueba, isTrue);
      expect(guardada.dias, [1, 2, 3, 4, 5, 6, 7]);
      expect(guardada.inicioMinutos, 420);
      expect(guardada.finMinutos, 720);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
