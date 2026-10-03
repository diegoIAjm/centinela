import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/pin_service.dart';
import '../widgets/deslizar_para_confirmar.dart';

class AlarmaActivaScreen extends StatefulWidget {
  final bool alarmaYaActiva;

  const AlarmaActivaScreen({super.key, this.alarmaYaActiva = false});

  /// Evita apilar dos pantallas de alarma.
  static bool visible = false;

  static const _pantalla = MethodChannel('com.example.centinela/pantalla');

  /// Solo mientras la alarma está en pantalla la app se muestra sobre el
  /// bloqueo; así contactos y PINs no quedan expuestos sin desbloquear.
  static Future<void> mostrarSobreBloqueo(bool activo) async {
    try {
      await _pantalla.invokeMethod('mostrarSobreBloqueo', activo);
    } on PlatformException catch (e) {
      debugPrint('⚠️ No se pudo cambiar la vista sobre bloqueo: $e');
    }
  }

  @override
  State<AlarmaActivaScreen> createState() => _AlarmaActivaScreenState();
}

class _AlarmaActivaScreenState extends State<AlarmaActivaScreen> {
  final _pinService = PinService();
  final _pinCtrl = TextEditingController();
  String _mensaje = '';
  bool _mostrandoPins = false;
  List<String> _bitacora = const [];
  StreamSubscription<Map<String, dynamic>?>? _estado;

  @override
  void initState() {
    super.initState();
    AlarmaActivaScreen.visible = true;
    AlarmaActivaScreen.mostrarSobreBloqueo(true);
    final servicio = FlutterBackgroundService();
    _estado = servicio.on('estado').listen((datos) {
      final bitacora = datos?['bitacora'];
      if (!mounted || bitacora is! List) return;
      setState(() => _bitacora = List<String>.from(bitacora));
    });
    if (!widget.alarmaYaActiva) {
      servicio.invoke('activarAlarma');
    }
    servicio.invoke('consultarEstado');
  }

  Future<void> _verificarPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 4) {
      setState(() => _mensaje = 'El PIN debe tener 4 dígitos');
      return;
    }

    final tipo = await _pinService.verificarPin(pin);

    if (tipo == 'real') {
      FlutterBackgroundService().invoke('cancelarAlarma');
      _salir('✅ Alarma cancelada');
    } else if (tipo == 'falso') {
      // Misma UI que el PIN real; en segundo plano la alarma sigue.
      FlutterBackgroundService().invoke('falsaAlarma');
      _salir('✅ Alarma cancelada');
    } else {
      setState(() => _mensaje = 'PIN incorrecto');
      _pinCtrl.clear();
    }
  }

  /// Lo que el servicio va haciendo de verdad: SMS, subidas y errores.
  Widget _panelBitacora() {
    final ultimos = _bitacora.length > 8
        ? _bitacora.sublist(_bitacora.length - 8)
        : _bitacora;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ultimos.isEmpty
          ? const Text(
              'Esperando al servicio…',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final linea in ultimos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      linea,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }

  void _estoyASalvo() {
    FlutterBackgroundService().invoke('estoyASalvo');
    _salir('✅ Alarma detenida. Avisamos a tus contactos que estás a salvo.');
  }

  void _salir(String mensaje) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Solo se sale con PIN o con "Estoy a salvo".
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 100,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'ALARMA ACTIVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Grabando audio y enviando ubicación...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _panelBitacora(),
                  const SizedBox(height: 24),
                  if (!_mostrandoPins) ...[
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _mostrandoPins = true),
                      icon: const Icon(Icons.lock),
                      label: const Text('Ingresar PIN para cancelar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Ingresa tu PIN',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pinCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        letterSpacing: 15,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onSubmitted: (_) => _verificarPin(),
                    ),
                    const SizedBox(height: 10),
                    if (_mensaje.isNotEmpty)
                      Text(
                        _mensaje,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _verificarPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 50,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Aceptar'),
                    ),
                  ],
                  const SizedBox(height: 40),
                  DeslizarParaConfirmar(
                    texto: 'Estoy a salvo',
                    icono: Icons.shield,
                    onConfirmado: _estoyASalvo,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    AlarmaActivaScreen.visible = false;
    _estado?.cancel();
    AlarmaActivaScreen.mostrarSobreBloqueo(false);
    _pinCtrl.dispose();
    super.dispose();
  }
}
