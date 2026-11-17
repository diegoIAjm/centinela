import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/voice_service.dart';
import '../tema.dart';
import '../widgets/ui.dart';

class ConfigVozScreen extends StatefulWidget {
  const ConfigVozScreen({super.key});

  @override
  State<ConfigVozScreen> createState() => _ConfigVozScreenState();
}

class _ConfigVozScreenState extends State<ConfigVozScreen> {
  final _palabra = TextEditingController();
  bool _decibelios = false;
  bool _palabrasActivas = false;
  double _umbral = 7;
  List<String> _palabras = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final config = await ConfigVoz.cargar();
    if (!mounted) return;
    setState(() {
      _decibelios = config.decibelios;
      _palabrasActivas = config.palabrasActivas;
      _umbral = config.umbral;
      _palabras = List.of(config.palabras);
      _cargando = false;
    });
  }

  void _agregar() {
    final palabra = ConfigVoz.normalizar(_palabra.text);
    if (palabra.isEmpty) return;
    if (!_palabras.map(ConfigVoz.normalizar).contains(palabra)) {
      setState(() => _palabras.add(palabra));
    }
    _palabra.clear();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      if ((_decibelios || _palabrasActivas) &&
          !await Permission.microphone.request().isGranted) {
        throw StateError(
          'Concede el permiso de micrófono para activar la voz.',
        );
      }
      if (_palabrasActivas && _palabras.isEmpty) {
        throw StateError('Agrega al menos una palabra clave.');
      }
      await ConfigVoz(
        decibelios: _decibelios,
        palabrasActivas: _palabrasActivas,
        umbral: _umbral,
        palabras: _palabras,
      ).guardar();
      FlutterBackgroundService().invoke('configVozActualizada');
      if (!mounted) return;
      mostrarMensaje(
        context,
        'Configuración de voz guardada',
        tipo: TipoAviso.exito,
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        mostrarMensaje(
          context,
          e is StateError ? e.message : '$e',
          tipo: TipoAviso.peligro,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _interruptor({
    required String titulo,
    required String descripcion,
    required bool valor,
    required ValueChanged<bool> alCambiar,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(descripcion),
    value: valor,
    onChanged: alCambiar,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activación por voz')),
    body: _cargando
        ? const Center(child: CircularProgressIndicator())
        : AbsorbPointer(
            absorbing: _guardando,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Aviso(
                  tipo: TipoAviso.info,
                  titulo: 'Cómo funciona',
                  texto:
                      'La alarma se activa si gritas o si dices una palabra '
                      'de la lista. Necesita internet y la protección activa. '
                      'Android reinicia la escucha por silencio, así que '
                      'puede haber breves pausas.',
                ),
                const EncabezadoSeccion('Volumen de voz'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _interruptor(
                          titulo: 'Activar al detectar un grito',
                          descripcion:
                              'Se activa si el sonido supera el nivel '
                              'durante medio segundo.',
                          valor: _decibelios,
                          alCambiar: (v) => setState(() => _decibelios = v),
                        ),
                        if (_decibelios) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(child: Text('Nivel para activar')),
                              Text(
                                _umbral.toStringAsFixed(1),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          Slider(
                            value: _umbral,
                            min: 1,
                            max: 20,
                            divisions: 190,
                            label: _umbral.toStringAsFixed(1),
                            onChanged: (v) => setState(() => _umbral = v),
                          ),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Más sensible',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Paleta.textoSecundario,
                                ),
                              ),
                              Text(
                                'Menos sensible',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Paleta.textoSecundario,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const EncabezadoSeccion('Palabras clave'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _interruptor(
                          titulo: 'Activar al oír una palabra clave',
                          descripcion:
                              'Funciona con palabras sueltas o frases '
                              'completas.',
                          valor: _palabrasActivas,
                          alCambiar: (v) =>
                              setState(() => _palabrasActivas = v),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _palabra,
                          decoration: InputDecoration(
                            labelText: 'Agregar palabra o frase',
                            suffixIcon: IconButton(
                              tooltip: 'Agregar',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _agregar,
                            ),
                          ),
                          onSubmitted: (_) => _agregar(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_palabras.length} palabra(s) en la lista',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Paleta.textoSecundario,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final palabra in _palabras)
                              InputChip(
                                label: Text(palabra),
                                backgroundColor: Paleta.infoFondo,
                                side: BorderSide.none,
                                deleteIconColor: Paleta.marino,
                                deleteButtonTooltipMessage: 'Eliminar $palabra',
                                onDeleted: () =>
                                    setState(() => _palabras.remove(palabra)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _guardando ? 'Guardando…' : 'Guardar configuración',
                  ),
                ),
              ],
            ),
          ),
  );

  @override
  void dispose() {
    _palabra.dispose();
    super.dispose();
  }
}
