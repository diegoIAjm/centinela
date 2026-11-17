import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/formulario_denuncia.dart';
import '../models/incidente.dart';
import '../services/dictado_parser.dart';
import '../services/informe_service.dart';
import '../widgets/dictado_sheet.dart';
import '../tema.dart';
import '../widgets/ui.dart';
import 'configuracion_denunciante_screen.dart';

const tiposDelito = [
  'Violencia física',
  'Violencia psicológica',
  'Violencia sexual',
  'Amenazas',
  'Acoso',
  'Violencia económica',
  'Robo',
  'Otro',
];

/// Formulario de denuncia de un incidente, con las secciones del Formulario
/// Único de Denuncias. Al guardar genera el PDF.
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

  /// Campos de texto y listas del resto del formulario ([CampoFormulario]).
  final _campos = <String, TextEditingController>{};
  final _opciones = <String, String?>{};
  Map<String, String> _guardado = const {};
  bool _victimaEsDenunciante = true;

  Incidente? _incidente;
  Map<String, dynamic> _denunciante = const {};
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final i = await _informes.obtenerIncidente(widget.idIncidente);
    final denunciante = await _informes.obtenerDatosDenunciante();
    if (!mounted) return;
    if (i == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _incidente = i;
      _denunciante = denunciante;
      _guardado = i.formulario;
      _victimaEsDenunciante = i.victimaEsDenunciante;
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

  Future<void> _recargarDenunciante() async {
    final d = await _informes.obtenerDatosDenunciante();
    if (mounted) setState(() => _denunciante = d);
  }

  TextEditingController _campo(String clave) => _campos.putIfAbsent(
    clave,
    () => TextEditingController(text: _guardado[clave] ?? ''),
  );

  Future<void> _dictarAgresor() async {
    final texto = await dictar(
      context,
      titulo: 'Datos de la persona denunciada',
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
      titulo: 'Relato del hecho',
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

  Future<void> _editarMisDatos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfiguracionDenuncianteScreen()),
    );
    await _recargarDenunciante();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      _avisar('Revisa los campos marcados en rojo.', Colors.orange);
      return;
    }
    if (!await _informes.datosDenuncianteCompletos()) {
      if (!mounted) return;
      final configurar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Faltan tus datos personales'),
          content: const Text(
            'El formulario necesita tu nombre, CI, domicilio y teléfono. '
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
        await _editarMisDatos();
        if (!mounted) return;
      }
    }

    setState(() => _guardando = true);
    final error = await _informes.completarIncidente(
      widget.idIncidente,
      {
        'nombre_agresor': _nombre.text,
        'ci_agresor': _ci.text,
        'relacion_agresor': _relacion,
        'domicilio_agresor': _domicilio.text,
        'descripcion_agresor': _descripcion.text,
        'tipo_delito': _tipoDelito,
        'relato': _relato.text,
        'testigos': _testigos.text,
        'observaciones': _observaciones.text,
      },
      formulario: {
        for (final e in _campos.entries)
          // Los datos de otra víctima no se guardan si la víctima eres tú.
          if (!_victimaEsDenunciante || !_esDeVictima(e.key))
            e.key: e.value.text,
        for (final e in _opciones.entries)
          if (e.value != null &&
              (!_victimaEsDenunciante || !_esDeVictima(e.key)))
            e.key: e.value!,
        CampoFormulario.victimaEsDenunciante: _victimaEsDenunciante
            ? 'si'
            : 'no',
      },
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (error == null) {
      _avisar('Formulario generado y subido', Colors.green);
    } else {
      _avisar(
        'Formulario guardado en el teléfono, pero el PDF no se subió: '
        '$error',
        Colors.orange,
      );
    }
    Navigator.pop(context, true);
  }

  static bool _esDeVictima(String clave) =>
      clave.startsWith('vic_') || clave == CampoFormulario.relacionConVictima;

  void _avisar(String texto, Color color) {
    mostrarMensaje(
      context,
      texto,
      tipo: color == Colors.green
          ? TipoAviso.exito
          : color == Colors.orange
          ? TipoAviso.aviso
          : TipoAviso.peligro,
    );
  }

  Future<void> _abrir(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      _avisar('No se pudo abrir el enlace', Colors.red);
    }
  }

  String? _obligatorio(String? v) =>
      v == null || v.trim().isEmpty ? 'Obligatorio' : null;

  // ===================== WIDGETS =====================

  Widget _seccion(String titulo, {VoidCallback? dictado}) => EncabezadoSeccion(
    titulo,
    accion: dictado == null
        ? null
        : TextButton.icon(
            onPressed: dictado,
            icon: const Icon(Icons.mic_none),
            label: const Text('Dictar'),
          ),
  );

  /// Tarjeta con los campos de una sección, separados de forma uniforme.
  Widget _bloque(List<Widget> campos) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var n = 0; n < campos.length; n++) ...[
            if (n > 0) const SizedBox(height: 14),
            campos[n],
          ],
        ],
      ),
    ),
  );

  Widget _texto(
    String clave,
    String etiqueta, {
    String? ayuda,
    TextInputType? teclado,
    bool obligatorio = false,
    int lineas = 1,
  }) => TextFormField(
    controller: _campo(clave),
    decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
    keyboardType: teclado,
    minLines: lineas,
    maxLines: lineas,
    textCapitalization: TextCapitalization.sentences,
    validator: obligatorio ? _obligatorio : null,
  );

  Widget _lista(String clave, String etiqueta, List<String> valores) {
    final actual = _opciones.containsKey(clave)
        ? _opciones[clave]
        : _guardado[clave];
    return DropdownButtonFormField<String>(
      key: ValueKey('$clave $actual'),
      initialValue: valores.contains(actual) ? actual : null,
      decoration: InputDecoration(labelText: etiqueta),
      items: [
        for (final v in valores) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (v) => setState(() => _opciones[clave] = v),
    );
  }

  Widget _resumenDenunciante() {
    String? v(String clave) {
      final valor = (_denunciante[clave] as String?)?.trim();
      return valor == null || valor.isEmpty ? null : valor;
    }

    final nombre = v('nombre_completo');
    final ci = v('ci');
    if (nombre == null) {
      return Aviso(
        tipo: TipoAviso.aviso,
        titulo: 'Aún no completaste tus datos personales',
        texto: 'Se usan en todos tus formularios de denuncia.',
        accion: 'Completar ahora',
        onTap: _editarMisDatos,
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(nombre),
        subtitle: Text(
          [
            if (ci != null) 'C.I. $ci ${v('ci_ext') ?? ''}'.trim(),
            ?v('domicilio'),
          ].join(' · '),
        ),
        trailing: const Icon(Icons.edit_outlined, color: Paleta.marino),
        onTap: _editarMisDatos,
      ),
    );
  }

  Widget _pruebas(Incidente i) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            'Se registraron al activarse la alarma y se incluyen como enlaces '
            'en el formulario.',
            style: TextStyle(color: Paleta.textoSecundario),
          ),
        ),
        if (i.urlsAudio.isEmpty)
          const ListTile(
            leading: Icon(Icons.headset_off_outlined),
            title: Text('Sin grabaciones de audio subidas'),
          )
        else
          for (var n = 0; n < i.urlsAudio.length; n++)
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text('Grabación de audio N.º ${n + 1}'),
              subtitle: Text(
                i.urlsAudio[n],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () => _abrir(i.urlsAudio[n]),
            ),
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: const Text('Ubicación GPS'),
          subtitle: Text(
            i.linkMaps == null ? 'No disponible' : '${i.lat}, ${i.lon}',
          ),
          trailing: i.linkMaps == null
              ? null
              : const Icon(Icons.open_in_new, size: 20),
          onTap: i.linkMaps == null ? null : () => _abrir(i.linkMaps!),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: TextFormField(
            controller: _testigos,
            decoration: const InputDecoration(
              labelText: 'Testigos (opcional)',
              helperText: 'Nombre y cómo contactarlos, si los hubo',
            ),
            maxLines: 2,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final i = _incidente;
    return Scaffold(
      appBar: AppBar(title: const Text('Formulario de denuncia')),
      body: _cargando || i == null
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _guardando,
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const Aviso(
                      tipo: TipoAviso.info,
                      titulo: 'Llena lo que sepas',
                      texto:
                          'Lo que dejes vacío aparecerá como "Dato no '
                          'consignado". Los campos con * son obligatorios.',
                    ),

                    _seccion('Lugar y fecha del hecho'),
                    _bloque([
                      Row(
                        children: [
                          const Icon(Icons.event_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatearFecha(i.fecha),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const Text(
                                  'Activación de la alarma',
                                  style: TextStyle(
                                    color: Paleta.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      _texto(
                        CampoFormulario.horarioHecho,
                        'Horario aproximado del hecho',
                        ayuda: 'Ej.: entre 22:25 y 22:40',
                      ),
                      _texto(CampoFormulario.municipio, 'Municipio'),
                      _texto(CampoFormulario.zona, 'Zona'),
                      _texto(
                        CampoFormulario.direccionHecho,
                        'Dirección',
                        ayuda: 'Calle, número, departamento…',
                      ),
                    ]),

                    _seccion('1. Relato del hecho', dictado: _dictarHechos),
                    _bloque([
                      DropdownButtonFormField<String>(
                        key: ValueKey('tipo $_tipoDelito'),
                        initialValue: tiposDelito.contains(_tipoDelito)
                            ? _tipoDelito
                            : null,
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
                          helperText:
                              'Qué pasó, en orden, con horas si las sabes',
                          alignLabelWithHint: true,
                        ),
                        minLines: 5,
                        maxLines: 12,
                        maxLength: _maxRelato,
                        validator: _obligatorio,
                      ),
                    ]),

                    _seccion('2. Persona denunciada', dictado: _dictarAgresor),
                    _bloque([
                      TextFormField(
                        controller: _nombre,
                        decoration: const InputDecoration(
                          labelText: 'Nombres y apellidos *',
                          helperText:
                              'Si no lo conoces, escribe "Desconocido" y '
                              'descríbelo abajo',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _obligatorio,
                      ),
                      TextFormField(
                        controller: _ci,
                        decoration: const InputDecoration(labelText: 'C.I.'),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('relacion $_relacion'),
                        initialValue: relacionesAgresor.contains(_relacion)
                            ? _relacion
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Relación con la víctima',
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
                          labelText: 'Domicilio',
                        ),
                      ),
                      TextFormField(
                        controller: _descripcion,
                        decoration: const InputDecoration(
                          labelText: 'Descripción física',
                        ),
                        maxLines: 2,
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        title: const Text('Más datos del denunciado'),
                        subtitle: const Text('Opcionales, si los conoces'),
                        children: [
                          for (final campo in [
                            _lista(CampoFormulario.denSexo, 'Sexo', sexos),
                            _texto(
                              CampoFormulario.denFechaNacimiento,
                              'Fecha de nacimiento o edad aproximada',
                            ),
                            _lista(
                              CampoFormulario.denEstadoCivil,
                              'Estado civil',
                              estadosCiviles,
                            ),
                            _texto(
                              CampoFormulario.denTelefono,
                              'Teléfono y celular',
                              teclado: TextInputType.phone,
                            ),
                            _texto(
                              CampoFormulario.denCorreo,
                              'Correo electrónico',
                              teclado: TextInputType.emailAddress,
                            ),
                            _texto(
                              CampoFormulario.denLugarNacimiento,
                              'Lugar de nacimiento',
                            ),
                            _lista(
                              CampoFormulario.denEducacion,
                              'Nivel de educación',
                              nivelesEducacion,
                            ),
                            _texto(
                              CampoFormulario.denOcupacion,
                              'Profesión u ocupación',
                            ),
                            _texto(
                              CampoFormulario.denLugarTrabajo,
                              'Lugar de trabajo',
                            ),
                            _texto(CampoFormulario.denIdioma, 'Idioma'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: campo,
                            ),
                        ],
                      ),
                    ]),

                    _seccion('3. Datos del denunciante'),
                    _resumenDenunciante(),

                    _seccion('4. Datos de la víctima'),
                    _bloque([
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Yo soy la víctima'),
                        subtitle: const Text(
                          'Desactívalo si denuncias lo que le pasó a otra '
                          'persona',
                        ),
                        value: _victimaEsDenunciante,
                        onChanged: (v) =>
                            setState(() => _victimaEsDenunciante = v),
                      ),
                      if (!_victimaEsDenunciante) ...[
                        _texto(
                          CampoFormulario.vicNombre,
                          'Nombres y apellidos de la víctima *',
                          obligatorio: true,
                        ),
                        _texto(
                          CampoFormulario.relacionConVictima,
                          'Tu relación con la víctima *',
                          ayuda: 'Ej.: hermana, madre, amiga',
                          obligatorio: true,
                        ),
                        _texto(CampoFormulario.vicCi, 'C.I.'),
                        _lista(CampoFormulario.vicSexo, 'Sexo', sexos),
                        _texto(
                          CampoFormulario.vicFechaNacimiento,
                          'Fecha de nacimiento o edad',
                        ),
                        _lista(
                          CampoFormulario.vicEstadoCivil,
                          'Estado civil',
                          estadosCiviles,
                        ),
                        _texto(CampoFormulario.vicNacionalidad, 'Nacionalidad'),
                        _texto(
                          CampoFormulario.vicOcupacion,
                          'Profesión u ocupación',
                        ),
                        _texto(CampoFormulario.vicDomicilio, 'Domicilio'),
                        _texto(
                          CampoFormulario.vicLugarTrabajo,
                          'Lugar de trabajo',
                        ),
                        _texto(
                          CampoFormulario.vicTelefono,
                          'Teléfono y celular',
                          teclado: TextInputType.phone,
                        ),
                      ],
                    ]),

                    _seccion('5. Pruebas y evidencias'),
                    _pruebas(i),

                    _seccion('6. Observaciones'),
                    _bloque([
                      TextFormField(
                        controller: _observaciones,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones (opcional)',
                          alignLabelWithHint: true,
                        ),
                        minLines: 3,
                        maxLines: 6,
                      ),
                    ]),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _guardando
                            ? 'Generando y subiendo PDF…'
                            : 'Guardar y generar formulario',
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
      ..._campos.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
