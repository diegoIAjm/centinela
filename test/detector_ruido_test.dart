import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/services/detector_ruido.dart';

void main() {
  Duration ms(int valor) => Duration(milliseconds: valor);

  test('Un golpe aislado no activa la alarma', () {
    final detector = DetectorRuido();
    expect(detector.agregar(true, ms(0)), isFalse);
    expect(detector.agregar(true, ms(100)), isFalse);
    for (var t = 200; t < 3000; t += 100) {
      expect(detector.agregar(false, ms(t)), isFalse);
    }
  });
  test('Ruido sostenido 1,5 s activa una sola vez', () {
    final detector = DetectorRuido();
    var activaciones = 0;
    for (var t = 0; t <= 1600; t += 100) {
      if (detector.agregar(true, ms(t))) activaciones++;
    }
    expect(activaciones, 1);
  });
  test('Pausas breves no reinician la cuenta', () {
    final detector = DetectorRuido();
    for (var t = 0; t <= 600; t += 100) {
      expect(detector.agregar(true, ms(t)), isFalse);
    }
    expect(detector.agregar(false, ms(700)), isFalse);
    for (var t = 900; t < 1500; t += 100) {
      expect(detector.agregar(true, ms(t)), isFalse);
    }
    expect(detector.agregar(true, ms(1500)), isTrue);
  });
  test('Una pausa larga reinicia la cuenta', () {
    final detector = DetectorRuido();
    expect(detector.agregar(true, ms(0)), isFalse);
    expect(detector.agregar(true, ms(1000)), isFalse);
    expect(detector.agregar(false, ms(1500)), isFalse);
    expect(detector.agregar(true, ms(1600)), isFalse);
    expect(detector.agregar(true, ms(2000)), isFalse);
  });
}
