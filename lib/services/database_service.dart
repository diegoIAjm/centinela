import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/contacto.dart';

/// Se abre tanto en la UI como en el servicio en segundo plano (SQLite
/// coordina el acceso entre ambas conexiones).
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'centinela.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contactos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nombre TEXT NOT NULL,
            telefono TEXT NOT NULL
          )
        ''');
        await _crearIncidentes(db);
      },
      onUpgrade: (db, anterior, nueva) async {
        if (anterior < 2) await _crearIncidentes(db);
      },
    );
  }

  Future<void> _crearIncidentes(Database db) => db.execute('''
    CREATE TABLE incidentes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha TEXT NOT NULL,
      lat REAL,
      lon REAL,
      urls_audio TEXT,
      url_pdf TEXT,
      ruta_pdf TEXT,
      finalizado INTEGER NOT NULL DEFAULT 0,
      nombre_agresor TEXT,
      ci_agresor TEXT,
      relacion_agresor TEXT,
      domicilio_agresor TEXT,
      descripcion_agresor TEXT,
      tipo_delito TEXT,
      relato TEXT,
      testigos TEXT,
      observaciones TEXT
    )
  ''');

  Future<int> insertarContacto(Contacto contacto) async {
    final db = await database;
    return await db.insert('contactos', contacto.toMap());
  }

  Future<List<Contacto>> obtenerContactos() async {
    final db = await database;
    final result = await db.query('contactos');
    return result.map((e) => Contacto.fromMap(e)).toList();
  }

  Future<int> eliminarContacto(int id) async {
    final db = await database;
    return await db.delete('contactos', where: 'id = ?', whereArgs: [id]);
  }
}
