import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:mynotes/services/crud/crud_exception.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

class NoteService {
  Database? _db;
  List<DatabaseNote> _notes = [];

  static final NoteService _shared = NoteService._sharedInstance();

//making singleTon
  NoteService._sharedInstance();
  factory NoteService() => _shared;

  final _notesStreamController =
      StreamController<List<DatabaseNote>>.broadcast();

  Stream<List<DatabaseNote>> get AllNotes => _notesStreamController.stream;

  Future<void> _cacheNotes() async {
    final allNotes = await getAllNote();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Future<void> open() async {
    if (_db != null) {
      throw DatabaseAlreadyOpenException();
    } else {
      try {
        final docsPath = await getApplicationDocumentsDirectory();
        final dbPath = join(docsPath.path, dbName);
        final db = await openDatabase(dbPath);
        _db = db;

        //create user table
        db.execute(createUserTable);

        //create user table
        db.execute(createNotesTable);
        await _cacheNotes();
      } on MissingPlatformDirectoryException {
        throw UnableTogetDocumentsDirectory();
      }
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      await db.close();
      _db = null;
    }
  }

  Future<void> _ensureDbIsOpen() async {
    try {
      await open();
    } on DatabaseAlreadyOpenException {
      //empty
    }
  }

  Database _getDatabase() {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      return db;
    }
  }

  Future<void> deleteUserOrThrow({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final deleteAccount = db.delete(userTable,
        where: 'email = ?', whereArgs: [email.toLowerCase()]);

    if (deleteAccount != 1) {
      throw CouldNotdeleteUser();
    }
  }

  Future<DatabaseUser> getOrCreateUser({required String email}) async {
    try {
      final user = await getUser(email: email);
      return user;
    } on UserNotFoundException {
      return await createUser(email: email);
    } catch (e) {
      rethrow;
    }
  }

  Future<DatabaseUser> createUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final result = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (result.isNotEmpty) {
      throw UserAlreadyExist();
    }
    final userId = await db.insert(
      userTable,
      {
        emailColumn: email.toLowerCase(),
      },
    );
    return DatabaseUser(id: userId, email: email);
  }

  Future<DatabaseUser> getUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final result = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (result.isEmpty) {
      throw UserNotFoundException();
    } else {
      return DatabaseUser.fromRow(result.first);
    }
  }

  Future<DatabaseNote> createNote({required DatabaseUser owner}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final dbUser = getUser(email: owner.email);
    if (dbUser != owner) {
      throw UserNotFoundException();
    }
    const text = '';
    final noteID = await db.insert(
      noteTable,
      {
        userIdColumn: owner.id,
        textColumn: text,
        isSyncedCloudColumn: 1,
      },
    );
    final note = DatabaseNote(
      id: noteID,
      userId: owner.id,
      text: text,
      isSyncedCloud: true,
    );

    _notes.add(note);
    _notesStreamController.add(_notes);

    return note;
  }

  Future<void> deleteNoterOrThrow({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final deleteNote =
        await db.delete(noteTable, where: 'id = ?', whereArgs: [id]);

    if (deleteNote == 0) {
      throw CouldNotdeleteNote();
    } else {
      _notes.removeWhere((note) => note.id == id);
      _notesStreamController.add(_notes);
    }
  }

  Future<int> deleteAllNoterOrThrow() async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final numberdeleted = await db.delete(noteTable);
    _notes = [];
    _notesStreamController.add(_notes);
    return numberdeleted;
  }

  Future<DatabaseNote> getNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final result = await db.query(
      noteTable,
      limit: 1,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) {
      throw CouldNotFindNote();
    } else {
      final note = DatabaseNote.fromRow(result.first);
      _notes.removeWhere((note) => note.id == id);
      _notes.add(note);
      _notesStreamController.add(_notes);
      return note;
    }
  }

  Future<Iterable<DatabaseNote>> getAllNote() async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    final notes = await db.query(noteTable);
    return notes.map((notesRow) => DatabaseNote.fromRow(notesRow));
  }

  Future<DatabaseNote> updateNotes({
    required DatabaseNote databaseNote,
    required String text,
  }) async {
    await _ensureDbIsOpen();
    final db = _getDatabase();
    await getNote(id: databaseNote.id);

    final updateCount =
        await db.update(noteTable, {textColumn: text, isSyncedCloudColumn: 0});
    if (updateCount == 0) {
      throw CouldNotUpdateNotes();
    } else {
      final updatednote = await getNote(id: databaseNote.id);

      _notes.removeWhere((note) => note.id == updatednote.id);
      _notes.add(updatednote);
      _notesStreamController.add(_notes);

      return updatednote;
    }
  }
}

@immutable
class DatabaseUser {
  final int id;
  final String email;

  const DatabaseUser({required this.id, required this.email});

  DatabaseUser.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        email = map[emailColumn] as String;

  @override
  String toString() => 'Person, ID=$id, Email=$email';

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DatabaseNote {
  final int id;
  final int userId;
  final String text;
  final bool isSyncedCloud;

  const DatabaseNote({
    required this.id,
    required this.userId,
    required this.text,
    required this.isSyncedCloud,
  });

  DatabaseNote.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        userId = map[userIdColumn] as int,
        text = map[textColumn] as String,
        isSyncedCloud = (map[isSyncedCloudColumn] as int) == 1 ? true : false;

  @override
  String toString() =>
      'Note, ID = $id, UserId = $userId, isSyncedCloud = $isSyncedCloud  ';

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

//all constants
const dbName = 'mynotesdb.db';
const noteTable = 'notes';
const userTable = 'user';

const idColumn = 'id';
const emailColumn = 'email';
const userIdColumn = 'user_id';
const textColumn = 'text';
const isSyncedCloudColumn = "is_synced_cloud";

//creating user table
const createUserTable = ''' 
          CREATE TABLE IF NOT EXISTS "user" (
            "id"	INTEGER NOT NULL,
            "email"	TEXT NOT NULL UNIQUE,
            PRIMARY KEY("id" AUTOINCREMENT)
          );
        ''';
//create user table
const createNotesTable = ''' 
          CREATE TABLE IF NOT EXISTS "notes" (
            "id"	INTEGER NOT NULL,
            "user_id"	INTEGER NOT NULL,
            "text"	TEXT NOT NULL,
            "is_synced_cloud"	INTEGER DEFAULT 0,
            PRIMARY KEY("id" AUTOINCREMENT),
            FOREIGN KEY("user_id") REFERENCES "user"("id")
          );
          ''';
