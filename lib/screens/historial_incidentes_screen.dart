import 'package:flutter/material.dart';
import '../models/incidente.dart';
import '../services/informe_service.dart';
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
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aún no hay incidentes registrados.\nCada alarma cancelada '
                  'aparece aquí para que completes su informe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.separated(
                itemCount: lista.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, n) {
                  final i = lista[n];
                  return ListTile(
                    leading: IconoEstado(i.estado),
                    title: Text(formatearFecha(i.fecha)),
                    subtitle: Text(
                      '${ubicacionCorta(i)}\n${textoEstado(i.estado)}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetalleIncidenteScreen(id: i.id!),
                        ),
                      );
                      _cargar();
                    },
                  );
                },
              ),
            ),
    );
  }
}

String ubicacionCorta(Incidente i) => i.lat == null
    ? 'Ubicación no disponible'
    : '📍 ${i.lat!.toStringAsFixed(4)}, ${i.lon!.toStringAsFixed(4)}';

String textoEstado(EstadoInforme e) => switch (e) {
  EstadoInforme.completo => '✅ Informe completo',
  EstadoInforme.sinSubir => '☁️ Informe guardado, PDF sin subir',
  EstadoInforme.pendiente => '⚠️ Pendiente de completar informe',
};

class IconoEstado extends StatelessWidget {
  final EstadoInforme estado;
  const IconoEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) => switch (estado) {
    EstadoInforme.completo => const Icon(
      Icons.check_circle,
      color: Colors.green,
    ),
    EstadoInforme.sinSubir => const Icon(Icons.cloud_off, color: Colors.orange),
    EstadoInforme.pendiente => const Icon(Icons.warning, color: Colors.orange),
  };
}
