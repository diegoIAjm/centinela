import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/models/configuracion_voz.dart';

void main() {
  const diario = ConfiguracionVoz(habilitada: true);
  test('07:00 inclusivo y 12:00 exclusivo', () {
    expect(diario.contiene(DateTime(2026, 10, 20, 6, 59, 59)), isFalse);
    expect(diario.contiene(DateTime(2026, 10, 20, 7)), isTrue);
    expect(diario.contiene(DateTime(2026, 10, 20, 11, 59, 59)), isTrue);
    expect(diario.contiene(DateTime(2026, 10, 20, 12)), isFalse);
  });
  test('Respeta días y deshabilitación', () {
    const lunes = ConfiguracionVoz(habilitada: true, dias: [1]);
    expect(lunes.contiene(DateTime(2026, 10, 19, 8)), isTrue);
    expect(lunes.contiene(DateTime(2026, 10, 20, 8)), isFalse);
    expect(
      const ConfiguracionVoz().contiene(DateTime(2026, 10, 19, 8)),
      isFalse,
    );
  });
  test(
    'Horario nocturno pertenece al día de inicio, incluso domingo-lunes',
    () {
      const noche = ConfiguracionVoz(
        habilitada: true,
        dias: [7],
        inicioMinutos: 1320,
        finMinutos: 120,
      );
      expect(noche.contiene(DateTime(2026, 10, 18, 21, 59)), isFalse);
      expect(noche.contiene(DateTime(2026, 10, 18, 22)), isTrue);
      expect(noche.contiene(DateTime(2026, 10, 19, 1, 59)), isTrue);
      expect(noche.contiene(DateTime(2026, 10, 19, 2)), isFalse);
      expect(noche.contiene(DateTime(2026, 10, 19, 22)), isFalse);
    },
  );
  test('Inicio a medianoche y fin a medianoche', () {
    const madrugada = ConfiguracionVoz(
      habilitada: true,
      dias: [2],
      inicioMinutos: 0,
      finMinutos: 60,
    );
    const tarde = ConfiguracionVoz(
      habilitada: true,
      dias: [2],
      inicioMinutos: 1380,
      finMinutos: 0,
    );
    expect(madrugada.contiene(DateTime(2026, 10, 20)), isTrue);
    expect(tarde.contiene(DateTime(2026, 10, 20, 23, 59)), isTrue);
    expect(tarde.contiene(DateTime(2026, 10, 21)), isFalse);
  });
  test('Rechaza días, horas y frases inválidas', () {
    for (final c in [
      const ConfiguracionVoz(dias: []),
      const ConfiguracionVoz(dias: [8]),
      const ConfiguracionVoz(inicioMinutos: -1),
      const ConfiguracionVoz(finMinutos: 1440),
      const ConfiguracionVoz(inicioMinutos: 420, finMinutos: 420),
      const ConfiguracionVoz(frases: []),
      const ConfiguracionVoz(frases: ['ayuda']),
      const ConfiguracionVoz(frases: ['Necesito ayuda', 'necesito AYUDA!']),
      ConfiguracionVoz(frases: List.generate(11, (i) => 'necesito ayuda $i')),
    ]) {
      expect(c.error, isNotNull);
    }
  });
  test('Persistencia conserva horario nocturno, días y modo real', () {
    const c = ConfiguracionVoz(
      habilitada: true,
      modoPrueba: false,
      dias: [1, 5],
      inicioMinutos: 1380,
      finMinutos: 60,
      frases: ['centinela necesito ayuda'],
    );
    expect(ConfiguracionVoz.fromMap(c.toMap()).toMap(), c.toMap());
    expect(const ConfiguracionVoz().modoPrueba, isTrue);
  });
  test(
    'Frases completas con tildes y puntuación; no coincidencias parciales',
    () {
      expect(
        fraseCoincidente('¡CENTINELA, necesito ayuda!', diario.frases),
        diario.frases.first,
      );
      expect(
        fraseCoincidente('centinela necesito ayudante', diario.frases),
        isNull,
      );
      expect(fraseCoincidente('necesito ayuda', diario.frases), isNull);
      expect(
        fraseCoincidente('¿Dónde estás? Necesito protección.', [
          'necesito proteccion',
        ]),
        'necesito proteccion',
      );
      expect(
        fraseCoincidente('no sirves para nadas', ['no sirves para nada']),
        isNull,
      );
    },
  );
}
