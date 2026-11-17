import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:centinela/models/formulario_denuncia.dart';
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

  Incidente completo({bool victimaEsDenunciante = true, String relato = 'x'}) =>
      Incidente(
        id: 12,
        fecha: DateTime(2026, 9, 17, 22, 30),
        lat: -16.5,
        lon: -68.12,
        urlsAudio: [
          for (var n = 1; n <= 12; n++)
            'https://res.cloudinary.com/demo/video/upload/audio_$n.m4a',
        ],
        finalizado: true,
        nombreAgresor: 'Persona Denunciada',
        ciAgresor: '1234567 LP',
        relacionAgresor: 'Conocido',
        tipoDelito: 'Amenazas',
        relato: relato,
        formulario: {
          CampoFormulario.municipio: 'La Paz',
          CampoFormulario.zona: 'Miraflores',
          CampoFormulario.denIdioma: 'Castellano',
          CampoFormulario.victimaEsDenunciante: victimaEsDenunciante
              ? 'si'
              : 'no',
          if (!victimaEsDenunciante) ...{
            CampoFormulario.vicNombre: 'Otra Persona',
            CampoFormulario.relacionConVictima: 'Hermana',
          },
        },
      );

  /// Texto visible del PDF: la librería escribe cada palabra en su propio
  /// operador TJ, así que se unen con espacios.
  Future<String> textoDelPdf(
    Incidente i,
    Map<String, dynamic> denunciante,
  ) async {
    final crudo = latin1.decode(
      await construirPdf(
        i,
        denunciante,
        generado: DateTime(2026, 9, 18, 8, 35),
        comprimir: false,
      ),
    );
    return RegExp(r'\[\(((?:\\.|[^\\)])*)\)\]TJ')
        .allMatches(crudo)
        .map((m) => m[1]!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!))
        .join(' ');
  }

  test('El formulario lleva sus secciones, pruebas y datos vacíos', () async {
    final pdf = await textoDelPdf(completo(), {
      'nombre_completo': 'Denunciante Prueba',
      'ci': '7654321',
      'ci_ext': 'LP',
    });
    for (final texto in [
      'FORMULARIO DE DENUNCIA',
      'LUGAR Y FECHA DEL HECHO',
      '1 RELATO DEL HECHO',
      '2 PERSONA DENUNCIADA',
      '3 DATOS DEL DENUNCIANTE',
      '4 DATOS DE LA V',
      '5 PRUEBAS Y EVIDENCIAS',
      '6 OBSERVACIONES',
      'Miraflores',
      'Castellano',
      'Dato no consignado',
      'Grabaci',
      'https://res.cloudinary.com/demo/video/upload/audio_12.m4a',
      'https://maps.google.com/?q=-16.5,-68.12',
      'La Paz, 18 de septiembre de 2026',
      'DENUNCIANTE',
    ]) {
      expect(pdf, contains(texto), reason: texto);
    }
    // Sin elementos de un documento oficial ya registrado.
    expect(pdf, isNot(contains('FISCAL DE MATERIA')));
    expect(pdf, isNot(contains('CÓDIGO:')));
    // Campos retirados del formulario.
    expect(pdf, isNot(contains('fiscal asignado')));
    expect(pdf, isNot(contains('Autoidentificaci')));
    expect(pdf, isNot(contains('Domicilio laboral')));
  });

  test('Contacto reservado y víctima distinta del denunciante', () async {
    final pdf = await textoDelPdf(completo(victimaEsDenunciante: false), {
      'nombre_completo': 'Denunciante Prueba',
      'telefono': '71234567',
      'correo': 'yo@ejemplo.com',
      'reservar_contacto': true,
    });
    expect(pdf, contains('Dato reservado'));
    expect(pdf, isNot(contains('71234567')));
    expect(pdf, isNot(contains('yo@ejemplo.com')));
    expect(pdf, contains('Otra Persona'));
    expect(pdf, contains('Hermana'));
  });

  test('Relato al máximo y 12 audios no rompen el PDF', () async {
    final relato = List.filled(250, 'Texto largo del relato.').join(' ');
    final bytes = await construirPdf(
      completo(relato: relato.substring(0, 2000)),
      const {},
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('El formulario extra se guarda y se lee como JSON', () {
    final i = Incidente.fromMap({
      'id': 1,
      'fecha': '2026-09-17T22:30:00.000',
      'finalizado': 1,
      'formulario': jsonEncode({
        CampoFormulario.zona: 'Sopocachi',
        CampoFormulario.victimaEsDenunciante: 'no',
      }),
    });
    expect(i.campo(CampoFormulario.zona), 'Sopocachi');
    expect(i.campo(CampoFormulario.municipio), isNull);
    expect(i.victimaEsDenunciante, isFalse);
    expect(
      Incidente.fromMap({
        'fecha': '2026-01-01T00:00:00.000',
      }).victimaEsDenunciante,
      isTrue,
    );
  });

  test('Vista previa del PDF', () async {
    final ruta = Platform.environment['CENTINELA_PDF_PREVIA'];
    if (ruta == null) return;
    await File(ruta).writeAsBytes(
      await construirPdf(
        completo(
          relato:
              'El 17 de septiembre, cerca de las 22:30, la persona denunciada '
              'me amenazó en la puerta de mi casa y la alarma se activó.',
        ),
        {
          'nombre_completo': 'Denunciante Prueba',
          'ci': '7654321',
          'ci_ext': 'LP',
          'sexo': 'Femenino',
          'nacionalidad': 'Boliviana',
          'domicilio': 'Calle de prueba 123',
          'telefono': '70000000',
          'reservar_contacto': true,
        },
        generado: DateTime(2026, 9, 18, 8, 35),
      ),
    );
  });
}
