/// Opciones y claves del formulario de denuncia (estructura del Formulario
/// Único de Denuncias del Ministerio Público de Bolivia, sin sus datos de
/// registro, que los asigna la institución al recibir la denuncia).
library;

const sexos = ['Femenino', 'Masculino'];

const estadosCiviles = [
  'Soltero/a',
  'Casado/a',
  'Conviviente',
  'Divorciado/a',
  'Viudo/a',
];

const nivelesEducacion = [
  'Ninguno',
  'Primaria',
  'Secundaria',
  'Técnico',
  'Superior',
];

/// Claves guardadas en `Incidente.formulario`. Las del denunciado y la
/// víctima llevan prefijo para no chocar con las del denunciante.
abstract final class CampoFormulario {
  // Lugar y fecha del hecho.
  static const municipio = 'municipio';
  static const zona = 'zona';
  static const direccionHecho = 'direccion_hecho';
  static const horarioHecho = 'horario_hecho';

  // Persona denunciada (además de las columnas *_agresor del incidente).
  static const denSexo = 'den_sexo';
  static const denFechaNacimiento = 'den_fecha_nacimiento';
  static const denEstadoCivil = 'den_estado_civil';
  static const denTelefono = 'den_telefono';
  static const denCorreo = 'den_correo';
  static const denLugarNacimiento = 'den_lugar_nacimiento';
  static const denEducacion = 'den_educacion';
  static const denOcupacion = 'den_ocupacion';
  static const denLugarTrabajo = 'den_lugar_trabajo';
  static const denIdioma = 'den_idioma';

  // Víctima, cuando no es la misma persona que denuncia.
  static const victimaEsDenunciante = 'vic_es_denunciante';
  static const vicNombre = 'vic_nombre';
  static const vicCi = 'vic_ci';
  static const vicSexo = 'vic_sexo';
  static const vicFechaNacimiento = 'vic_fecha_nacimiento';
  static const vicEstadoCivil = 'vic_estado_civil';
  static const vicNacionalidad = 'vic_nacionalidad';
  static const vicOcupacion = 'vic_ocupacion';
  static const vicDomicilio = 'vic_domicilio';
  static const vicLugarTrabajo = 'vic_lugar_trabajo';
  static const vicTelefono = 'vic_telefono';
  static const relacionConVictima = 'relacion_con_victima';
}
