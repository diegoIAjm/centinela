import 'package:flutter/material.dart';
import '../services/dictado_parser.dart';
import '../services/informe_service.dart';
import '../widgets/dictado_sheet.dart';
import 'configuracion_denunciante_screen.dart';

const tiposDelito = [
  'Violencia física',
  'Violencia psicológica',
  'Amenazas',
  'Acoso',
  'Violencia económica',
  'Otro',
];

/// Datos del agresor y relato de un incidente; al guardar genera el PDF.
class DatosIncidenteScreen extends StatefulWidget {
  final int idIncidente;
  const DatosIncidenteScreen({super.key, required this.idIncidente});

  @override
  State<DatosIncidenteScreen> createState() => _DatosIncidenteScreenState();
}

class _DatosIncidenteScreenState extends State<DatosIncidenteScreen> {
  static const _maxRelato = 2000;

  final _informes = InformeService();
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _ci = TextEditingController();
  final _domicilio = TextEditingController();
  final _descripcion = TextEditingController();
  final _relato = TextEditingController();
  final _testigos = TextEditingController();
  final _observaciones = TextEditingController();
  String? _relacion;
  String? _tipoDelito;
  String _fecha = '';
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final i = await _informes.obtenerIncidente(widget.idIncidente);
    if (!mounted) return;
    if (i == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _fecha = formatearFecha(i.fecha);
      _nombre.text = i.nombreAgresor ?? '';
      _ci.text = i.ciAgresor ?? '';
      _domicilio.text = i.domicilioAgresor ?? '';
      _descripcion.text = i.descripcionFisicaAgresor ?? '';
      _relato.text = i.relato ?? '';
      _testigos.text = i.testigos ?? '';
      _observaciones.text = i.observaciones ?? '';
      _relacion = i.relacionAgresor;
      _tipoDelito = i.tipoDelito;
      _cargando = false;
    });
  }

  Future<void> _dictarAgresor() async {
    final texto = await dictar(
      context,
      titulo: '🎤 Datos del agresor',
      ayuda:
          'Ejemplo: "Se llama Juan Mamani, su carnet es 7654321, es mi ex '
          'pareja, vive en la avenida Blanco Galindo, descripción física '
          'alto, moreno, con una cicatriz en la ceja."',
    );
    if (texto == null || !mounted) return;
    final c = interpretarAgresor(texto);
    if (c.isEmpty) {
      _avisar(
        'No reconocí datos. Empieza con "se llama", "vive en", "es mi"…',
        Colors.orange,
      );
      return;
    }
    setState(() {
      if (c['nombre_agresor'] case final v?) _nombre.text = v;
      if (c['ci_agresor'] case final v?) _ci.text = v;
      if (c['relacion_agresor'] case final v?) _relacion = v;
      if (c['domicilio_agresor'] case final v?) _domicilio.text = v;
      if (c['descripcion_agresor'] case final v?) _descripcion.text = v;
    });
    _avisar('Se completaron ${c.length} dato(s). Revísalos.', Colors.green);
  }

  Future<void> _dictarHechos() async {
    final texto = await dictar(
      context,
      titulo: '🎤 ¿Qué pasó?',
      ayuda:
          'Cuenta con tus palabras qué ocurrió, dónde y cómo. '
          'Se agrega al relato; después puedes corregirlo.',
    );
    if (texto == null || !mounted) return;
    setState(() {
      final previo = _relato.text.trim();
      var nuevo = previo.isEmpty ? texto : '$previo $texto';
      if (nuevo.length > _maxRelato) nuevo = nuevo.substring(0, _maxRelato);
      _relato.text = nuevo;
    });
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (!await _informes.datosDenuncianteCompletos()) {
      if (!mounted) return;
      final configurar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Faltan tus datos personales'),
          content: const Text(
            'El informe necesita tu nombre, CI, domicilio y teléfono. '
            '¿Quieres completarlos ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Generar igual'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Completar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (configurar == true) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ConfiguracionDenuncianteScreen(),
          ),
        );
        if (!mounted) return;
      }
    }

    setState(() => _guardando = true);
    final error = await _informes.completarIncidente(widget.idIncidente, {
      'nombre_agresor': _nombre.text,
      'ci_agresor': _ci.text,
      'relacion_agresor': _relacion,
      'domicilio_agresor': _domicilio.text,
      'descripcion_agresor': _descripcion.text,
      'tipo_delito': _tipoDelito,
      'relato': _relato.text,
      'testigos': _testigos.text,
      'observaciones': _observaciones.text,
    });
    if (!mounted) return;
    setState(() => _guardando = false);
    if (error == null) {
      _avisar('✅ Informe generado y subido', Colors.green);
    } else {
      _avisar(
        '⚠️ Informe guardado en el teléfono, pero el PDF no se subió: $error',
        Colors.orange,
      );
    }
    Navigator.pop(context, true);
  }

  void _avisar(String texto, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
  }

  String? _obligatorio(String? v) =>
      v == null || v.trim().isEmpty ? 'Obligatorio' : null;

  Widget _seccion(String titulo, VoidCallback dictado, String boton) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        TextButton.icon(
          onPressed: dictado,
          icon: const Icon(Icons.mic),
          label: Text(boton),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informe del incidente')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _guardando,
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Incidente del $_fecha',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    _seccion('DATOS DEL AGRESOR', _dictarAgresor, 'Dictar'),
                    TextFormField(
                      controller: _nombre,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        helperText:
                            'Si no lo conoces, escribe "Desconocido" y descríbelo abajo',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: _obligatorio,
                    ),
                    TextFormField(
                      controller: _ci,
                      decoration: const InputDecoration(
                        labelText: 'CI (opcional)',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('relacion $_relacion'),
                      initialValue: _relacion,
                      decoration: const InputDecoration(
                        labelText: 'Relación contigo',
                      ),
                      items: [
                        for (final r in relacionesAgresor)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (v) => setState(() => _relacion = v),
                    ),
                    TextFormField(
                      controller: _domicilio,
                      decoration: const InputDecoration(
                        labelText: 'Domicilio (opcional)',
                      ),
                    ),
                    TextFormField(
                      controller: _descripcion,
                      decoration: const InputDecoration(
                        labelText: 'Descripción física (opcional)',
                      ),
                      maxLines: 2,
                    ),
                    _seccion('HECHOS', _dictarHechos, 'Dictar'),
                    DropdownButtonFormField<String>(
                      key: ValueKey('tipo $_tipoDelito'),
                      initialValue: _tipoDelito,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de delito',
                      ),
                      items: [
                        for (final t in tiposDelito)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setState(() => _tipoDelito = v),
                    ),
                    TextFormField(
                      controller: _relato,
                      decoration: const InputDecoration(
                        labelText: 'Relato de lo ocurrido *',
                        alignLabelWithHint: true,
                      ),
                      minLines: 4,
                      maxLines: 10,
                      maxLength: _maxRelato,
                      validator: _obligatorio,
                    ),
                    TextFormField(
                      controller: _testigos,
                      decoration: const InputDecoration(
                        labelText: 'Testigos (opcional)',
                      ),
                    ),
                    TextFormField(
                      controller: _observaciones,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones (opcional)',
                        alignLabelWithHint: true,
                      ),
                      minLines: 2,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(
                        _guardando
                            ? 'Generando y subiendo PDF…'
                            : '💾 Guardar y generar informe',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _ci,
      _domicilio,
      _descripcion,
      _relato,
      _testigos,
      _observaciones,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
