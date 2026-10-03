import 'package:flutter/material.dart';
import '../services/pin_service.dart';

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pinCtrl = TextEditingController();
  final _pinService = PinService();
  String _mensaje = '';

  Future<void> _verificar() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 4) {
      setState(() => _mensaje = 'El PIN debe tener 4 dígitos');
      return;
    }

    final tipo = await _pinService.verificarPin(pin);

    if (tipo == 'real') {
      // TODO: Aquí detendremos la alarma y el servicio en segundo plano
      if (mounted) {
        Navigator.pop(context, 'real');
      }
    } else if (tipo == 'falso') {
      // El PIN falso aparenta cerrar la alarma, pero mantiene la vigilancia.
      _mostrarFalsaAlarma();
    } else {
      setState(() => _mensaje = 'PIN incorrecto');
      _pinCtrl.clear();
    }
  }

  void _mostrarFalsaAlarma() {
    // Mostramos la pantalla de "cancelación exitosa" para engañar al agresor
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const _PantallaFalsaAlarma()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              const Text(
                'Ingresa tu PIN',
                style: TextStyle(color: Colors.white, fontSize: 22),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  letterSpacing: 10,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red),
                  ),
                ),
                onSubmitted: (_) => _verificar(),
              ),
              const SizedBox(height: 20),
              if (_mensaje.isNotEmpty)
                Text(
                  _mensaje,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _verificar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 14,
                  ),
                ),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }
}

// Pantalla que se muestra cuando se ingresa el PIN FALSO
// Simula que la app se cerró correctamente
class _PantallaFalsaAlarma extends StatefulWidget {
  const _PantallaFalsaAlarma();

  @override
  State<_PantallaFalsaAlarma> createState() => _PantallaFalsaAlarmaState();
}

class _PantallaFalsaAlarmaState extends State<_PantallaFalsaAlarma> {
  @override
  void initState() {
    super.initState();
    // Después de 3 segundos, cerramos esta pantalla (simulando que la app se cerró)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // TODO: Aquí en el futuro minimizaremos la app al home del teléfono
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 100),
            SizedBox(height: 20),
            Text(
              'Falsa Alarma',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'Cancelando servicio...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.green),
          ],
        ),
      ),
    );
  }
}
