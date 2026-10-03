import 'package:flutter/material.dart';
import '../services/dictado_parser.dart';
import '../services/informe_service.dart';
import '../widgets/dictado_sheet.dart';

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
  String _ciExt = 'LP';
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
      _fechaNacimiento = DateTime.tryParse(
        d['fecha_nacimiento'] as String? ?? '',
      );
      _cargando = false;
    });
  }

  Future<void> _dictar() async {
    final texto = await dictar(
      context,
      titulo: '🎤 Dicta tus datos',
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
    });
    if (!mounted) return;
    _avisar('✅ Datos guardados', Colors.green);
    Navigator.pop(context, true);
  }

  void _avisar(String texto, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
  }

  String? _obligatorio(String? v) =>
      v == null || v.trim().isEmpty ? 'Obligatorio' : null;

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
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Se usan para llenar el informe de denuncia de cada '
                    'incidente. Solo quedan guardados en este teléfono y en '
                    'los informes que generes.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _dictar,
                    icon: const Icon(Icons.mic),
                    label: const Text('🎤 Dictar mis datos'),
                  ),
                  const SizedBox(height: 16),
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
                        width: 90,
                        child: DropdownButtonFormField<String>(
                          // La clave lo reconstruye si el dictado cambia la ext.
                          key: ValueKey(_ciExt),
                          initialValue: _ciExt,
                          decoration: const InputDecoration(labelText: 'Ext.'),
                          items: [
                            for (final e in extensionesCi)
                              DropdownMenuItem(value: e, child: Text(e)),
                          ],
                          onChanged: (v) => setState(() => _ciExt = v!),
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de nacimiento'),
                    subtitle: Text(
                      f == null
                          ? 'Toca para elegir'
                          : formatearFechaNacimiento(f.toIso8601String()),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _elegirFecha,
                  ),
                  TextFormField(
                    controller: _domicilio,
                    decoration: const InputDecoration(labelText: 'Domicilio *'),
                    maxLines: 2,
                    validator: _obligatorio,
                  ),
                  TextFormField(
                    controller: _telefono,
                    decoration: const InputDecoration(labelText: 'Teléfono *'),
                    keyboardType: TextInputType.phone,
                    validator: _obligatorio,
                  ),
                  TextFormField(
                    controller: _ocupacion,
                    decoration: const InputDecoration(
                      labelText: 'Ocupación (opcional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _guardar,
                    icon: const Icon(Icons.save),
                    label: const Text('💾 Guardar'),
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
    super.dispose();
  }
}
