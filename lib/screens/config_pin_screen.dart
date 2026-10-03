import 'package:flutter/material.dart';
import '../services/pin_service.dart';

class ConfigPinScreen extends StatefulWidget {
  const ConfigPinScreen({super.key});

  @override
  State<ConfigPinScreen> createState() => _ConfigPinScreenState();
}

class _ConfigPinScreenState extends State<ConfigPinScreen> {
  final _pinRealCtrl = TextEditingController();
  final _pinFalsoCtrl = TextEditingController();
  final _pinService = PinService();
  bool _cargando = false;

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

  Future<void> _guardar() async {
    final real = _pinRealCtrl.text.trim();
    final falso = _pinFalsoCtrl.text.trim();

    // Validaciones
    if (real.length != 4 || falso.length != 4) {
      _mostrarMensaje('Ambos PINs deben tener exactamente 4 dígitos');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(real) ||
        !RegExp(r'^\d{4}$').hasMatch(falso)) {
      _mostrarMensaje('Los PINs solo deben contener números');
      return;
    }
    if (real == falso) {
      _mostrarMensaje('El PIN real y el PIN falso NO pueden ser iguales');
      return;
    }

    setState(() => _cargando = true);
    await _pinService.guardarPines(real, falso);
    setState(() => _cargando = false);

    if (mounted) {
      _mostrarMensaje('PINs guardados correctamente', esError: false);
      Navigator.pop(context);
    }
  }

  void _mostrarMensaje(String msg, {bool esError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar PINs'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Card(
              color: Color(0xFFFFEBEE),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PIN Real',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Este PIN detiene la alarma real y cancela todo. Úsalo solo cuando estés a salvo.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinRealCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN Real (4 dígitos)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            const Card(
              color: Color(0xFFFFF3E0),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PIN Falso (Coacción)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Úsalo si alguien te obliga a apagar la app. Parecerá que se cerró, pero seguirá grabando y enviando tu ubicación.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinFalsoCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN Falso (4 dígitos)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _cargando ? null : _guardar,
              icon: _cargando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_cargando ? 'Guardando...' : 'Guardar PINs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
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
