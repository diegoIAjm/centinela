import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/configuracion_voz.dart';
import '../services/voz/configuracion_voz_store.dart';
import '../services/voz/motor_voz.dart';
import '../services/background_service.dart';
import '../services/database_service.dart';
import '../services/pin_service.dart';

String etiquetaEstadoVoz(String estado) => switch (estado) {
  'escuchando' => 'Escuchando dentro del horario',
  'esperando' => 'Esperando el próximo horario',
  'suspendida' => 'Escucha suspendida por pausa o alarma',
  'dictado' => 'Micrófono reservado para dictado',
  'error' => 'La escucha tiene un error',
  'sinServicio' => 'Activa la vigilancia para aplicar el horario',
  _ => 'Protección por voz desactivada',
};

class ConfiguracionVozScreen extends StatefulWidget {
  const ConfiguracionVozScreen({super.key});
  @override
  State<ConfiguracionVozScreen> createState() => _ConfiguracionVozScreenState();
}

class _ConfiguracionVozScreenState extends State<ConfiguracionVozScreen>
    with WidgetsBindingObserver {
  final _frases = TextEditingController();
  final _store = ConfiguracionVozStore();
  final _servicio = FlutterBackgroundService();
  StreamSubscription<Map<String, dynamic>?>? _sub;
  Timer? _reloj;
  bool _cargando = true;
  bool _ocupado = false;
  bool _modelo = false;
  bool _habilitada = false;
  bool _prueba = true;
  bool _cambios = false;
  Set<int> _dias = {1, 2, 3, 4, 5, 6, 7};
  int _inicio = 420;
  int _fin = 720;
  Map<String, dynamic> _estado = {'estado': 'sinServicio'};
  static const _nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _servicio.on('estado').listen((datos) {
      if (!mounted || datos?['voz'] is! Map) return;
      setState(() => _estado = Map<String, dynamic>.from(datos!['voz'] as Map));
    });
    _cargar();
    _reloj = Timer.periodic(const Duration(seconds: 10), (_) => _consultar());
  }

  Future<void> _cargar() async {
    try {
      final c = await _store.cargar();
      final modelo = await MotorVozLocal.modeloDisponible();
      if (!mounted) return;
      setState(() {
        _habilitada = c.habilitada;
        _prueba = c.modoPrueba;
        _dias = c.dias.toSet();
        _inicio = c.inicioMinutos;
        _fin = c.finMinutos;
        _frases.text = c.frases.join('\n');
        _modelo = modelo;
      });
    } catch (e) {
      _mensaje('No se pudo cargar la configuración: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    await _consultar();
  }

  Future<void> _consultar() async {
    final activo = await _servicio.isRunning();
    if (!mounted) return;
    if (activo) {
      _servicio.invoke('consultarEstado');
    } else {
      setState(() => _estado = {'estado': 'sinServicio'});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _consultar();
  }

  void _editar(VoidCallback accion) => setState(() {
    accion();
    _cambios = true;
  });
  String _hora(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _elegirHora(bool inicio) async {
    final m = inicio ? _inicio : _fin;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: inicio ? 'Inicio de escucha' : 'Fin de escucha',
    );
    if (t != null && mounted) {
      _editar(() {
        if (inicio) {
          _inicio = t.hour * 60 + t.minute;
        } else {
          _fin = t.hour * 60 + t.minute;
        }
      });
    }
  }

  Future<void> _descargar() async {
    setState(() => _ocupado = true);
    try {
      await MotorVozLocal.descargarModelo();
      if (!mounted) return;
      setState(() => _modelo = true);
      _servicio.invoke('recargarVoz');
      _mensaje(
        'Modelo instalado. El reconocimiento ya puede funcionar sin internet.',
      );
    } catch (e) {
      _mensaje('No se pudo instalar el modelo. Puedes reintentar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _guardar() async {
    final c = ConfiguracionVoz(
      habilitada: _habilitada,
      modoPrueba: _prueba,
      dias: _dias.toList()..sort(),
      inicioMinutos: _inicio,
      finMinutos: _fin,
      frases: _frases.text
          .split('\n')
          .map((f) => f.trim())
          .where((f) => f.isNotEmpty)
          .toList(),
    );
    if (c.error != null) {
      _mensaje(c.error!);
      return;
    }
    if (_habilitada && !_modelo) {
      _mensaje('Descarga primero el modelo español.');
      return;
    }
    if (_habilitada && !_prueba) {
      if ((await DatabaseService().obtenerContactos()).isEmpty) {
        _mensaje(
          'Añade un contacto de emergencia antes de habilitar alertas reales.',
        );
        return;
      }
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Activar alertas reales por voz?'),
          content: const Text(
            'Una coincidencia de frase activará la sirena, grabará audio y enviará SMS a tus contactos. También puede activarse por una televisión o por otra persona. Prueba tus frases antes de habilitar este modo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Activar alertas reales'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await _store.guardar(c);
      _servicio.invoke('recargarVoz');
      if (mounted) setState(() => _cambios = false);
      _mensaje('Configuración guardada. Revisa el estado de escucha debajo.');
    } catch (e) {
      _mensaje('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _activar() async {
    if (_cambios) {
      _mensaje('Guarda primero los cambios.');
      return;
    }
    if (!await PinService().estaConfigurado()) {
      _mensaje('Configura primero los dos PINs desde Inicio.');
      return;
    }
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await [
        Permission.microphone,
        Permission.locationWhenInUse,
        Permission.notification,
        Permission.sms,
        Permission.phone,
      ].request();
      if (!await Permission.microphone.isGranted ||
          !await Permission.locationWhenInUse.isGranted) {
        throw StateError('Concede los permisos de micrófono y ubicación.');
      }
      if (!_prueba && !await Permission.sms.isGranted) {
        throw StateError('Concede el permiso de SMS para alertas reales.');
      }
      await iniciarServicioSegundoPlano();
      _servicio.invoke('reanudar');
      _servicio.invoke('recargarVoz');
      await _consultar();
    } catch (e) {
      _mensaje('No se pudo activar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _mensaje(String texto) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(texto)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _sub?.cancel();
    _frases.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protección por voz')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Escucha programada',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Elige cuándo escuchar y qué frases activan tu alarma. La escucha se procesa en el teléfono; no guarda ni sube conversaciones mientras vigila.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Habilitar horario de voz'),
                  value: _habilitada,
                  onChanged: _ocupado
                      ? null
                      : (v) => _editar(() => _habilitada = v),
                ),
                const Text(
                  'Repetir',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text(_nombres[i - 1]),
                        selected: _dias.contains(i),
                        onSelected: _ocupado
                            ? null
                            : (v) => _editar(() {
                                if (v) {
                                  _dias.add(i);
                                } else {
                                  _dias.remove(i);
                                }
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : () => _elegirHora(true),
                      icon: const Icon(Icons.schedule),
                      label: Text('Desde ${_hora(_inicio)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : () => _elegirHora(false),
                      icon: const Icon(Icons.schedule),
                      label: Text('Hasta ${_hora(_fin)}'),
                    ),
                  ],
                ),
                Text(
                  _fin < _inicio
                      ? 'Termina al día siguiente. Los días elegidos son los de inicio.'
                      : 'Hora local del teléfono. El fin del horario deja de escuchar; no cancela una alarma en curso.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _frases,
                  enabled: !_ocupado,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1210,
                  onChanged: (_) => _editar(() {}),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Frases de activación',
                    helperText:
                        'Una por línea · 2 palabras como mínimo · hasta 10 frases',
                  ),
                ),
                const Text(
                  'Usa una frase poco habitual, por ejemplo «centinela necesito ayuda». Las coincidencias no distinguen quién habla ni interpretan el contexto.',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo de prueba (recomendado)'),
                  subtitle: const Text(
                    'La voz solo muestra la detección. No activa sirena, grabación ni envíos. El botón y el agitado conservan sus alertas reales.',
                  ),
                  value: _prueba,
                  onChanged: _ocupado
                      ? null
                      : (v) => _editar(() => _prueba = v),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(_modelo ? Icons.offline_pin : Icons.download),
                    title: Text(
                      _modelo
                          ? 'Modelo español instalado'
                          : 'Descargar modelo español · aprox. 39 MB',
                    ),
                    subtitle: const Text(
                      'Vosk · modelo small-es-0.42 · licencia Apache 2.0. Internet solo para esta descarga.',
                    ),
                    trailing: _modelo
                        ? null
                        : TextButton(
                            onPressed: _ocupado ? null : _descargar,
                            child: const Text('Descargar'),
                          ),
                  ),
                ),
                if (_ocupado) ...[
                  const LinearProgressIndicator(),
                  const Text(
                    'Procesando… Si estás descargando el modelo, puede tardar varios minutos.',
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _ocupado ? null : _guardar,
                  icon: const Icon(Icons.save),
                  label: Text(
                    _cambios ? 'Guardar cambios' : 'Guardar configuración',
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          etiquetaEstadoVoz(
                            _estado['estado'] as String? ?? 'sinServicio',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_cambios)
                          const Text(
                            'Hay cambios sin guardar. El servicio usa la configuración guardada.',
                          ),
                        if (_estado['error'] != null)
                          Text(_estado['error'].toString()),
                        if (_estado['ultimaDeteccion'] != null)
                          Text(
                            'Última coincidencia: ${_estado['ultimaDeteccion']}\n${_estado['fechaDeteccion'] ?? ''}',
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _ocupado || !_habilitada ? null : _activar,
                          child: const Text(
                            'Activar vigilancia / reintentar voz',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text(
                  'Para aplicar el horario, activa la vigilancia con la app abierta y mantén la notificación. La revisión del horario es aproximada (cada 5 segundos). La protección por voz aumenta el consumo de batería, también al esperar el horario. Después de reiniciar, forzar la detención o si Android cierra el servicio, debes abrir la app y volver a activarla.',
                ),
                const SizedBox(height: 12),
              ],
            ),
    );
  }
}
