# Activación por voz de Centinela

## Uso

En Inicio → Activación por Voz se pueden habilitar independientemente el
nivel de sonido y las palabras clave. Ambos están desactivados inicialmente.
El umbral inicial es 7.0, configurable entre 1.0 y 10.0; un umbral menor
dispara con sonidos más suaves. El nivel es RMS relativo del motor Android,
no dB SPL calibrados; su escala depende del dispositivo y del reconocedor.
Las palabras iniciales son ayuda, socorro, auxilio, peligro, emergencia,
policia y una lista de insultos y amenazas (`ConfigVoz.palabrasIniciales`),
editable desde la pantalla. La comparación admite mayúsculas, puntuación y
acentos, y respeta palabras completas. También se pueden agregar frases.

Android censura las palabras ofensivas por defecto
(`EXTRA_MASK_OFFENSIVE_WORDS`) y speech_to_text no permite cambiarlo, así que
`p***` se compara con la lista: misma longitud y mismas letras visibles. No se
filtra por confianza (Android suele entregar -1) y se aceptan resultados
parciales para activar sin esperar a una pausa. En modo debug, el log
`🗣️ Oído:` muestra lo que entendió el motor.

Se necesita guardar la configuración. Se solicita micrófono con
permission_handler en la pantalla, antes de iniciar el reconocedor. El
servicio comprueba el permiso, pero no intenta mostrar diálogos desde un
isolate sin Activity. La vigilancia general debe estar activa para escuchar.

## Archivos y cambios

- `lib/services/voice_service.dart`: ConfigVoz persistida como un único JSON
  en SharedPreferences y singleton VoiceService por isolate; cancelación,
  reserva, pausa, recarga entre isolates y reintentos de 3 segundos.
- `lib/screens/config_voz_screen.dart`: controles y guardado explícito.
- `lib/services/background_service.dart`: crea VoiceService en el isolate
  del Foreground Service y lo inicia después de registrar los callbacks de
  AlarmaService. Recibe configVozActualizada y comandos de reserva para dictado.
- `lib/services/alarma_service.dart`: suscribe la amenaza a activarAlarma()
  existente; reserva el micrófono al preparar la captura; lo libera tras
  terminar la captura y volver al estado inactivo; propaga pausa/reanudación;
  detiene la escucha al detener el servicio. No existe resetear() en este proyecto.
- `lib/screens/home_screen.dart`: import y botón de menú del mismo estilo.
- `lib/widgets/dictado_sheet.dart`: espera confirmación de que la escucha de
  vigilancia se suspendió antes de abrir el dictado existente; libera la
  reserva al cerrar y rechaza nuevas sesiones durante una alarma.
- `test/voice_service_test.dart`: coincidencias, persistencia y transiciones
  del micrófono con el canal del reconocedor simulado.

`pubspec.yaml` ya contiene speech_to_text ^7.5.0 (estable consultada en
pub.dev). AndroidManifest.xml ya declara RECORD_AUDIO, INTERNET,
ACCESS_NETWORK_STATE, los tipos de Foreground Service y la consulta
android.speech.RecognitionService. No necesitan modificaciones.

Para inspeccionar el diff de los archivos existentes:

```powershell
git diff -- lib/services/alarma_service.dart lib/services/background_service.dart lib/screens/home_screen.dart lib/widgets/dictado_sheet.dart
```

Los archivos nuevos están completos en las rutas indicadas; no aparecen en
git diff hasta agregarlos a Git.

## Coordinación del micrófono

VoiceService establece la reserva de forma síncrona para descartar nuevos
disparos y reintentos; después espera la cola de operaciones y cancel() del
reconocedor antes de permitir el inicio de record. Los callbacks tardíos de
sesiones anteriores se ignoran. El PIN falso únicamente silencia la alarma:
no libera la reserva, por lo que record sigue siendo el usuario del micrófono.
Con PIN real o Estoy a salvo, la escucha se reanuda después de detener la
captura. Actualizar opciones no salta reservas ni pausas.

La pausa manual se conserva separada de la reserva de grabación y de la
reserva del dictado de formularios. La UI de configuración no instancia
VoiceService ni escucha: solo escribe preferencias y envía un comando.

## Pruebas automáticas y compilación

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Estas pruebas no envían SMS ni suben archivos. Las pruebas manuales de una
alarma completa sí lo hacen: utiliza contactos de prueba informados.

## Emulador Android

1. Usa una imagen con Google Play/servicios de reconocimiento instalados,
   acceso a internet y entrada del micrófono del equipo habilitada.
2. Ejecuta flutter run, concede permisos y configura los dos PIN.
3. Activa solo palabras, guarda y di "ayuda"; observa la pantalla de alarma
   y los logs de palabra clave y reserva del micrófono.
4. Cancela con PIN real; verifica que aparece VoiceService iniciado y que
   una nueva palabra activa otra alarma.
5. Prueba solo nivel de sonido: empieza con umbral bajo y ajústalo. Verifica
   que nivel inferior no dispara y superior sí.
6. Pausa vigilancia: ni sonidos ni palabras deben activar una alarma.
   Reactiva y vuelve a probar. Desactiva ambos modos y verifica que las
   sacudidas siguen siendo el disparador existente.
7. Sin conexión o sin motor, observa los errores y reintentos; la aplicación
   debe seguir respondiendo. Recupera internet y comprueba la escucha.

El emulador no valida recepción real de SMS ni fiabilidad bajo bloqueo o
restricciones del fabricante; esas comprobaciones requieren teléfono físico.

## Teléfono físico

1. Con SIM habilitada, GPS, internet y contactos de prueba, inicia la
   vigilancia desde la app visible. Concede también los permisos existentes
   de alarma sobre bloqueo y excepción de batería cuando corresponda.
2. Con palabras activas y nivel desactivado, bloquea la pantalla y di
   "socorro" mientras escucha; comprueba alarma, SMS de ubicación, primer
   audio de 10 s y siguientes de 30 s (más el tiempo de subida).
3. Introduce PIN falso: el sonido cesa, pero siguen llegando audios/SMS y
   no debe aparecer un reinicio de VoiceService durante la grabación.
4. Usa Estoy a salvo desde Inicio: debe detener la captura, cerrar el
   incidente y reanudar la escucha. Prueba también el PIN real en otra alarma.
5. Repite con nivel de sonido y ajusta el umbral al teléfono real.
6. Comprueba cambios de configuración durante pausa y alarma: no deben
   reactivar el reconocedor mientras el micrófono esté reservado.
7. Abre el dictado de un formulario sin alarma: debe suspenderse la escucha
   de vigilancia y regresar al cerrar la hoja. No debe dispararse la alarma
   por las palabras que se están dictando al formulario.
8. Repite las sacudidas con voz habilitada para comprobar la misma reserva
   antes de grabar. Revisa que historial, PDF y envío de enlaces mantienen
   el comportamiento anterior.

## Límites del reconocedor

speech_to_text usa sesiones cortas del motor Android. El sistema puede
cerrarlas por silencio, emitir pitidos, limitar solicitudes o suspenderlas
según fabricante. Al terminar por silencio se reinician en 500 ms, y sin
marcar error; ante un error real esperan 3 segundos para no saturar al motor.
Aun así existen huecos de detección: no es un motor
de palabra de activación con escucha continua garantizada. Iniciar el
Foreground Service con la pantalla visible sigue siendo necesario.

Se usa es_ES y se alterna a es_MX si el motor notifica idioma no disponible.
El motor utilizado puede requerir internet para reconocimiento y niveles;
sin él se reintenta, sin sustituir la vigilancia por sacudidas.

Referencias oficiales:
- https://pub.dev/packages/speech_to_text
- https://pub.dev/packages/speech_to_text/versions
- https://developer.android.com/reference/android/speech/SpeechRecognizer

## Correcciones de auditoría

- La activación llama explícitamente a `cancelarDictado` mediante un callback
  enlazado por el Foreground Service. Se envía `cancelarDictado` a la UI con
  el identificador de la sesión y se espera `dictadoCancelado` fuera de la
  cola de comandos, para evitar un bloqueo circular. La UI conserva el
  último parcial y retira únicamente la hoja de dictado, incluso si la alarma
  ya está encima; devuelve el texto al formulario. Las suscripciones se cancelan
  al cerrar y cada hoja registra sus propios callbacks del reconocedor.
- Ubicación/SMS y sirena arrancan mientras se cancela el reconocimiento.
  La grabación espera la liberación acotada del micrófono de servicio y UI.
  No se inicia record antes de intentar cancelar ambos reconocedores: hacerlo
  reproduciría la competencia por el micrófono. Si falla la cancelación se
  registra el error y se intenta grabar igualmente, sin impedir el resto del SOS.
- Todas las operaciones de voz desde AlarmaService están protegidas y
  acotadas. Detener primero finaliza captura; después detiene voz. Se bloquean
  nuevas activaciones durante esa detención. Liberar voz tras cancelar no
  retrasa ni el cierre del incidente ni el aviso a contactos.
- `listen`, `initialize` y `cancel` tienen un timeout de 5 segundos. La
  cancelación del dictado UI tiene 2 segundos y su confirmación entre isolates
  4 segundos. Un timeout no cancela por sí mismo una operación nativa: se
  intenta cancelarla y se descartan callbacks según pausa/reserva/generación.
- El servicio publica `vozEstado` y `vozError`. Inicio distingue escucha,
  conexión, intervalo entre sesiones, pausa, reserva, dictado y desactivación;
  muestra una advertencia persistente mientras existe un error. La notificación
  avisa de incidencias cuando la voz habilitada falla. El modo PIN falso mantiene
  el ocultamiento de errores y no libera el micrófono.
- No se añadieron dependencias ni se cambiaron los bucles de grabación,
  las duraciones 10/30 s, Cloudinary, SMS, PIN, PDF o almacenamiento de incidentes.

Las pruebas de regresión adicionales simulan una alarma sobre una hoja de
dictado y verifican texto parcial, cancelación antes del ACK y conservación
de la pantalla de alarma. También simulan llamadas `listen` y `cancel` sin
respuesta para comprobar que la cola vuelve a funcionar tras el timeout.

En teléfono físico, repetir especialmente dictado → sacudida → alarma,
PIN falso → grabación continua y PIN real → reanudación de voz. Un fallo o
timeout del motor no permite garantizar que Android haya liberado físicamente
el micrófono; debe verificarse que record graba audio utilizable en cada motor
y dispositivo objetivo. Las pruebas automáticas usan canales simulados y no
validan esa condición del hardware.
