import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'contactos_screen.dart';
import 'config_pin_screen.dart';
import '../navegacion.dart';
import '../services/pin_service.dart';
import '../services/background_service.dart';
import '../services/notificacion_alarma.dart';
import 'package:centinela_nativo/centinela_nativo.dart';
import '../models/incidente.dart';
import '../services/informe_service.dart';
import 'configuracion_denunciante_screen.dart';
import 'historial_incidentes_screen.dart';

class _OpcionPausa {
  final String etiqueta;
  final int? minutos;
  final bool indefinida;

  const _OpcionPausa(this.etiqueta, this.minutos) : indefinida = false;

  const _OpcionPausa.indefinida(this.etiqueta)
    : minutos = null,
      indefinida = true;
}

const _opcionesPausa = [
  _OpcionPausa('Solo 30 minutos', 30),
  _OpcionPausa('1 hora', 60),
  _OpcionPausa('2 horas', 120),
  _OpcionPausa('4 horas', 240),
  _OpcionPausa('8 horas', 480),
  _OpcionPausa('12 horas', 720),
  _OpcionPausa('24 horas', 1440),
  _OpcionPausa.indefinida('Indefinido (hasta reactivar manualmente)'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _pinService = PinService();
  bool _pinesConfigurados = false;
  bool _sensoresActivos = false;
  bool _iniciando = false;
  StreamSubscription<Map<String, dynamic>?>? _servicioEventos;
  String? _ultimoError;
  List<String> _bitacora = const [];
  bool _abreSobreBloqueo = true;
  StreamSubscription<Map<String, dynamic>?>? _incidentesEventos;
  bool _datosDenuncianteCompletos = false;
  int _incidentes = 0;
  int _incidentesPendientes = 0;
  bool _alarmaFalsaActiva = false;
  String? _pausaEtiqueta;
  bool _pausaIndefinida = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _incidentesEventos = FlutterBackgroundService()
        .on('incidenteFinalizado')
        .listen((datos) async {
          final id = datos?['id'];
          if (id is! int) return;
          await _actualizarInformes();
          await ofrecerCompletarInforme(id);
          _actualizarInformes();
        });
    _actualizarInformes();
    _servicioEventos = FlutterBackgroundService().on('estado').listen((datos) {
      if (!mounted || datos == null) return;
      setState(() {
        _sensoresActivos = datos['vigilando'] == true;
        _alarmaFalsaActiva = datos['alarma'] == 'falsaAlarma';
        if (_sensoresActivos) {
          _pausaEtiqueta = null;
          _pausaIndefinida = false;
        } else if (datos['pausaIndefinida'] == true) {
          _pausaEtiqueta = null;
          _pausaIndefinida = true;
        } else if (datos['pausaEtiqueta'] is String) {
          _pausaEtiqueta = datos['pausaEtiqueta'] as String;
          _pausaIndefinida = false;
        }
        final bitacora = datos['bitacora'];
        if (bitacora is List) _bitacora = List<String>.from(bitacora);
      });
      // El servicio reenvía el estado a menudo: avisar cada error una vez.
      final error = datos['error'] as String?;
      if (error != null && error != _ultimoError) {
        _mostrarMensaje(error, Colors.red);
      }
      _ultimoError = error;
      if (datos['alarma'] == 'activa') _abrirAlarmaActiva();
    });
    _verificarConfiguracion();
    _verificarAperturaSobreBloqueo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FlutterBackgroundService().invoke('consultarEstado');
      _verificarAperturaSobreBloqueo();
      _actualizarInformes();
    }
  }

  Future<void> _actualizarInformes() async {
    final informes = InformeService();
    final completos = await informes.datosDenuncianteCompletos();
    final historial = await informes.obtenerHistorial();
    if (!mounted) return;
    setState(() {
      _datosDenuncianteCompletos = completos;
      _incidentes = historial.length;
      _incidentesPendientes = historial
          .where((i) => i.estado != EstadoInforme.completo)
          .length;
    });
  }

  /// Para que la alarma entre directo con el teléfono bloqueado hace falta
  /// "pantalla completa" (Android 14+) o "mostrar sobre otras apps".
  Future<void> _verificarAperturaSobreBloqueo() async {
    try {
      final p = await CentinelaNativo.puedeAbrirSobreBloqueo();
      if (mounted) {
        setState(() => _abreSobreBloqueo = p.pantallaCompleta && p.superponer);
      }
    } catch (_) {}
  }

  Future<void> _pedirAperturaSobreBloqueo() async {
    final p = await CentinelaNativo.puedeAbrirSobreBloqueo();
    if (!p.superponer) {
      await Permission.systemAlertWindow.request();
    } else if (!p.pantallaCompleta) {
      await solicitarPermisoPantallaCompleta();
    }
    await _verificarAperturaSobreBloqueo();
  }

  void _abrirAlarmaActiva() {
    if (!mounted) return;
    abrirPantallaAlarma();
  }

  Future<void> _verificarConfiguracion() async {
    final config = await _pinService.estaConfigurado();
    if (!mounted) return;
    setState(() => _pinesConfigurados = config);
    if (config && !_sensoresActivos) {
      await _iniciarVigilancia();
    }
  }

  Future<void> _iniciarVigilancia() async {
    if (_iniciando) return;
    if (!_pinesConfigurados) {
      _mostrarMensaje(
        'Configura los dos PINs antes de activar la protección.',
        Colors.red,
      );
      return;
    }
    _iniciando = true;
    try {
      await [
        Permission.microphone,
        Permission.locationWhenInUse,
        Permission.sms,
        Permission.notification,
        Permission.phone,
      ].request();
      final microfono = await Permission.microphone.status;
      final ubicacion = await Permission.locationWhenInUse.status;
      final sms = await Permission.sms.status;

      if (!microfono.isGranted || !ubicacion.isGranted || !sms.isGranted) {
        if (mounted) {
          _mostrarMensaje(
            'Habilita micrófono, ubicación y SMS en los permisos de Centinela.',
            Colors.red,
          );
        }
        return;
      }

      await iniciarServicioSegundoPlano();
    } catch (e) {
      _mostrarMensaje('No se pudo activar la protección: $e', Colors.red);
    } finally {
      _iniciando = false;
    }
  }

  Future<void> _togglePausa() async {
    if (!_sensoresActivos) {
      await _iniciarVigilancia();
      if (!await FlutterBackgroundService().isRunning()) return;
      FlutterBackgroundService().invoke('reanudar');
    } else {
      final opcion = await _seleccionarPausa();
      if (opcion == null) return;
      FlutterBackgroundService().invoke('pausar', {
        'duracionMinutos': opcion.minutos,
        'indefinida': opcion.indefinida,
        'etiqueta': opcion.indefinida ? null : opcion.etiqueta,
      });
    }
  }

  Future<_OpcionPausa?> _seleccionarPausa() {
    return showDialog<_OpcionPausa>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Desactivar vigilancia'),
        children: [
          for (final opcion in _opcionesPausa)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, opcion),
              child: Text(opcion.etiqueta),
            ),
        ],
      ),
    );
  }

  void _reactivarAhora() {
    _togglePausa();
  }

  void _estoyASalvo() {
    setState(() => _alarmaFalsaActiva = false);
    FlutterBackgroundService().invoke('estoyASalvo');
  }

  void _mostrarMensaje(String texto, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centinela'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ====== ESTADO DE SENSORES ======
              Card(
                color: _sensoresActivos
                    ? Colors.green.shade100
                    : Colors.orange.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _sensoresActivos ? Icons.shield : Icons.pause_circle,
                        color: _sensoresActivos ? Colors.green : Colors.orange,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _sensoresActivos
                              ? 'Vigilancia ACTIVA\nSacudidas monitoreadas'
                                : _pausaIndefinida
                                ? '⏸️ Vigilancia INACTIVA (se reactiva manualmente)'
                                : '⏸️ Vigilancia INACTIVA (se reactiva en ${(_pausaEtiqueta ?? '30 minutos').replaceFirst('Solo ', '')})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _sensoresActivos,
                        onChanged: (_) => _togglePausa(),
                        activeThumbColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
              if (!_sensoresActivos)
                TextButton(
                  onPressed: _reactivarAhora,
                  child: const Text('Reactivar ahora'),
                ),
              if (_alarmaFalsaActiva)
                ElevatedButton(
                  onPressed: _estoyASalvo,
                  child: const Text('Estoy a salvo'),
                ),
              const SizedBox(height: 15),
              const Text(
                'Activa la protección antes de bloquear el teléfono o quitar la app de recientes. '
                'Mantén la notificación activa. Después de reiniciar o forzar la detención, abre la app nuevamente.',
                style: TextStyle(fontSize: 12),
              ),
              TextButton.icon(
                icon: const Icon(Icons.battery_saver),
                label: const Text(
                  'Permitir protección sin restricción de batería',
                ),
                onPressed: () async {
                  await Permission.ignoreBatteryOptimizations.request();
                },
              ),

              if (!_abreSobreBloqueo)
                Card(
                  color: const Color(0xFFFFE0B2),
                  child: ListTile(
                    leading: const Icon(Icons.lock_open, color: Colors.orange),
                    title: const Text(
                      'La alarma no podrá abrirse sola con el teléfono bloqueado',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Toca para permitir "Mostrar sobre otras apps" y '
                      '"Notificaciones a pantalla completa".',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: _pedirAperturaSobreBloqueo,
                  ),
                ),
              if (_bitacora.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Último incidente'),
                    subtitle: Text(
                      _bitacora.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    children: [
                      for (final linea in _bitacora.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 3,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              linea,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              if (!_pinesConfigurados)
                const Card(
                  color: Color(0xFFFFCDD2),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aún no has configurado tus PINs. Hazlo antes de usar la app.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _botonMenu(
                icono: _datosDenuncianteCompletos
                    ? Icons.verified_user
                    : Icons.person_outline,
                titulo: _datosDenuncianteCompletos
                    ? '✅ Mis datos configurados'
                    : '⚠️ Configurar mis datos',
                subtitulo: 'Datos personales para el informe de denuncia',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracionDenuncianteScreen(),
                    ),
                  );
                  _actualizarInformes();
                },
              ),
              const SizedBox(height: 12),
              _botonMenu(
                icono: Icons.history,
                titulo: 'Historial de incidentes ($_incidentes)',
                subtitulo: _incidentesPendientes == 0
                    ? 'Alarmas registradas e informes'
                    : '⚠️ $_incidentesPendientes informe(s) por completar',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HistorialIncidentesScreen(),
                    ),
                  );
                  _actualizarInformes();
                },
              ),
              const SizedBox(height: 12),
              _botonMenu(
                icono: Icons.contacts,
                titulo: 'Contactos de Emergencia',
                subtitulo: 'Personas que recibirán tu SOS',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactosScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _botonMenu(
                icono: Icons.lock,
                titulo: 'Configurar PINs',
                subtitulo: 'PIN real y PIN falso',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConfigPinScreen()),
                  );
                  _verificarConfiguracion();
                },
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 30),
              const Text(
                'Centinela v1.0\nTu seguridad, en tus manos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _servicioEventos?.cancel();
    _incidentesEventos?.cancel();
    super.dispose();
  }

  Widget _botonMenu({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(icono, color: Colors.white),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
