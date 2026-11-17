import 'package:flutter/material.dart';
import '../services/pin_service.dart';
import '../tema.dart';
import '../widgets/ui.dart';

class ConfigPinScreen extends StatefulWidget {
  const ConfigPinScreen({super.key});

  @override
  State<ConfigPinScreen> createState() => _ConfigPinScreenState();
}

class _ConfigPinScreenState extends State<ConfigPinScreen> {
  final _form = GlobalKey<FormState>();
  final _pinRealCtrl = TextEditingController();
  final _pinFalsoCtrl = TextEditingController();
  final _pinService = PinService();
  bool _cargando = false;
  bool _mostrar = false;

  @override
  void initState() {
    super.initState();
    _cargarPinesExistentes();
  }

  Future<void> _cargarPinesExistentes() async {
    final real = await _pinService.obtenerPinReal();
    final falso = await _pinService.obtenerPinFalso();
    if (real != null) _pinRealCtrl.text = real;
    if (falso != null) _pinFalsoCtrl.text = falso;
  }

  String? _validarPin(String? v) {
    final pin = v?.trim() ?? '';
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return 'Debe tener 4 números';
    return null;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final real = _pinRealCtrl.text.trim();
    final falso = _pinFalsoCtrl.text.trim();
    if (real == falso) {
      mostrarMensaje(
        context,
        'El PIN real y el PIN de coacción deben ser distintos',
        tipo: TipoAviso.peligro,
      );
      return;
    }

    setState(() => _cargando = true);
    await _pinService.guardarPines(real, falso);
    if (!mounted) return;
    setState(() => _cargando = false);
    mostrarMensaje(context, 'PIN guardados', tipo: TipoAviso.exito);
    Navigator.pop(context);
  }

  Widget _campoPin(TextEditingController c, String etiqueta) => TextFormField(
    controller: c,
    keyboardType: TextInputType.number,
    maxLength: 4,
    obscureText: !_mostrar,
    style: const TextStyle(fontSize: 22, letterSpacing: 8),
    decoration: InputDecoration(labelText: etiqueta, counterText: ''),
    validator: _validarPin,
  );

  Widget _explicacion(IconData icono, String titulo, String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, color: Paleta.marino),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(texto),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PIN de seguridad')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Column(
                  children: [
                    _explicacion(
                      Icons.lock_open,
                      'PIN real',
                      'Detiene la alarma y cancela el envío. Úsalo solo cuando '
                          'estés a salvo.',
                    ),
                    _explicacion(
                      Icons.visibility_off_outlined,
                      'PIN de coacción',
                      'Úsalo si alguien te obliga a apagar la alarma. Parecerá '
                          'que se detuvo, pero seguirá grabando y enviando tu '
                          'ubicación.',
                    ),
                  ],
                ),
              ),
            ),
            const EncabezadoSeccion('Tus PIN'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _campoPin(_pinRealCtrl, 'PIN real (4 números)'),
                    const SizedBox(height: 14),
                    _campoPin(_pinFalsoCtrl, 'PIN de coacción (4 números)'),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar los números'),
                      value: _mostrar,
                      onChanged: (v) => setState(() => _mostrar = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargando ? null : _guardar,
              icon: _cargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_cargando ? 'Guardando…' : 'Guardar PIN'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinRealCtrl.dispose();
    _pinFalsoCtrl.dispose();
    super.dispose();
  }
}
