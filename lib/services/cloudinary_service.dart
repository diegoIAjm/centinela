import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _cloudName = 'rm4wqeol';
const _uploadPreset = 'centinela_audios_unsigned';
const _audioFolder = 'centinela_audios';
const _informesFolder = 'centinela_informes';

/// Resultado de una subida: [url] si Cloudinary la aceptó, o [error] con el
/// motivo exacto (status HTTP + mensaje de Cloudinary).
class SubidaArchivo {
  final String? url;
  final String? error;
  const SubidaArchivo.ok(String this.url) : error = null;
  const SubidaArchivo.fallo(String this.error) : url = null;
}

/// Audio: Cloudinary lo guarda como recurso "video".
Future<SubidaArchivo> subirAudioACloudinary(String rutaArchivoLocal) =>
    _subir(rutaArchivoLocal, recurso: 'video', carpeta: _audioFolder);

/// PDF del informe: recurso "raw" para que se descargue tal cual.
Future<SubidaArchivo> subirPDFACloudinary(String rutaPDF) =>
    _subir(rutaPDF, recurso: 'raw', carpeta: _informesFolder);

/// http directo (no un SDK) para poder ver status y body de cada rechazo.
Future<SubidaArchivo> _subir(
  String rutaArchivoLocal, {
  required String recurso,
  required String carpeta,
}) async {
  debugPrint('════════════════════════════════════');
  debugPrint('📁 Iniciando subida a Cloudinary ($recurso)');
  debugPrint('📁 Ruta local: $rutaArchivoLocal');
  final archivo = File(rutaArchivoLocal);
  final existe = await archivo.exists();
  debugPrint('📁 ¿Existe el archivo? $existe');
  if (!existe) {
    debugPrint('════════════════════════════════════');
    return const SubidaArchivo.fallo('el archivo no existe');
  }
  final tamano = await archivo.length();
  debugPrint('📁 Tamaño: $tamano bytes');
  debugPrint('════════════════════════════════════');
  if (tamano == 0) {
    debugPrint('⚠️ ARCHIVO VACÍO - no se escribió nada');
    return const SubidaArchivo.fallo('archivo vacío');
  }

  try {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/$recurso/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = carpeta
      ..files.add(await http.MultipartFile.fromPath('file', rutaArchivoLocal));
    final response = await request.send().timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    debugPrint('📤 Status HTTP: ${response.statusCode}');
    debugPrint('📤 Body: $body');

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    if (response.statusCode == 200) {
      final url = json?['secure_url'] as String?;
      if (url != null && url.isNotEmpty) {
        debugPrint('✅ Subido: $url');
        return SubidaArchivo.ok(url);
      }
      return SubidaArchivo.fallo('HTTP 200 sin secure_url: $body');
    }
    final motivo = (json?['error'] as Map?)?['message'] ?? body;
    debugPrint('❌ Cloudinary rechazó la subida: $motivo');
    return SubidaArchivo.fallo('HTTP ${response.statusCode}: $motivo');
  } catch (e) {
    debugPrint('❌ Error de red subiendo a Cloudinary: $e');
    return SubidaArchivo.fallo('sin conexión o error de red: $e');
  }
}
