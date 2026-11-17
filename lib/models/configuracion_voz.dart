/// Horario semanal en la hora local del teléfono. Los días pertenecen al
/// inicio de la franja, también cuando termina al día siguiente.
class ConfiguracionVoz {
  final bool habilitada;
  final bool modoPrueba;
  final List<int> dias;
  final int inicioMinutos;
  final int finMinutos;
  final List<String> frases;

  const ConfiguracionVoz({
    this.habilitada = false,
    this.modoPrueba = true,
    this.dias = const [1, 2, 3, 4, 5, 6, 7],
    this.inicioMinutos = 420,
    this.finMinutos = 720,
    this.frases = const ['centinela necesito ayuda'],
  });

  String? get error {
    if (dias.isEmpty || dias.any((d) => d < 1 || d > 7)) {
      return 'Selecciona al menos un día válido.';
    }
    if (inicioMinutos < 0 ||
        inicioMinutos >= 1440 ||
        finMinutos < 0 ||
        finMinutos >= 1440 ||
        inicioMinutos == finMinutos) {
      return 'El inicio y el fin deben ser distintos y válidos.';
    }
    if (frases.isEmpty || frases.length > 10) {
      return 'Configura entre 1 y 10 frases.';
    }
    final normalizadas = frases.map(normalizarVoz).toList();
    if (normalizadas.any((f) => f.split(' ').length < 2 || f.length > 120)) {
      return 'Cada frase debe tener al menos dos palabras y hasta 120 caracteres.';
    }
    if (normalizadas.toSet().length != normalizadas.length) {
      return 'Hay frases repetidas.';
    }
    return null;
  }

  bool contiene(DateTime ahora) {
    if (!habilitada || error != null) return false;
    final minuto = ahora.hour * 60 + ahora.minute;
    if (inicioMinutos < finMinutos) {
      return dias.contains(ahora.weekday) &&
          minuto >= inicioMinutos &&
          minuto < finMinutos;
    }
    final ayer = ahora.weekday == 1 ? 7 : ahora.weekday - 1;
    return (dias.contains(ahora.weekday) && minuto >= inicioMinutos) ||
        (dias.contains(ayer) && minuto < finMinutos);
  }

  Map<String, dynamic> toMap() => {
    'version': 1,
    'habilitada': habilitada,
    'modoPrueba': modoPrueba,
    'dias': dias,
    'inicioMinutos': inicioMinutos,
    'finMinutos': finMinutos,
    'frases': frases,
  };

  factory ConfiguracionVoz.fromMap(Map<String, dynamic> m) => ConfiguracionVoz(
    habilitada: m['habilitada'] == true,
    modoPrueba: m['modoPrueba'] != false,
    dias: List<int>.from(m['dias'] as List),
    inicioMinutos: m['inicioMinutos'] as int,
    finMinutos: m['finMinutos'] as int,
    frases: List<String>.from(m['frases'] as List),
  );
}

String normalizarVoz(String texto) {
  var s = texto.toLowerCase();
  const cambios = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final e in cambios.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  return s
      .replaceAll(RegExp(r'[^a-zñ0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Coincidencia de frase completa sobre una transcripción final. No hace
/// clasificación de violencia, inferencia de intención ni reconocimiento de voz personal.
String? fraseCoincidente(String texto, List<String> frases) {
  final normalizado = ' ${normalizarVoz(texto)} ';
  for (final frase in frases) {
    if (normalizado.contains(' ${normalizarVoz(frase)} ')) return frase;
  }
  return null;
}
