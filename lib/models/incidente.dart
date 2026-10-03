import 'dart:convert';

enum EstadoInforme { pendiente, sinSubir, completo }

/// Una alarma registrada y, si la víctima lo completó, su informe.
class Incidente {
  final int? id;
  final DateTime fecha;
  final double? lat;
  final double? lon;

  /// Un link por cada fragmento de audio subido a Cloudinary.
  final List<String> urlsAudio;
  final String? urlPdf;
  final String? rutaPdf;

  /// false mientras la alarma sigue (incluido el modo PIN falso): esos
  /// incidentes no se muestran en el historial.
  final bool finalizado;

  final String? nombreAgresor;
  final String? ciAgresor;
  final String? relacionAgresor;
  final String? domicilioAgresor;
  final String? descripcionFisicaAgresor;
  final String? tipoDelito;
  final String? relato;
  final String? testigos;
  final String? observaciones;

  const Incidente({
    this.id,
    required this.fecha,
    this.lat,
    this.lon,
    this.urlsAudio = const [],
    this.urlPdf,
    this.rutaPdf,
    this.finalizado = false,
    this.nombreAgresor,
    this.ciAgresor,
    this.relacionAgresor,
    this.domicilioAgresor,
    this.descripcionFisicaAgresor,
    this.tipoDelito,
    this.relato,
    this.testigos,
    this.observaciones,
  });

  String? get urlAudio => urlsAudio.isEmpty ? null : urlsAudio.first;

  String? get linkMaps => lat == null || lon == null
      ? null
      : 'https://maps.google.com/?q=$lat,$lon';

  EstadoInforme get estado {
    if (relato == null || relato!.trim().isEmpty) {
      return EstadoInforme.pendiente;
    }
    return urlPdf == null ? EstadoInforme.sinSubir : EstadoInforme.completo;
  }

  factory Incidente.fromMap(Map<String, Object?> m) => Incidente(
    id: m['id'] as int?,
    fecha: DateTime.parse(m['fecha'] as String),
    lat: (m['lat'] as num?)?.toDouble(),
    lon: (m['lon'] as num?)?.toDouble(),
    urlsAudio: m['urls_audio'] == null
        ? const []
        : List<String>.from(jsonDecode(m['urls_audio'] as String) as List),
    urlPdf: m['url_pdf'] as String?,
    rutaPdf: m['ruta_pdf'] as String?,
    finalizado: m['finalizado'] == 1,
    nombreAgresor: m['nombre_agresor'] as String?,
    ciAgresor: m['ci_agresor'] as String?,
    relacionAgresor: m['relacion_agresor'] as String?,
    domicilioAgresor: m['domicilio_agresor'] as String?,
    descripcionFisicaAgresor: m['descripcion_agresor'] as String?,
    tipoDelito: m['tipo_delito'] as String?,
    relato: m['relato'] as String?,
    testigos: m['testigos'] as String?,
    observaciones: m['observaciones'] as String?,
  );

  /// Claves que la pantalla de datos del incidente puede escribir.
  static const camposInforme = [
    'nombre_agresor',
    'ci_agresor',
    'relacion_agresor',
    'domicilio_agresor',
    'descripcion_agresor',
    'tipo_delito',
    'relato',
    'testigos',
    'observaciones',
  ];

  Map<String, String?> get datosInforme => {
    'nombre_agresor': nombreAgresor,
    'ci_agresor': ciAgresor,
    'relacion_agresor': relacionAgresor,
    'domicilio_agresor': domicilioAgresor,
    'descripcion_agresor': descripcionFisicaAgresor,
    'tipo_delito': tipoDelito,
    'relato': relato,
    'testigos': testigos,
    'observaciones': observaciones,
  };
}
