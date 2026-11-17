import 'package:flutter/material.dart';
import '../models/formulario_denuncia.dart';
import '../services/dictado_parser.dart';
import '../services/informe_service.dart';
import '../tema.dart';
import '../widgets/dictado_sheet.dart';
import '../widgets/ui.dart';

/// Datos permanentes de la víctima para el informe de denuncia.
class ConfiguracionDenuncianteScreen extends StatefulWidget {
  const ConfiguracionDenuncianteScreen({super.key});

  @override
  State<ConfiguracionDenuncianteScreen> createState() =>
      _ConfiguracionDenuncianteScreenState();
}

class _ConfiguracionDenuncianteScreenState
    extends State<ConfiguracionDenuncianteScreen> {
  final _informes = InformeService();
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _ci = TextEditingController();
  final _domicilio = TextEditingController();
  final _telefono = TextEditingController();
  final _ocupacion = TextEditingController();
  final _nacionalidad = TextEditingController();
  final _lugarTrabajo = TextEditingController();
  final _correo = TextEditingController();
  String _ciExt = 'LP';
  String? _sexo;
  String? _estadoCivil;
  bool _reservarContacto = false;
  DateTime? _fechaNacimiento;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final d = await _informes.obtenerDatosDenunciante();
    if (!mounted) return;
    setState(() {
      _nombre.text = d['nombre_completo'] as String? ?? '';
      _ci.text = d['ci'] as String? ?? '';
      _ciExt = d['ci_ext'] as String? ?? 'LP';
      _domicilio.text = d['domicilio'] as String? ?? '';
      _telefono.text = d['telefono'] as String? ?? '';
      _ocupacion.text = d['ocupacion'] as String? ?? '';
      _nacionalidad.text = d['nacionalidad'] as String? ?? 'Boliviana';
      _lugarTrabajo.text = d['lugar_trabajo'] as String? ?? '';
      _correo.text = d['correo'] as String? ?? '';
      _sexo = sexos.contains(d['sexo']) ? d['sexo'] as String : null;
      _estadoCivil = estadosCiviles.contains(d['estado_civil'])
          ? d['estado_civil'] as String
          : null;
      _reservarContacto = d['reservar_contacto'] == true;
      _fechaNacimiento = DateTime.tryParse(
        d['fecha_nacimiento'] as String? ?? '',
      );
      _cargando = false;
    });
  }

  Future<void> _dictar() async {
    final texto = await dictar(
      context,
      titulo: 'Dicta tus datos',
      ayuda:
          'Ejemplo: "Mi nombre es María Pérez, mi carnet es 12345678 LP, '
          'nací el 5 de marzo de 1990, mi domicilio es calle Sucre 45, '
          'mi teléfono es 71234567 y trabajo como enfermera."',
    );
    if (texto == null || !mounted) return;
    final campos = interpretarDenunciante(texto);
    if (campos.isEmpty) {
      _avisar(
        'No reconocí ningún dato. Empieza cada dato con "mi nombre es", '
        '"mi carnet es", "vivo en"…',
        Colors.orange,
      );
      return;
    }
    setState(() {
      if (campos['nombre_completo'] case final v?) _nombre.text = v;
      if (campos['ci'] case final v?) _ci.text = v;
      if (campos['ci_ext'] case final v?) _ciExt = v;
      if (campos['domicilio'] case final v?) _domicilio.text = v;
      if (campos['telefono'] case final v?) _telefono.text = v;
      if (campos['ocupacion'] case final v?) _ocupacion.text = v;
      if (campos['fecha_nacimiento'] case final v?) {
        _fechaNacimiento = DateTime.parse(v);
      }
    });
    _avisar(
      'Se completaron ${campos.length} dato(s). Revísalos antes de guardar.',
      Colors.green,
    );
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(1995),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Fecha de nacimiento',
    );
    if (f != null) setState(() => _fechaNacimiento = f);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    String dos(int n) => n.toString().padLeft(2, '0');
    final f = _fechaNacimiento;
    await _informes.guardarDatosDenunciante({
      'nombre_completo': _nombre.text.trim(),
      'ci': _ci.text.trim(),
      'ci_ext': _ciExt,
      'fecha_nacimiento': f == null
          ? null
          : '${f.year}-${dos(f.month)}-${dos(f.day)}',
      'domicilio': _domicilio.text.trim(),
      'telefono': _telefono.text.trim(),
      'ocupacion': _ocupacion.text.trim(),
      'sexo': _sexo,
      'estado_civil': _estadoCivil,
      'nacionalidad': _nacionalidad.text.trim(),
      'lugar_trabajo': _lugarTrabajo.text.trim(),
      'correo': _correo.text.trim(),
      'reservar_contacto': _reservarContacto,
    });
    if (!mounted) return;
    _avisar('Datos guardados', Colors.green);
    Navigator.pop(context, true);
  }

  void _avisar(String texto, Color color) {
    mostrarMensaje(
      context,
      texto,
      tipo: color == Colors.green ? TipoAviso.exito : TipoAviso.aviso,
    );
  }

  String? _obligatorio(String? v) =>
      v == null || v.trim().isEmpty ? 'Obligatorio' : null;

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

  Widget _lista(
    String etiqueta,
    String? valor,
    List<String> opciones,
    ValueChanged<String?> alCambiar,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$etiqueta $valor'),
    initialValue: valor,
    decoration: InputDecoration(labelText: etiqueta),
    items: [
      for (final v in opciones) DropdownMenuItem(value: v, child: Text(v)),
    ],
    onChanged: alCambiar,
  );

  @override
  Widget build(BuildContext context) {
    final f = _fechaNacimiento;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis datos personales')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  const Aviso(
                    tipo: TipoAviso.info,
                    titulo: 'Para tus formularios de denuncia',
                    texto:
                        'Se guardan solo en este teléfono y en los formularios '
                        'que generes. Los campos con * son obligatorios.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _dictar,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('Dictar mis datos'),
                  ),
                  const EncabezadoSeccion('Identificación'),
                  _bloque([
                    TextFormField(
                      controller: _nombre,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo *',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: _obligatorio,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ci,
                            decoration: const InputDecoration(
                              labelText: 'Carnet de identidad *',
                            ),
                            keyboardType: TextInputType.number,
                            validator: _obligatorio,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 104,
                          child: DropdownButtonFormField<String>(
                            // La clave lo reconstruye si el dictado cambia la ext.
                            key: ValueKey(_ciExt),
                            initialValue: _ciExt,
                            decoration: const InputDecoration(
                              labelText: 'Ext.',
                            ),
                            items: [
                              for (final e in extensionesCi)
                                DropdownMenuItem(value: e, child: Text(e)),
                            ],
                            onChanged: (v) => setState(() => _ciExt = v!),
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _elegirFecha,
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de nacimiento',
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          f == null
                              ? 'Toca para elegir'
                              : formatearFechaNacimiento(f.toIso8601String()),
                          style: TextStyle(
                            fontSize: 16,
                            color: f == null
                                ? Paleta.textoSecundario
                                : Paleta.texto,
                          ),
                        ),
                      ),
                    ),
                    _lista(
                      'Sexo',
                      _sexo,
                      sexos,
                      (v) => setState(() => _sexo = v),
                    ),
                    _lista(
                      'Estado civil',
                      _estadoCivil,
                      estadosCiviles,
                      (v) => setState(() => _estadoCivil = v),
                    ),
                    TextFormField(
                      controller: _nacionalidad,
                      decoration: const InputDecoration(
                        labelText: 'Nacionalidad',
                      ),
                    ),
                  ]),
                  const EncabezadoSeccion('Domicilio y contacto'),
                  _bloque([
                    TextFormField(
                      controller: _domicilio,
                      decoration: const InputDecoration(
                        labelText: 'Domicilio *',
                      ),
                      maxLines: 2,
                      validator: _obligatorio,
                    ),
                    TextFormField(
                      controller: _telefono,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono *',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: _obligatorio,
                    ),
                    TextFormField(
                      controller: _correo,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ocultar teléfono y correo'),
                      subtitle: const Text(
                        'En el formulario aparecerán como "Dato reservado".',
                      ),
                      value: _reservarContacto,
                      onChanged: (v) => setState(() => _reservarContacto = v),
                    ),
                  ]),
                  const EncabezadoSeccion('Trabajo'),
                  _bloque([
                    TextFormField(
                      controller: _ocupacion,
                      decoration: const InputDecoration(
                        labelText: 'Profesión u ocupación',
                      ),
                    ),
                    TextFormField(
                      controller: _lugarTrabajo,
                      decoration: const InputDecoration(
                        labelText: 'Lugar de trabajo',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _guardar,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar mis datos'),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nombre.dispose();
    _ci.dispose();
    _domicilio.dispose();
    _telefono.dispose();
    _ocupacion.dispose();
    _nacionalidad.dispose();
    _lugarTrabajo.dispose();
    _correo.dispose();
    super.dispose();
  }
}
