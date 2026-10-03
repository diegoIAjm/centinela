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
      error == null ? '✅ PDF subido' : '⚠️ No se pudo subir: $error',
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
            ? '📨 Informe enviado a ${r.enviados} contacto(s)'
            : '⚠️ Enviado a ${r.enviados}; falló: ${r.fallidos.join(', ')}',
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
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
                padding: const EdgeInsets.all(16),
                children: [
                  if (_ocupado) const LinearProgressIndicator(),
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Fecha y hora'),
                    subtitle: Text(formatearFecha(i.fecha)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: const Text('Ubicación'),
                    subtitle: Text(ubicacionCorta(i)),
                    trailing: i.linkMaps == null
                        ? null
                        : const Icon(Icons.open_in_new),
                    onTap: i.linkMaps == null
                        ? null
                        : () => _abrir(i.linkMaps!),
                  ),
                  if (i.urlsAudio.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.headset_off),
                      title: Text('Audio'),
                      subtitle: Text('No se subió ningún audio'),
                    )
                  else
                    for (var n = 0; n < i.urlsAudio.length; n++)
                      ListTile(
                        leading: const Icon(Icons.headphones),
                        title: Text(
                          i.urlsAudio.length == 1
                              ? '🎧 Ver audio'
                              : '🎧 Ver audio ${n + 1}',
                        ),
                        subtitle: Text(
                          i.urlsAudio[n],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _abrir(i.urlsAudio[n]),
                      ),
                  ListTile(
                    leading: IconoEstado(i.estado),
                    title: const Text('Estado del informe'),
                    subtitle: Text(textoEstado(i.estado)),
                  ),
                  const Divider(),
                  FilledButton.icon(
                    onPressed: _editar,
                    icon: const Icon(Icons.edit),
                    label: Text(
                      i.estado == EstadoInforme.pendiente
                          ? '✏️ Completar informe'
                          : '✏️ Editar informe',
                    ),
                  ),
                  if (i.estado == EstadoInforme.sinSubir) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _reintentarSubida,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('☁️ Reintentar subida del PDF'),
                    ),
                  ],
                  if (_hayPdfLocal) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _verPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('📄 Ver PDF'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _compartirPdf,
                      icon: const Icon(Icons.share),
                      label: const Text('📤 Compartir PDF'),
                    ),
                  ],
                  if (i.urlPdf != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _enviarAContactos,
                      icon: const Icon(Icons.sms),
                      label: const Text('📨 Enviar informe a contactos'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
