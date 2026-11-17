import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/formulario_denuncia.dart';
import '../models/incidente.dart';
import 'cloudinary_service.dart';
import 'database_service.dart';

/// Datos permanentes de la víctima (SharedPreferences, solo en la UI) e
/// incidentes (SQLite, escritos también por el servicio de alarma).
class InformeService {
  static const _claveDenunciante = 'datos_denunciante';
  static const camposObligatoriosDenunciante = [
    'nombre_completo',
    'ci',
    'domicilio',
    'telefono',
  ];

  final _db = DatabaseService();

  // ===================== DENUNCIANTE =====================

  Future<void> guardarDatosDenunciante(Map<String, dynamic> datos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveDenunciante, jsonEncode(datos));
  }

  Future<Map<String, dynamic>> obtenerDatosDenunciante() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_claveDenunciante);
    return json == null ? {} : jsonDecode(json) as Map<String, dynamic>;
  }

  Future<bool> datosDenuncianteCompletos() async {
    final d = await obtenerDatosDenunciante();
    return camposObligatoriosDenunciante.every(
      (c) => (d[c] as String?)?.trim().isNotEmpty ?? false,
    );
  }

  // ===================== INCIDENTES =====================

  /// Lo llama el servicio de alarma al dispararse. [lat]/[lon] pueden
  /// llegar después con [actualizarUbicacion].
  Future<int> crearIncidente({
    required DateTime fecha,
    double? lat,
    double? lon,
    String? urlAudio,
  }) async {
    final db = await _db.database;
    return db.insert('incidentes', {
      'fecha': fecha.toIso8601String(),
      'lat': lat,
      'lon': lon,
      'urls_audio': jsonEncode([?urlAudio]),
      'finalizado': 0,
    });
  }

  Future<void> actualizarUbicacion(int id, double lat, double lon) async {
    final db = await _db.database;
    await db.update(
      'incidentes',
      {'lat': lat, 'lon': lon},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> agregarAudio(int id, String url) async {
    final incidente = await obtenerIncidente(id);
    if (incidente == null) return;
    final db = await _db.database;
    await db.update(
      'incidentes',
      {
        'urls_audio': jsonEncode([...incidente.urlsAudio, url]),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// La alarma terminó de verdad (PIN real o "Estoy a salvo"): desde ahora
  /// aparece en el historial.
  Future<void> finalizarIncidente(int id) async {
    final db = await _db.database;
    await db.update(
      'incidentes',
      {'finalizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Al arrancar el servicio no hay ninguna alarma en curso: los incidentes
  /// que quedaron abiertos (servicio cerrado a la fuerza) se muestran ya.
  Future<void> finalizarAbiertos() async {
    final db = await _db.database;
    await db.update('incidentes', {'finalizado': 1}, where: 'finalizado = 0');
  }

  Future<List<Incidente>> obtenerHistorial() async {
    final db = await _db.database;
    final filas = await db.query(
      'incidentes',
      where: 'finalizado = 1',
      orderBy: 'fecha DESC',
    );
    return filas.map(Incidente.fromMap).toList();
  }

  Future<Incidente?> obtenerIncidente(int id) async {
    final db = await _db.database;
    final filas = await db.query(
      'incidentes',
      where: 'id = ?',
      whereArgs: [id],
    );
    return filas.isEmpty ? null : Incidente.fromMap(filas.first);
  }

  /// Guarda agresor y hechos, genera el PDF y lo sube a Cloudinary.
  /// Devuelve null si todo salió bien, o el motivo si el PDF no se subió
  /// (los datos y el PDF local quedan guardados igual).
  Future<String?> completarIncidente(
    int id,
    Map<String, dynamic> datos, {
    Map<String, String>? formulario,
  }) async {
    final db = await _db.database;
    await db.update(
      'incidentes',
      {
        for (final c in Incidente.camposInforme)
          c: (datos[c] as String?)?.trim().isEmpty ?? true
              ? null
              : (datos[c] as String).trim(),
        if (formulario != null)
          'formulario': jsonEncode({
            for (final e in formulario.entries)
              if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
          }),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final ruta = await generarPDFCompleto(id);
    if (ruta == null) return 'No se encontró el incidente';
    await db.update(
      'incidentes',
      {'ruta_pdf': ruta, 'url_pdf': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    final subida = await subirPDFACloudinary(ruta);
    if (subida.url == null) return subida.error;
    await db.update(
      'incidentes',
      {'url_pdf': subida.url},
      where: 'id = ?',
      whereArgs: [id],
    );
    return null;
  }

  /// Reintenta subir un informe ya guardado cuya subida falló. Regenera el
  /// PDF por si llegaron más audios o cambiaron los datos del denunciante.
  Future<String?> reintentarSubidaPdf(int id) async {
    final incidente = await obtenerIncidente(id);
    if (incidente == null) return 'No se encontró el incidente';
    return completarIncidente(
      id,
      incidente.datosInforme,
      formulario: incidente.formulario,
    );
  }

  /// Crea (o reemplaza) el PDF local del informe y devuelve su ruta.
  Future<String?> generarPDFCompleto(int id) async {
    final incidente = await obtenerIncidente(id);
    if (incidente == null) return null;
    final denunciante = await obtenerDatosDenunciante();
    final bytes = await construirPdf(incidente, denunciante);
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/centinela_informes');
    await carpeta.create(recursive: true);
    final archivo = File('${carpeta.path}/informe_incidente_$id.pdf');
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo.path;
  }
}

// ===================== PDF =====================

String formatearFecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

String formatearFechaNacimiento(String? iso) {
  final f = iso == null ? null : DateTime.tryParse(iso);
  if (f == null) return 'No indicada';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

/// La fuente estándar del PDF solo tiene Latin-1: se reemplazan comillas y
/// rayas tipográficas y se descarta lo demás (emojis) para que no falle.
String textoPdf(String? v, [String siVacio = '-']) {
  if (v == null || v.trim().isEmpty) return siVacio;
  const reemplazos = {
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '–': '-',
    '—': '-',
    '…': '...',
  };
  final b = StringBuffer();
  for (final r in v.trim().runes) {
    final c = String.fromCharCode(r);
    if (reemplazos.containsKey(c)) {
      b.write(reemplazos[c]);
    } else if (r == 10 || (r >= 32 && r <= 255)) {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String fechaEnLetras(DateTime f) =>
    '${f.day} de ${_meses[f.month - 1]} de ${f.year}';

/// Formulario de denuncia con la estructura del Formulario Único de Denuncias
/// del Ministerio Público. Es un borrador que presenta la persona: no lleva
/// escudo, código de caso, QR ni datos de registro, porque esos los asigna la
/// institución al recibir la denuncia.
Future<List<int>> construirPdf(
  Incidente i,
  Map<String, dynamic> denunciante, {
  DateTime? generado,
  bool comprimir = true,
}) async {
  const noConsignado = 'Dato no consignado';
  const reservado = 'Dato reservado';
  final ahora = generado ?? DateTime.now();
  final doc = pw.Document(
    title: 'Formulario de denuncia',
    creator: 'Centinela',
    compress: comprimir,
  );

  String d(String clave, [String siVacio = noConsignado]) =>
      textoPdf(denunciante[clave] as String?, siVacio);
  String f(String clave, [String siVacio = noConsignado]) =>
      textoPdf(i.campo(clave), siVacio);
  final contactoReservado = denunciante['reservar_contacto'] == true;
  final nombreDenunciante = d('nombre_completo', '');
  final numeroCi = (denunciante['ci'] as String?)?.trim() ?? '';
  final ciDenunciante = numeroCi.isEmpty
      ? noConsignado
      : textoPdf('$numeroCi ${denunciante['ci_ext'] ?? ''}');

  const borde = pw.BorderSide(color: PdfColors.grey600, width: 0.6);
  final etiqueta = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget seccion(String titulo) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey300,
      border: pw.Border.fromBorderSide(borde),
    ),
    child: pw.Text(titulo, style: etiqueta.copyWith(fontSize: 10)),
  );

  pw.Widget dato(String nombre, String valor) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 1.5),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$nombre: ', style: etiqueta),
          pw.TextSpan(text: valor),
        ],
      ),
    ),
  );

  pw.Widget recuadro(pw.Widget hijo) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(left: borde, right: borde, bottom: borde),
    ),
    child: hijo,
  );

  pw.Widget dosColumnas(List<pw.Widget> izquierda, List<pw.Widget> derecha) =>
      recuadro(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: izquierda,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: derecha,
              ),
            ),
          ],
        ),
      );

  pw.Widget enlace(String url) => pw.UrlLink(
    destination: url,
    child: pw.Text(
      url,
      style: const pw.TextStyle(
        color: PdfColors.blue800,
        decoration: pw.TextDecoration.underline,
      ),
    ),
  );

  final horario = i.campo(CampoFormulario.horarioHecho);
  final fechaHecho = [
    formatearFecha(i.fecha),
    '(activación de la alarma)',
    if (horario != null) '- ${textoPdf(horario)}',
  ].join(' ');
  final municipio = i.campo(CampoFormulario.municipio);

  final victima = i.victimaEsDenunciante
      ? recuadro(
          pw.Text(
            'La víctima es la misma persona denunciante (ver sección 3).',
          ),
        )
      : dosColumnas(
          [
            dato('Nombres y apellidos', f(CampoFormulario.vicNombre)),
            dato('C.I.', f(CampoFormulario.vicCi)),
            dato('Sexo', f(CampoFormulario.vicSexo)),
            dato('Fecha de nacimiento', f(CampoFormulario.vicFechaNacimiento)),
            dato('Estado civil', f(CampoFormulario.vicEstadoCivil)),
          ],
          [
            dato('Nacionalidad', f(CampoFormulario.vicNacionalidad)),
            dato('Profesión u ocupación', f(CampoFormulario.vicOcupacion)),
            dato('Domicilio', f(CampoFormulario.vicDomicilio)),
            dato('Lugar de trabajo', f(CampoFormulario.vicLugarTrabajo)),
            dato('Teléfono y celular', f(CampoFormulario.vicTelefono)),
          ],
        );

  final gris = pw.TextStyle(fontSize: 7, color: PdfColors.grey700);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ).copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 9)),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Borrador elaborado con Centinela - no es una denuncia registrada',
            style: gris,
          ),
          pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: gris),
        ],
      ),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            'FORMULARIO DE DENUNCIA',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Para presentar ante el Ministerio Público o la Policía',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
        ),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Referencia Centinela: incidente N.º ${i.id ?? '-'}',
            style: gris.copyWith(fontSize: 8),
          ),
        ),
        seccion('CASO'),
        dosColumnas(
          [
            dato('Tipo de denuncia', 'Denuncia escrita de la persona'),
            dato('Tipo de delito', textoPdf(i.tipoDelito, noConsignado)),
            dato('Fecha de elaboración', formatearFecha(ahora)),
          ],
          [
            pw.Text('LUGAR Y FECHA DEL HECHO', style: etiqueta),
            dato('Municipio', f(CampoFormulario.municipio)),
            dato('Zona', f(CampoFormulario.zona)),
            dato('Dirección', f(CampoFormulario.direccionHecho)),
            dato('Fecha del hecho', fechaHecho),
            dato(
              'Ubicación GPS',
              i.lat == null ? 'No disponible' : '${i.lat}, ${i.lon}',
            ),
          ],
        ),
        seccion('1  RELATO DEL HECHO'),
        recuadro(
          pw.Text(
            textoPdf(i.relato, noConsignado),
            textAlign: pw.TextAlign.justify,
          ),
        ),
        seccion('2  PERSONA DENUNCIADA'),
        dosColumnas(
          [
            dato(
              'Nombres y apellidos',
              textoPdf(i.nombreAgresor, noConsignado),
            ),
            dato('C.I.', textoPdf(i.ciAgresor, noConsignado)),
            dato('Sexo', f(CampoFormulario.denSexo)),
            dato('Fecha de nacimiento', f(CampoFormulario.denFechaNacimiento)),
            dato('Estado civil', f(CampoFormulario.denEstadoCivil)),
            dato('Teléfono y celular', f(CampoFormulario.denTelefono)),
            dato('Correo electrónico', f(CampoFormulario.denCorreo)),
            dato('Domicilio', textoPdf(i.domicilioAgresor, noConsignado)),
          ],
          [
            dato('Lugar de nacimiento', f(CampoFormulario.denLugarNacimiento)),
            dato('Nivel de educación', f(CampoFormulario.denEducacion)),
            dato('Profesión u ocupación', f(CampoFormulario.denOcupacion)),
            dato('Lugar de trabajo', f(CampoFormulario.denLugarTrabajo)),
            dato(
              'Relación con la víctima',
              textoPdf(i.relacionAgresor, noConsignado),
            ),
            dato('Idioma', f(CampoFormulario.denIdioma)),
            dato(
              'Descripción física',
              textoPdf(i.descripcionFisicaAgresor, noConsignado),
            ),
          ],
        ),
        seccion('3  DATOS DEL DENUNCIANTE'),
        dosColumnas(
          [
            dato('Nombres y apellidos', d('nombre_completo')),
            dato('C.I.', ciDenunciante),
            dato('Sexo', d('sexo')),
            dato(
              'Fecha de nacimiento',
              denunciante['fecha_nacimiento'] == null
                  ? noConsignado
                  : formatearFechaNacimiento(
                      denunciante['fecha_nacimiento'] as String?,
                    ),
            ),
            dato('Estado civil', d('estado_civil')),
            dato('Nacionalidad', d('nacionalidad')),
          ],
          [
            dato('Profesión u ocupación', d('ocupacion')),
            dato('Domicilio', d('domicilio')),
            dato('Lugar de trabajo', d('lugar_trabajo')),
            dato(
              'Teléfono y celular',
              contactoReservado ? reservado : d('telefono'),
            ),
            dato(
              'Correo electrónico',
              contactoReservado ? reservado : d('correo'),
            ),
            dato(
              'Relación con la víctima',
              i.victimaEsDenunciante
                  ? 'Es la víctima'
                  : f(CampoFormulario.relacionConVictima),
            ),
          ],
        ),
        seccion('4  DATOS DE LA VÍCTIMA'),
        victima,
        seccion('5  PRUEBAS Y EVIDENCIAS'),
        recuadro(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Registradas automáticamente por la aplicación Centinela al '
                'activarse la alarma el ${formatearFecha(i.fecha)}.',
              ),
              pw.SizedBox(height: 4),
              if (i.urlsAudio.isEmpty)
                dato('Grabaciones de audio', 'No se subió ningún audio')
              else
                for (var n = 0; n < i.urlsAudio.length; n++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Grabación de audio N.º ${n + 1}:',
                          style: etiqueta,
                        ),
                        enlace(i.urlsAudio[n]),
                      ],
                    ),
                  ),
              pw.SizedBox(height: 2),
              if (i.linkMaps == null)
                dato('Ubicación en el mapa', 'No disponible')
              else ...[
                pw.Text('Ubicación en el mapa:', style: etiqueta),
                enlace(i.linkMaps!),
              ],
              pw.SizedBox(height: 2),
              dato('Testigos', textoPdf(i.testigos, 'Ninguno indicado')),
            ],
          ),
        ),
        seccion('6  OBSERVACIONES'),
        recuadro(pw.Text(textoPdf(i.observaciones, 'Ninguna'))),
        pw.SizedBox(height: 36),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 200,
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 0.6, color: PdfColors.black),
                  pw.Text(
                    nombreDenunciante.isEmpty
                        ? 'Firma del denunciante'
                        : nombreDenunciante,
                    style: etiqueta,
                  ),
                  pw.Text('C.I.: $ciDenunciante'),
                  pw.Text('DENUNCIANTE'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            '${textoPdf(municipio, '__________')}, ${fechaEnLetras(ahora)}',
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
