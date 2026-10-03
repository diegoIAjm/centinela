# Protección en segundo plano

Configura ambos PINs y al menos un contacto, concede micrófono, ubicación,
SMS y notificaciones. Activa el GPS y usa una SIM con servicio para SMS.
Activa la vigilancia con la app visible y espera la confirmación de protección.
El botón de batería permite solicitar la excepción de ahorro de energía.
Algunos fabricantes también requieren permitir inicio automático en sus ajustes.

## Comprobación en un teléfono real

Estas pruebas envían SMS reales y suben grabaciones al preset configurado.
Coordina previamente con el contacto de prueba.

1. Bloquea la pantalla durante varios minutos. Agita tres veces con impulsos
   separados entre 150 y 800 ms. Comprueba sirena y SMS de ubicación.
2. Comprueba el enlace del primer audio (10 segundos, más tiempo de subida).
   Mientras la alarma siga activa se graban fragmentos posteriores de 60 segundos.
3. Ingresa el PIN real: debe detener sonido y grabación, descartar envíos aún
   pendientes y volver a detectar otra alarma. Los SMS ya enviados y las subidas
   ya iniciadas no pueden retirarse.
4. Repite con el PIN de amenaza: debe silenciarse y mostrar la cancelación
   simulada, manteniendo grabaciones y envíos. Reabre la pantalla de alarma
   con SIMULAR ALARMA para ingresar después el PIN real.
5. Quita la app de recientes y repite agitado y ruido por separado con pantalla
   bloqueada. Abre la notificación: debe recuperar la alarma activa.
6. Desactiva internet: los archivos cuya subida falle deben permanecer en
   el almacenamiento privado centinela_audios. No existe reintento automático
   de archivos anteriores; los siguientes fragmentos vuelven a intentar subir.
7. Pausa la vigilancia y comprueba que se reanuda a los 30 minutos.

El umbral de sonido es -20 dBFS (nivel digital relativo al micrófono), no dB SPL
calibrados ni reconocimiento de palabras. Un ruido fuerte también lo activa.
Los sensores se disparan independientemente: ruido O agitado.

## Límites

La notificación del servicio y el indicador de micrófono de Android permanecen
visibles, incluso con el PIN de amenaza. La sirena puede oírse en la grabación.
No hay garantía de ejecución tras Forzar detención, reinicio, revocación de
permisos o cierre impuesto por el fabricante: abre la app y reactiva protección.
Quitar de recientes no equivale a Forzar detención.

La aceptación de un SMS por Android no confirma su recepción por el contacto.
Cloudinary requiere internet y un preset unsigned válido para audio/video.
Estas condiciones requieren validación real antes de depender de la app.

Referencia Android: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
