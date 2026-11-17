import 'package:flutter/material.dart';

import '../tema.dart';

/// Componentes visuales compartidos para que todas las pantallas se lean igual.

enum TipoAviso { info, exito, aviso, peligro }

extension on TipoAviso {
  Color get color => switch (this) {
    TipoAviso.info => Paleta.info,
    TipoAviso.exito => Paleta.exito,
    TipoAviso.aviso => Paleta.aviso,
    TipoAviso.peligro => Paleta.peligro,
  };
  Color get fondo => switch (this) {
    TipoAviso.info => Paleta.infoFondo,
    TipoAviso.exito => Paleta.exitoFondo,
    TipoAviso.aviso => Paleta.avisoFondo,
    TipoAviso.peligro => Paleta.peligroFondo,
  };
  IconData get icono => switch (this) {
    TipoAviso.info => Icons.info_outline,
    TipoAviso.exito => Icons.check_circle_outline,
    TipoAviso.aviso => Icons.warning_amber_rounded,
    TipoAviso.peligro => Icons.error_outline,
  };
}

/// Mensaje breve en la parte inferior, con color según el resultado.
void mostrarMensaje(
  BuildContext context,
  String texto, {
  TipoAviso tipo = TipoAviso.info,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(texto),
      backgroundColor: switch (tipo) {
        TipoAviso.exito => Paleta.exito,
        TipoAviso.aviso => Paleta.aviso,
        TipoAviso.peligro => Paleta.peligro,
        TipoAviso.info => Paleta.marino,
      },
    ),
  );
}

/// Título de un grupo de contenido.
class EncabezadoSeccion extends StatelessWidget {
  final String titulo;
  final Widget? accion;
  const EncabezadoSeccion(this.titulo, {super.key, this.accion});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Paleta.textoSecundario,
            ),
          ),
        ),
        ?accion,
      ],
    ),
  );
}

/// Recuadro de aviso con icono, borde lateral y acción opcional.
class Aviso extends StatelessWidget {
  final TipoAviso tipo;
  final String titulo;
  final String? texto;
  final String? accion;
  final VoidCallback? onTap;

  const Aviso({
    super.key,
    required this.tipo,
    required this.titulo,
    this.texto,
    this.accion,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Material(
      color: tipo.fondo,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: tipo.color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tipo.icono, color: tipo.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: tipo == TipoAviso.info
                            ? Paleta.texto
                            : tipo.color,
                      ),
                    ),
                    if (texto != null) ...[
                      const SizedBox(height: 2),
                      Text(texto!, style: const TextStyle(fontSize: 14)),
                    ],
                    if (accion != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        accion!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tipo.color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null && accion == null)
                Icon(Icons.chevron_right, color: tipo.color),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Opción de menú: icono, título, descripción y flecha.
class OpcionMenu extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final VoidCallback onTap;
  final Widget? insignia;

  const OpcionMenu({
    super.key,
    required this.icono,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
    this.insignia,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Paleta.infoFondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icono, color: Paleta.marino),
    ),
    title: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
    subtitle: subtitulo == null ? null : Text(subtitulo!),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?insignia,
        const Icon(Icons.chevron_right, color: Paleta.textoSecundario),
      ],
    ),
    onTap: onTap,
  );
}

/// Varias opciones dentro de una misma tarjeta, separadas por líneas.
class GrupoOpciones extends StatelessWidget {
  final List<Widget> hijos;
  const GrupoOpciones(this.hijos, {super.key});

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var n = 0; n < hijos.length; n++) ...[
          if (n > 0) const Divider(indent: 72),
          hijos[n],
        ],
      ],
    ),
  );
}

/// Pastilla pequeña de estado o conteo.
class Insignia extends StatelessWidget {
  final String texto;
  final TipoAviso tipo;
  const Insignia(this.texto, {super.key, this.tipo = TipoAviso.info});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: tipo.fondo,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: tipo.color,
      ),
    ),
  );
}

/// Contenido para listas vacías.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 56, color: Paleta.borde),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Paleta.textoSecundario),
          ),
        ],
      ),
    ),
  );
}
