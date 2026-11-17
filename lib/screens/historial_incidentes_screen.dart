import 'package:flutter/material.dart';
import '../models/incidente.dart';
import '../services/informe_service.dart';
import '../tema.dart';
import '../widgets/ui.dart';
import 'detalle_incidente_screen.dart';

class HistorialIncidentesScreen extends StatefulWidget {
  const HistorialIncidentesScreen({super.key});

  @override
  State<HistorialIncidentesScreen> createState() =>
      _HistorialIncidentesScreenState();
}

class _HistorialIncidentesScreenState extends State<HistorialIncidentesScreen> {
  List<Incidente>? _incidentes;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await InformeService().obtenerHistorial();
    if (mounted) setState(() => _incidentes = lista);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _incidentes;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de incidentes')),
      body: lista == null
          ? const Center(child: CircularProgressIndicator())
          : lista.isEmpty
          ? const EstadoVacio(
              icono: Icons.history,
              titulo: 'Aún no hay incidentes',
              texto:
                  'Cada alarma que se active quedará registrada aquí para que '
                  'completes su formulario de denuncia.',
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: lista.length,
                itemBuilder: (_, n) {
                  final i = lista[n];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      leading: IconoEstado(i.estado),
                      title: Text(
                        formatearFecha(i.fecha),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            '${ubicacionCorta(i)} · '
                            '${i.urlsAudio.length} audio(s)',
                          ),
                          const SizedBox(height: 6),
                          EtiquetaEstado(i.estado),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Paleta.textoSecundario,
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetalleIncidenteScreen(id: i.id!),
                          ),
                        );
                        _cargar();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

String ubicacionCorta(Incidente i) => i.lat == null
    ? 'Sin ubicación'
    : '${i.lat!.toStringAsFixed(4)}, ${i.lon!.toStringAsFixed(4)}';

String textoEstado(EstadoInforme e) => switch (e) {
  EstadoInforme.completo => 'Formulario completo',
  EstadoInforme.sinSubir => 'Formulario guardado, PDF sin subir',
  EstadoInforme.pendiente => 'Formulario pendiente',
};

TipoAviso _tipoEstado(EstadoInforme e) => switch (e) {
  EstadoInforme.completo => TipoAviso.exito,
  EstadoInforme.sinSubir => TipoAviso.aviso,
  EstadoInforme.pendiente => TipoAviso.aviso,
};

class EtiquetaEstado extends StatelessWidget {
  final EstadoInforme estado;
  const EtiquetaEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) =>
      Insignia(textoEstado(estado), tipo: _tipoEstado(estado));
}

class IconoEstado extends StatelessWidget {
  final EstadoInforme estado;
  const IconoEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) => switch (estado) {
    EstadoInforme.completo => const Icon(
      Icons.check_circle,
      color: Paleta.exito,
    ),
    EstadoInforme.sinSubir => const Icon(
      Icons.cloud_off_outlined,
      color: Paleta.aviso,
    ),
    EstadoInforme.pendiente => const Icon(Icons.edit_note, color: Paleta.aviso),
  };
}
