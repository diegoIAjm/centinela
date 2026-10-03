import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<String?> completarIncidente(int id, Map<String, dynamic> datos) async {
    final db = await _db.database;
    await db.update(
      'incidentes',
      {
        for (final c in Incidente.camposInforme)
          c: (datos[c] as String?)?.trim().isEmpty ?? true
              ? null
              : (datos[c] as String).trim(),
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
    return completarIncidente(id, incidente.datosInforme);
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

Future<List<int>> construirPdf(
  Incidente i,
  Map<String, dynamic> denunciante,
) async {
  final doc = pw.Document(title: 'Informe de denuncia', creator: 'Centinela');
  String d(String clave, [String siVacio = 'No indicado']) =>
      textoPdf(denunciante[clave] as String?, siVacio);
  final ci = denunciante['ci'] == null
      ? 'No indicado'
      : '${d('ci')} ${d('ci_ext', '')}'.trim();

  pw.Widget titulo(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
    child: pw.Text(
      t,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );
  pw.Widget fila(String etiqueta, String valor) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 110,
          child: pw.Text(
            etiqueta,
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(child: pw.Text(valor)),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ).copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 10.5)),
      build: (_) => [
        pw.Divider(thickness: 2),
        pw.Center(
          child: pw.Text(
            'INFORME DE DENUNCIA',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Generado por Centinela',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
        ),
        pw.Divider(thickness: 2),
        titulo('INCIDENTE'),
        fila('Fecha y hora:', formatearFecha(i.fecha)),
        fila(
          'Ubicación:',
          i.lat == null ? 'No disponible' : '${i.lat}, ${i.lon}\n${i.linkMaps}',
        ),
        titulo('DENUNCIANTE'),
        fila('Nombre:', d('nombre_completo')),
        fila('CI:', ci),
        fila(
          'Fecha de nac.:',
          formatearFechaNacimiento(denunciante['fecha_nacimiento'] as String?),
        ),
        fila('Domicilio:', d('domicilio')),
        fila('Teléfono:', d('telefono')),
        fila('Ocupación:', d('ocupacion', 'No indicada')),
        titulo('DENUNCIADO'),
        fila('Nombre:', textoPdf(i.nombreAgresor, 'No conocido')),
        fila('CI:', textoPdf(i.ciAgresor, 'No conocido')),
        fila('Relación:', textoPdf(i.relacionAgresor, 'No indicada')),
        fila('Domicilio:', textoPdf(i.domicilioAgresor, 'No conocido')),
        fila(
          'Descripción:',
          textoPdf(i.descripcionFisicaAgresor, 'No especificada'),
        ),
        titulo('HECHOS'),
        fila('Tipo de delito:', textoPdf(i.tipoDelito, 'No indicado')),
        fila('Relato:', ''),
        pw.Paragraph(text: textoPdf(i.relato)),
        titulo('PRUEBAS'),
        if (i.urlsAudio.isEmpty)
          fila('Audio:', 'Sin audio subido')
        else
          for (var n = 0; n < i.urlsAudio.length; n++)
            fila(
              i.urlsAudio.length == 1 ? 'Audio:' : 'Audio ${n + 1}:',
              i.urlsAudio[n],
            ),
        titulo('TESTIGOS'),
        pw.Paragraph(text: textoPdf(i.testigos, 'Ninguno')),
        titulo('OBSERVACIONES'),
        pw.Paragraph(text: textoPdf(i.observaciones, 'Ninguna')),
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 2),
        pw.Text(
          'Este informe fue generado automáticamente por Centinela. '
          'No sustituye una denuncia formal ante la Fiscalía o Policía, '
          'pero sirve como evidencia y contexto para presentarla.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
        pw.Divider(thickness: 2),
      ],
    ),
  );
  return doc.save();
}
