import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/models/incidente.dart';
import 'package:centinela/services/informe_service.dart';

void main() {
  test(
    'El PDF se genera con tildes, ñ, comillas tipográficas y emojis',
    () async {
      final incidente = Incidente(
        id: 1,
        fecha: DateTime(2026, 9, 24, 21, 5),
        lat: -16.5,
        lon: -68.15,
        urlsAudio: const ['https://res.cloudinary.com/x/video/upload/a.m4a'],
        finalizado: true,
        nombreAgresor: 'Juan Ñuflo',
        relacionAgresor: 'Ex pareja',
        tipoDelito: 'Violencia física',
        relato: 'Me dijo “te voy a encontrar” — y me empujó 😢…',
      );
      final bytes = await construirPdf(incidente, {
        'nombre_completo': 'María Pérez',
        'ci': '12345678',
        'ci_ext': 'LP',
        'fecha_nacimiento': '1990-03-05',
        'domicilio': 'Calle Sucre 45',
        'telefono': '71234567',
      });
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );

  test('Texto del PDF limpio para Latin-1', () {
    expect(textoPdf('“hola” – ñandú 😢'), '"hola" - ñandú ');
    expect(textoPdf('  ', 'Ninguno'), 'Ninguno');
  });

  test('Estado del informe', () {
    final base = Incidente(fecha: DateTime(2026));
    expect(base.estado, EstadoInforme.pendiente);
    expect(
      Incidente(fecha: DateTime(2026), relato: 'x').estado,
      EstadoInforme.sinSubir,
    );
    expect(
      Incidente(fecha: DateTime(2026), relato: 'x', urlPdf: 'u').estado,
      EstadoInforme.completo,
    );
  });
}
