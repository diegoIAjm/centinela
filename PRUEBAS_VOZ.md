# Protección por voz programada (Android)

Primera versión: una franja semanal, frases completas configurables y reconocimiento
local con Vosk. No identifica al hablante ni determina que exista violencia.
La configuración se abre desde Inicio → Protección por voz.

## Preparación y uso

1. Conserva `android/app/google-services.json` del equipo (no se agrega en este cambio).
2. Ejecuta `flutter pub get` y vuelve a compilar; hot reload no instala el código nativo.
3. Configura los dos PINs. Para alertas reales, añade al menos un contacto de prueba.
4. En Protección por voz, descarga el modelo español (aprox. 39 MB comprimidos).
   Se guarda en el almacenamiento privado; no vuelve a descargarse en cada inicio.
5. Habilita el horario; por defecto todos los días, 07:00–12:00. También admite
   horarios nocturnos: lunes 22:00–02:00 termina el martes a las 02:00.
6. Escribe de 1 a 10 frases, una por línea, de al menos dos palabras. Frase inicial:
   `centinela necesito ayuda`. Se ignoran mayúsculas, tildes y puntuación.
7. Guarda. Mantén el modo de prueba para comprobar detecciones sin sirena,
   grabación ni envíos **por voz**. El botón y el agitado siguen siendo reales.
8. Pulsa Activar vigilancia / reintentar voz con la app visible. Comprueba el
   estado: Escuchando, Esperando horario, Suspendida o Error.
9. Para activar el flujo real, desmarca el modo de prueba, guarda y confirma.
   Una coincidencia confirmada ejecuta la alarma existente: sirena, pantalla de
   alarma, grabación, ubicación y SMS; no es una activación silenciosa.

El detector evalúa transcripciones finales; puede haber demora después de terminar
la frase. No se exige pulsar un micrófono cada vez. No se conservan conversaciones
mientras vigila: solo audio transitorio en memoria y la última frase configurada
que coincidió, en memoria del servicio. Tras disparar, el audio de evidencia sigue
el flujo existente (archivos locales, Cloudinary, enlaces por SMS).

## Verificación en emulador (sin SMS reales)

- Autoriza el micrófono del PC para Android Emulator y habilita la entrada de audio
  en los controles del emulador si está desactivada.
- Configura una franja que incluya la hora local actual y deja modo de prueba.
- Di la frase completa y espera el final de la intervención. Debe aparecer la
  última coincidencia, sin crear incidentes, reproducir sirena ni enviar archivos.
- Di palabras parecidas incompletas: no deben coincidir por subcadenas de palabras.
- Prueba una frase reproducida por altavoz: puede activar el detector; no hay
  identificación de hablante. No habilites alertas reales sin evaluar este riesgo.
- Cambia el fin a un minuto próximo: fuera de la franja deja de escuchar.
- Guarda deshabilitada: libera el micrófono. Configurar el horario no significa
  que el servicio ya esté funcionando: verifica su estado.
- Prueba el dictado de formularios: se reserva el micrófono y luego se reanuda
  la escucha. Cada sesión de dictado se cierra antes de 3 minutos.

## Verificación en teléfono real

Coordina los envíos con el contacto de prueba: el modo real puede enviar SMS con
costo y subir grabaciones a la cuenta Cloudinary ya configurada.

- En modo prueba, mide acentos, ruido, distancia, frases normales, televisión y
  falsos negativos con pantalla encendida y bloqueada. El emulador no acredita
  fiabilidad ni consumo de un teléfono real.
- En modo real, comprueba sirena, primera ubicación, grabación y enlace de audio.
- PIN real: cancela como antes y reanuda escucha si continúa dentro del horario.
- PIN de amenaza: mantiene la grabación sin volver a tomar el micrófono para voz.
- Una alarma iniciada antes del fin del horario debe continuar después del fin.
- Pausar la vigilancia pausa también la voz. Reanudar respeta el horario.
- Desactivar internet después de instalar el modelo no debe impedir reconocer;
  las subidas a Cloudinary siguen necesitando red y los SMS servicio telefónico.
- Si otra app toma/silencia el micrófono, comprobar estado Error; cerrar esa app y
  reintentar. No mostrar «Escuchando» cuando el motor informa un fallo.
- Probar reintento tras descarga fallida, permiso de micrófono revocado, servicio
  detenido, cambios de hora/zona horaria, cierre forzado y reinicio del teléfono.

## Límites explícitos

- Requiere un servicio de protección ya iniciado desde la app visible. No se
  implementa arranque del micrófono desde una alarma exacta ni desde el reinicio.
- Revisión de hora local cada 5 segundos, más latencia del sistema y carga del
  modelo. No es una alarma exacta. Al cambiar de zona horaria usa la hora local nueva.
- Android muestra la notificación y el indicador de micrófono. No se ocultan.
- Para revisar horarios con pantalla apagada, se mantiene un partial wake lock
  mientras la voz está habilitada y la vigilancia armada, incluso fuera de franja.
  Aumenta el consumo; medir autonomía. Se libera al deshabilitar, pausar o detener.
- No hay garantía tras Forzar detención, reinicio o cierre impuesto por Android/OEM.
  Abre la app y vuelve a activar; comprueba siempre el estado.
- Solo frases completas en transcripciones finales, no análisis semántico,
  negaciones, tono de voz, identificación de personas ni prueba de agresión.
- Se suprimen detecciones repetidas durante 30 segundos. No se duplican sesiones
  de alarma. El PIN de amenaza conserva el comportamiento previo.
- No se incorpora audio anterior al disparador; la evidencia empieza después.

## Arquitectura y ampliaciones

- `ConfiguracionVoz`: validación, calendario y coincidencia de frases sin Flutter.
- `ConfiguracionVozStore`: almacenamiento versionado y recarga entre isolates.
- `ProteccionVozService`: agenda, estados, exclusión por alarma/dictado, modo prueba.
- `MotorVoz`: interfaz sustituible; `MotorVozLocal` usa un canal independiente.
- `VozLocal.java`: Vosk, instalación validada del modelo, captura y liberación.
  Un único capturador de voz, sin competir con el grabador de evidencia.

Se pueden añadir múltiples franjas, recordatorios para rearmar, mejores estrategias
energéticas y modelos de detección específicos sin reemplazar la alarma existente.

## Dependencias y fuentes

- Vosk Android 0.3.75 y JNA 5.18.1, como la demo oficial:
  https://github.com/alphacep/vosk-android-demo/blob/master/app/build.gradle
- Modelo `vosk-model-small-es-0.42`, Apache 2.0, catálogo y descarga oficial:
  https://alphacephei.com/vosk/models
  https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip
- Permisos/servicio de micrófono:
  https://developer.android.com/develop/background-work/services/fgs/service-types#microphone

Pruebas automatizadas: `flutter test`. Analizador: `flutter analyze`.
La compilación de APK y la validación acústica deben registrarse por separado:
las pruebas con motor falso no acreditan detección en hardware.

## Validación de este cambio

- 35 pruebas Flutter aprobadas, incluyendo agenda, modo prueba/real con motor
  sustituido, exclusión del micrófono y formulario de 360 px.
- Analizador Dart sobre `lib` y `test`: sin incidencias.
- Ambos archivos Java del plugin compilados con JDK 17, stubs Android API 36,
  Flutter embedding, Vosk y JNA.
- No se generó ni ejecutó un APK completo en esta revisión. Pendientes:
  descarga del modelo desde la app, reconocimiento acústico y validación Android
  de extremo a extremo en emulador y teléfono, batería y SMS.
