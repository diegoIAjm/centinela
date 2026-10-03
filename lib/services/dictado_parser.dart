/// Convierte un dictado libre ("Mi nombre es María Pérez, mi carnet es
/// 12345678 LP, vivo en…") en campos de formulario. Cada campo empieza en su
/// frase clave y termina donde empieza la siguiente.
library;

const extensionesCi = ['LP', 'SC', 'CB', 'OR', 'PT', 'TJ', 'CH', 'BE'];

const relacionesAgresor = [
  'Ex pareja',
  'Familiar',
  'Conocido',
  'Vecino',
  'Compañero de trabajo',
  'Desconocido',
  'Otro',
];

const _clavesDenunciante = {
  'nombre_completo': [
    'mi nombre completo es',
    'mi nombre es',
    'me llamo',
    'nombre',
  ],
  'ci': [
    'mi carnet de identidad es',
    'mi carnet es',
    'carnet de identidad',
    'carnet',
    'cedula de identidad',
    'cedula',
    'ci',
  ],
  'fecha_nacimiento': ['fecha de nacimiento', 'naci el', 'naci'],
  'domicilio': [
    'mi domicilio es',
    'domicilio',
    'vivo en',
    'mi direccion es',
    'direccion',
  ],
  'telefono': [
    'mi numero de celular es',
    'mi telefono es',
    'mi celular es',
    'numero de celular',
    'telefono',
    'celular',
  ],
  'ocupacion': [
    'mi ocupacion es',
    'ocupacion',
    'trabajo como',
    'soy de profesion',
  ],
};

const _clavesAgresor = {
  'nombre_agresor': [
    'su nombre es',
    'se llama',
    'nombre del agresor',
    'nombre',
  ],
  'ci_agresor': ['su carnet es', 'su carnet', 'carnet', 'cedula', 'ci'],
  'relacion_agresor': ['la relacion es', 'relacion', 'es mi'],
  'domicilio_agresor': ['su domicilio es', 'vive en', 'domicilio', 'direccion'],
  'descripcion_agresor': [
    'descripcion fisica',
    'descripcion',
    'fisicamente',
    'estatura',
    'mide',
    'vestia',
    'lleva puesto',
  ],
};

/// Datos de la víctima: nombre_completo, ci, ci_ext, fecha_nacimiento
/// (yyyy-MM-dd), domicilio, telefono, ocupacion.
Map<String, String> interpretarDenunciante(String dictado) {
  final crudo = _extraer(dictado, _clavesDenunciante);
  final r = <String, String>{};
  final nombre = crudo['nombre_completo'];
  if (nombre != null) r['nombre_completo'] = _capitalizar(nombre);
  final ci = crudo['ci'];
  if (ci != null) {
    final (numero, ext) = _separarCi(ci);
    if (numero.isNotEmpty) r['ci'] = numero;
    if (ext != null) r['ci_ext'] = ext;
  }
  final fecha = crudo['fecha_nacimiento'];
  final fechaIso = fecha == null ? null : interpretarFecha(fecha);
  if (fechaIso != null) r['fecha_nacimiento'] = fechaIso;
  final domicilio = crudo['domicilio'];
  if (domicilio != null) r['domicilio'] = _primeraMayuscula(domicilio);
  final tel = crudo['telefono'];
  if (tel != null) {
    final digitos = _soloDigitos(tel);
    if (digitos.isNotEmpty) r['telefono'] = digitos;
  }
  final ocupacion = crudo['ocupacion'];
  if (ocupacion != null) r['ocupacion'] = _primeraMayuscula(ocupacion);
  return r;
}

/// Datos del agresor: nombre_agresor, ci_agresor, relacion_agresor (uno de
/// [relacionesAgresor]), domicilio_agresor, descripcion_agresor.
Map<String, String> interpretarAgresor(String dictado) {
  final crudo = _extraer(dictado, _clavesAgresor);
  final r = <String, String>{};
  final nombre = crudo['nombre_agresor'];
  if (nombre != null) r['nombre_agresor'] = _capitalizar(nombre);
  final ci = crudo['ci_agresor'];
  if (ci != null) {
    final (numero, ext) = _separarCi(ci);
    if (numero.isNotEmpty) {
      r['ci_agresor'] = ext == null ? numero : '$numero $ext';
    }
  }
  final relacion = relacionDesdeTexto(crudo['relacion_agresor'] ?? dictado);
  if (relacion != null) r['relacion_agresor'] = relacion;
  final domicilio = crudo['domicilio_agresor'];
  if (domicilio != null) r['domicilio_agresor'] = _primeraMayuscula(domicilio);
  final descripcion = crudo['descripcion_agresor'];
  if (descripcion != null) {
    r['descripcion_agresor'] = _primeraMayuscula(descripcion);
  }
  return r;
}

String? relacionDesdeTexto(String texto) {
  final t = _normalizar(texto);
  bool hay(String patron) => RegExp('\\b($patron)').hasMatch(t);
  if (hay(r'ex\b|ex ?pareja|ex ?esposo|ex ?novio|ex ?marido')) {
    return 'Ex pareja';
  }
  if (hay('desconocido|no lo conozco|no la conozco')) return 'Desconocido';
  if (hay(
    'padre|madre|papa|mama|herman|tio|tia|prim|padrastro|madrastra|'
    'hijo|hija|abuel|cunad|suegr|familiar',
  )) {
    return 'Familiar';
  }
  if (hay('vecin')) return 'Vecino';
  if (hay('companer|colega|jefe|trabajo')) return 'Compañero de trabajo';
  if (hay('conocid|amig')) return 'Conocido';
  if (hay('pareja|esposo|novio|marido|conviviente')) return 'Otro';
  return null;
}

const _meses = {
  'enero': 1,
  'febrero': 2,
  'marzo': 3,
  'abril': 4,
  'mayo': 5,
  'junio': 6,
  'julio': 7,
  'agosto': 8,
  'septiembre': 9,
  'setiembre': 9,
  'octubre': 10,
  'noviembre': 11,
  'diciembre': 12,
};

/// "5 de marzo de 1990" o "05/03/1990" → "1990-03-05".
String? interpretarFecha(String texto) {
  final t = _normalizar(texto);
  int? dia, mes, anio;
  final larga = RegExp(
    r'(\d{1,2})\s+de\s+([a-z]+)\s+(?:de|del)\s+(\d{4})',
  ).firstMatch(t);
  if (larga != null) {
    dia = int.parse(larga.group(1)!);
    mes = _meses[larga.group(2)];
    anio = int.parse(larga.group(3)!);
  } else {
    final corta = RegExp(
      r'(\d{1,2})[/\-. ](\d{1,2})[/\-. ](\d{4})',
    ).firstMatch(t);
    if (corta == null) return null;
    dia = int.parse(corta.group(1)!);
    mes = int.parse(corta.group(2)!);
    anio = int.parse(corta.group(3)!);
  }
  if (mes == null || mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  final f = DateTime(anio, mes, dia);
  if (f.month != mes) return null; // 31 de febrero, etc.
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${f.year}-${dos(f.month)}-${dos(f.day)}';
}

// ============================================================

Map<String, String> _extraer(String texto, Map<String, List<String>> claves) {
  final norm = _normalizar(texto);
  final marcas = <({int inicio, int fin, String campo})>[];
  claves.forEach((campo, frases) {
    ({int inicio, int fin})? mejor;
    for (final frase in frases) {
      final patron = RegExp('\\b${frase.replaceAll(' ', r'\s+')}\\b');
      final m = patron.firstMatch(norm);
      if (m == null) continue;
      if (mejor == null ||
          m.start < mejor.inicio ||
          (m.start == mejor.inicio && m.end > mejor.fin)) {
        mejor = (inicio: m.start, fin: m.end);
      }
    }
    if (mejor != null) {
      marcas.add((inicio: mejor.inicio, fin: mejor.fin, campo: campo));
    }
  });
  marcas.sort((a, b) => a.inicio.compareTo(b.inicio));

  final r = <String, String>{};
  for (var i = 0; i < marcas.length; i++) {
    final m = marcas[i];
    // Una frase clave dentro del valor de otro campo no corta ese valor.
    if (i > 0 && m.inicio < marcas[i - 1].fin) continue;
    final fin = i + 1 < marcas.length ? marcas[i + 1].inicio : texto.length;
    final valor = _limpiar(texto.substring(m.fin, fin));
    if (valor.isNotEmpty) r[m.campo] = valor;
  }
  return r;
}

/// Minúsculas y sin tildes, conservando la longitud (mismos índices).
String _normalizar(String texto) {
  const con = 'áéíóúüñÁÉÍÓÚÜÑ';
  const sin = 'aeiouunaeiouun';
  final b = StringBuffer();
  for (final c in texto.split('')) {
    final i = con.indexOf(c);
    b.write(i >= 0 ? sin[i] : c.toLowerCase());
  }
  return b.toString();
}

String _limpiar(String valor) {
  var v = valor.trim();
  v = v.replaceFirst(
    RegExp(r'^(es|son|era|:|el|la|de|en)\s+', caseSensitive: false),
    '',
  );
  v = v.replaceFirst(RegExp(r'^[\s,:;.\-]+'), '');
  v = v.replaceFirst(RegExp(r'[\s,;.\-]+(y|e)?[\s,;.\-]*$'), '');
  v = v.replaceFirst(RegExp(r'\s+(y|e)$'), '');
  return v.trim();
}

(String, String?) _separarCi(String valor) {
  final numero = _soloDigitos(valor);
  final t = _normalizar(valor);
  const departamentos = {
    'la paz': 'LP',
    'santa cruz': 'SC',
    'cochabamba': 'CB',
    'oruro': 'OR',
    'potosi': 'PT',
    'tarija': 'TJ',
    'chuquisaca': 'CH',
    'sucre': 'CH',
    'beni': 'BE',
  };
  for (final e in departamentos.entries) {
    if (t.contains(e.key)) return (numero, e.value);
  }
  final letras = t.replaceAll(RegExp(r'[^a-z]'), '').toUpperCase();
  for (final ext in extensionesCi) {
    if (letras.endsWith(ext)) return (numero, ext);
  }
  return (numero, null);
}

String _soloDigitos(String v) {
  final mas = v.trim().startsWith('+') ? '+' : '';
  return mas + v.replaceAll(RegExp(r'\D'), '');
}

String _capitalizar(String v) => v
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
    .join(' ');

String _primeraMayuscula(String v) =>
    v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
