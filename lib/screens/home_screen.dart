import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'contactos_screen.dart';
import 'config_pin_screen.dart';
import 'config_voz_screen.dart';
import '../navegacion.dart';
import '../services/pin_service.dart';
import '../services/background_service.dart';
import '../services/notificacion_alarma.dart';
import 'package:centinela_nativo/centinela_nativo.dart';
import '../models/incidente.dart';
import '../services/informe_service.dart';
import 'configuracion_denunciante_screen.dart';
import 'historial_incidentes_screen.dart';
import '../tema.dart';
import '../widgets/ui.dart';

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
  String? _estadoVoz;
  String? _errorVoz;

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
        _estadoVoz = datos['vozEstado'] as String?;
        _errorVoz = datos['vozError'] as String?;
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
    setState(() => _iniciando = true);
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
      if (mounted) setState(() => _iniciando = false);
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
    mostrarMensaje(
      context,
      texto,
      tipo: color == Colors.red ? TipoAviso.peligro : TipoAviso.info,
    );
  }

  Future<void> _abrir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

  String get _textoVoz {
    if (_errorVoz != null) return 'Voz no disponible, reintentando';
    return switch (_estadoVoz) {
      'escuchando' => 'Activación por voz: escuchando',
      'iniciando' => 'Activación por voz: conectando',
      'esperando' => 'Activación por voz: en espera',
      'pausada' => 'Activación por voz: pausada',
      'reservada' => 'Activación por voz: micrófono en uso',
      'dictado' => 'Activación por voz: en pausa por dictado',
      'desactivada' => 'Activación por voz: desactivada',
      _ => 'Activación por voz: detenida',
    };
  }

  Widget _tarjetaEstado() {
    final activo = _sensoresActivos;
    final color = activo ? Paleta.exito : Paleta.aviso;
    final detalle = activo
        ? 'Se detectan sacudidas del teléfono y, si lo configuraste, tu voz.'
        : _pausaIndefinida
        ? 'Pausada hasta que la reactives.'
        : 'Se reactivará sola en '
              '${(_pausaEtiqueta ?? '30 minutos').replaceFirst('Solo ', '')}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: activo ? Paleta.exitoFondo : Paleta.avisoFondo,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    activo ? Icons.shield : Icons.pause_circle_outline,
                    color: color,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activo ? 'Protección activa' : 'Protección en pausa',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(detalle),
                    ],
                  ),
                ),
              ],
            ),
            if (_estadoVoz != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _errorVoz != null ? Icons.mic_off : Icons.mic_none,
                    size: 20,
                    color: _errorVoz != null
                        ? Paleta.aviso
                        : Paleta.textoSecundario,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _textoVoz,
                      style: const TextStyle(color: Paleta.textoSecundario),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (activo)
              OutlinedButton.icon(
                onPressed: _iniciando ? null : _togglePausa,
                icon: const Icon(Icons.pause),
                label: const Text('Pausar protección'),
              )
            else
              FilledButton.icon(
                onPressed: _iniciando ? null : _reactivarAhora,
                icon: _iniciando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _iniciando ? 'Activando…' : 'Activar protección ahora',
                ),
              ),
            if (_alarmaFalsaActiva) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _estoyASalvo,
                child: const Text('Estoy a salvo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _pendientes() => [
    if (!_pinesConfigurados)
      Aviso(
        tipo: TipoAviso.peligro,
        titulo: 'Configura tus PIN',
        texto: 'Sin ellos no se puede activar la protección.',
        onTap: () async {
          await _abrir(const ConfigPinScreen());
          _verificarConfiguracion();
        },
      ),
    if (!_abreSobreBloqueo)
      Aviso(
        tipo: TipoAviso.aviso,
        titulo: 'La alarma no se abrirá con el teléfono bloqueado',
        texto:
            'Permite "Mostrar sobre otras apps" y "Notificaciones a '
            'pantalla completa".',
        onTap: _pedirAperturaSobreBloqueo,
      ),
    if (!_datosDenuncianteCompletos)
      Aviso(
        tipo: TipoAviso.aviso,
        titulo: 'Completa tus datos personales',
        texto: 'Se usan para llenar el formulario de denuncia.',
        onTap: () async {
          await _abrir(const ConfiguracionDenuncianteScreen());
          _actualizarInformes();
        },
      ),
    if (_incidentesPendientes > 0)
      Aviso(
        tipo: TipoAviso.aviso,
        titulo: _incidentesPendientes == 1
            ? '1 formulario de denuncia por completar'
            : '$_incidentesPendientes formularios de denuncia por completar',
        onTap: () async {
          await _abrir(const HistorialIncidentesScreen());
          _actualizarInformes();
        },
      ),
  ];

  Widget _ultimoIncidente() => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('Registro de la última alarma'),
      subtitle: Text(
        _bitacora.last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      children: [
        for (final linea in _bitacora.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                linea,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pendientes = _pendientes();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Image.asset('assets/images/logo_emblema.png', width: 36),
            const SizedBox(width: 10),
            const Text('Centinela'),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _tarjetaEstado(),
            if (pendientes.isNotEmpty) ...[
              const EncabezadoSeccion('Pendientes'),
              ...pendientes,
            ],
            const EncabezadoSeccion('Denuncias'),
            GrupoOpciones([
              OpcionMenu(
                icono: Icons.history,
                titulo: 'Historial de incidentes',
                subtitulo: 'Alarmas registradas y formularios',
                insignia: _incidentes == 0 ? null : Insignia('$_incidentes'),
                onTap: () async {
                  await _abrir(const HistorialIncidentesScreen());
                  _actualizarInformes();
                },
              ),
              OpcionMenu(
                icono: Icons.badge_outlined,
                titulo: 'Mis datos personales',
                subtitulo: 'Datos del denunciante',
                insignia: _datosDenuncianteCompletos
                    ? null
                    : const Insignia('Incompleto', tipo: TipoAviso.aviso),
                onTap: () async {
                  await _abrir(const ConfiguracionDenuncianteScreen());
                  _actualizarInformes();
                },
              ),
            ]),
            const EncabezadoSeccion('Configuración'),
            GrupoOpciones([
              OpcionMenu(
                icono: Icons.contacts_outlined,
                titulo: 'Contactos de emergencia',
                subtitulo: 'Reciben tu ubicación y audios',
                onTap: () => _abrir(const ContactosScreen()),
              ),
              OpcionMenu(
                icono: Icons.pin_outlined,
                titulo: 'PIN de seguridad',
                subtitulo: 'PIN real y PIN de coacción',
                insignia: _pinesConfigurados
                    ? null
                    : const Insignia('Falta', tipo: TipoAviso.peligro),
                onTap: () async {
                  await _abrir(const ConfigPinScreen());
                  _verificarConfiguracion();
                },
              ),
              OpcionMenu(
                icono: Icons.record_voice_over_outlined,
                titulo: 'Activación por voz',
                subtitulo: 'Volumen y palabras clave',
                onTap: () => _abrir(const ConfigVozScreen()),
              ),
              OpcionMenu(
                icono: Icons.battery_charging_full_outlined,
                titulo: 'Funcionar sin restricción de batería',
                subtitulo: 'Evita que Android detenga la protección',
                onTap: () => Permission.ignoreBatteryOptimizations.request(),
              ),
            ]),
            if (_bitacora.isNotEmpty) ...[
              const EncabezadoSeccion('Actividad'),
              _ultimoIncidente(),
            ],
            const SizedBox(height: 16),
            const Text(
              'Mantén visible la notificación de Centinela. Si reinicias el '
              'teléfono o fuerzas el cierre, abre la app para reactivar la '
              'protección.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Paleta.textoSecundario),
            ),
            const SizedBox(height: 8),
            const Text(
              'Centinela v1.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Paleta.textoSecundario),
            ),
          ],
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
}
