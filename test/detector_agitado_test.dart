import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/services/detector_agitado.dart';

void main() {
  bool impulso(DetectorAgitado detector, int ms) {
    detector.agregar(9.8, Duration(milliseconds: ms - 1));
    return detector.agregar(20, Duration(milliseconds: ms));
  }

  test('Tres impulsos rítmicos activan una sola alarma', () {
    final detector = DetectorAgitado();
    expect(impulso(detector, 100), isFalse);
    expect(impulso(detector, 400), isFalse);
    expect(impulso(detector, 700), isTrue);
    expect(impulso(detector, 1000), isFalse);
  });
  test('Un golpe sostenido no cuenta como varios movimientos', () {
    final detector = DetectorAgitado();
    for (var ms = 0; ms < 2000; ms += 100) {
      expect(detector.agregar(20, Duration(milliseconds: ms)), isFalse);
    }
  });
  test('Movimientos separados no se acumulan', () {
    final detector = DetectorAgitado();
    for (var ms = 100; ms < 5000; ms += 1000) {
      expect(impulso(detector, ms), isFalse);
    }
  });
  test('Reanudar descarta los movimientos anteriores', () {
    final detector = DetectorAgitado();
    impulso(detector, 100);
    impulso(detector, 400);
    detector.resetear();
    expect(impulso(detector, 700), isFalse);
  });
  test('Vibraciones muy rápidas no disparan la alarma', () {
    final detector = DetectorAgitado();
    expect(impulso(detector, 100), isFalse);
    expect(impulso(detector, 120), isFalse);
    expect(impulso(detector, 140), isFalse);
  });
}
