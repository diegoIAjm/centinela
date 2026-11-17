import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/incidente.dart';
import '../services/alerta_service.dart';
import '../services/informe_service.dart';
import 'datos_incidente_screen.dart';
import 'historial_incidentes_screen.dart';
import '../widgets/ui.dart';

class DetalleIncidenteScreen extends StatefulWidget {
  final int id;
  const DetalleIncidenteScreen({super.key, required this.id});

  @override
  State<DetalleIncidenteScreen> createState() => _DetalleIncidenteScreenState();
}

class _DetalleIncidenteScreenState extends State<DetalleIncidenteScreen> {
  final _informes = InformeService();
  Incidente? _incidente;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final i = await _informes.obtenerIncidente(widget.id);
    if (mounted) setState(() => _incidente = i);
  }

  bool get _hayPdfLocal {
    final ruta = _incidente?.rutaPdf;
    return ruta != null && File(ruta).existsSync();
  }

  Future<void> _abrir(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      _avisar('No se pudo abrir el enlace', Colors.red);
    }
  }

  Future<void> _editar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DatosIncidenteScreen(idIncidente: widget.id),
      ),
    );
    _cargar();
  }

  Future<void> _verPdf() async {
    final bytes = await File(_incidente!.rutaPdf!).readAsBytes();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'informe_incidente_${widget.id}.pdf',
    );
  }

  Future<void> _compartirPdf() async {
    await Share.shareXFiles([
      XFile(_incidente!.rutaPdf!, mimeType: 'application/pdf'),
    ], subject: 'Informe de denuncia Centinela');
  }

  Future<void> _reintentarSubida() async {
    setState(() => _ocupado = true);
    final error = await _informes.reintentarSubidaPdf(widget.id);
    if (!mounted) return;
    setState(() => _ocupado = false);
    _avisar(
      error == null ? 'PDF subido' : 'No se pudo subir: $error',
      error == null ? Colors.green : Colors.orange,
    );
    _cargar();
  }

  Future<void> _enviarAContactos() async {
    final i = _incidente!;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enviar informe a tus contactos'),
        content: const Text(
          'Se enviará por SMS el enlace al PDF del informe a todos tus '
          'contactos de emergencia. El informe incluye tus datos personales '
          'y cualquiera con el enlace podrá abrirlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await AlertaService().enviarSMSInforme(
        urlPdf: i.urlPdf!,
        fechaIncidente: formatearFecha(i.fecha),
      );
      _avisar(
        r.fallidos.isEmpty
            ? 'Formulario enviado a ${r.enviados} contacto(s)'
            : 'Enviado a ${r.enviados}; falló: ${r.fallidos.join(', ')}',
        r.fallidos.isEmpty ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _avisar('No se pudo enviar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _avisar(String texto, Color color) {
    if (!mounted) return;
    mostrarMensaje(
      context,
      texto,
      tipo: color == Colors.green
          ? TipoAviso.exito
          : color == Colors.orange
          ? TipoAviso.aviso
          : TipoAviso.peligro,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = _incidente;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del incidente')),
      body: i == null
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _ocupado,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (_ocupado) const LinearProgressIndicator(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconoEstado(i.estado),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  formatearFecha(i.fecha),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: EtiquetaEstado(i.estado),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _editar,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              i.estado == EstadoInforme.pendiente
                                  ? 'Completar formulario de denuncia'
                                  : 'Editar formulario de denuncia',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const EncabezadoSeccion('Datos de la alarma'),
                  GrupoOpciones([
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Fecha y hora'),
                      subtitle: Text(formatearFecha(i.fecha)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: const Text('Ubicación'),
                      subtitle: Text(ubicacionCorta(i)),
                      trailing: i.linkMaps == null
                          ? null
                          : const Icon(Icons.open_in_new, size: 20),
                      onTap: i.linkMaps == null
                          ? null
                          : () => _abrir(i.linkMaps!),
                    ),
                  ]),
                  const EncabezadoSeccion('Grabaciones de audio'),
                  if (i.urlsAudio.isEmpty)
                    const Aviso(
                      tipo: TipoAviso.info,
                      titulo: 'No se subió ninguna grabación',
                    )
                  else
                    GrupoOpciones([
                      for (var n = 0; n < i.urlsAudio.length; n++)
                        ListTile(
                          leading: const Icon(Icons.graphic_eq),
                          title: Text('Grabación N.º ${n + 1}'),
                          subtitle: Text(
                            i.urlsAudio[n],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 20),
                          onTap: () => _abrir(i.urlsAudio[n]),
                        ),
                    ]),
                  if (i.estado != EstadoInforme.pendiente) ...[
                    const EncabezadoSeccion('Formulario en PDF'),
                    if (i.estado == EstadoInforme.sinSubir)
                      Aviso(
                        tipo: TipoAviso.aviso,
                        titulo: 'El PDF no se subió a internet',
                        texto:
                            'Está guardado en el teléfono. Súbelo para poder '
                            'enviarlo a tus contactos.',
                        accion: 'Reintentar subida',
                        onTap: _reintentarSubida,
                      ),
                    GrupoOpciones([
                      if (_hayPdfLocal) ...[
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: const Text('Ver PDF'),
                          onTap: _verPdf,
                        ),
                        ListTile(
                          leading: const Icon(Icons.share_outlined),
                          title: const Text('Compartir PDF'),
                          onTap: _compartirPdf,
                        ),
                      ],
                      if (i.urlPdf != null)
                        ListTile(
                          leading: const Icon(Icons.sms_outlined),
                          title: const Text('Enviar a mis contactos'),
                          subtitle: const Text('Envía el enlace por SMS'),
                          onTap: _enviarAContactos,
                        ),
                    ]),
                  ],
                ],
              ),
            ),
    );
  }
}
