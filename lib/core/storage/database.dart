import 'dart:typed_data';
import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:flutter/foundation.dart';

part 'database.g.dart';

class Contacts extends Table {
  TextColumn get id        => text()();
  TextColumn get nickname  => text()();
  TextColumn get publicKey => text()();
  IntColumn  get lastSeen  => integer().nullable()();
  BoolColumn get isPinned  => boolean().withDefault(const Constant(false))();
  IntColumn  get createdAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id         => text()();
  TextColumn get contactId  => text()();
  BoolColumn get isOutgoing => boolean()();
  BlobColumn get ciphertext => blob()();
  BlobColumn get nonce      => blob()();
  IntColumn  get timestamp  => integer()();
  IntColumn  get state      => integer().withDefault(const Constant(0))();
  TextColumn get replyToId  => text().nullable()();
  IntColumn  get expiresAt  => integer().nullable()();
  BoolColumn get isMedia    => boolean().withDefault(const Constant(false))();
  TextColumn get mediaId    => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class MediaFiles extends Table {
  TextColumn get id           => text()();
  TextColumn get contactId    => text()();
  BlobColumn get encryptedKey => blob()();
  TextColumn get localPath    => text()();
  IntColumn  get sizeBytes    => integer()();
  TextColumn get mimeType     => text()();
  BoolColumn get autoDelete   => boolean().withDefault(const Constant(false))();
  BoolColumn get isViewed     => boolean().withDefault(const Constant(false))();
  IntColumn  get viewedAt     => integer().nullable()();
  IntColumn  get createdAt    => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class OutboxQueue extends Table {
  TextColumn get id          => text()();
  TextColumn get contactId   => text()();
  BlobColumn get frame       => blob()();
  IntColumn  get createdAt   => integer()();
  IntColumn  get retryCount  => integer().withDefault(const Constant(0))();
  IntColumn  get nextRetryAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class BackupSlots extends Table {
  IntColumn  get slot          => integer()();
  BlobColumn get encryptedBlob => blob()();
  BlobColumn get blobHash      => blob()();
  BlobColumn get salt          => blob()();
  TextColumn get localCode     => text()();
  IntColumn  get createdAt     => integer()();
  IntColumn  get rotatesAt     => integer()();
  @override
  Set<Column> get primaryKey => {slot};
}

@DriftDatabase(tables: [Contacts, Messages, MediaFiles, OutboxQueue, BackupSlots])
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_open());
  static final instance = AppDatabase._();

  Future<void> init() async {
    try {
      await customSelect('SELECT 1').get();
    } catch (e) {
      debugPrint('DB init error: $e');
    }
  }

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() => SqfliteQueryExecutor.inDatabaseFolder(
    path: 'securemsg.db',
    logStatements: false,
  );

  Future<List<Contact>> getAllContacts() => (select(contacts)
    ..orderBy([
          (c) => OrderingTerm.desc(c.isPinned),
          (c) => OrderingTerm.desc(c.lastSeen),
    ]))
      .get();

  Future<Contact?> getContactByPubKey(String pk) =>
      (select(contacts)..where((c) => c.publicKey.equals(pk))).getSingleOrNull();

  Future<void> upsertContact(ContactsCompanion c) =>
      into(contacts).insertOnConflictUpdate(c);

  Future<void> deleteContact(String id) =>
      (delete(contacts)..where((c) => c.id.equals(id))).go();

  Stream<List<Message>> watchMessages(String contactId) =>
      (select(messages)
        ..where((m) => m.contactId.equals(contactId))
        ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
          .watch();

  Future<void> insertMessage(MessagesCompanion msg) =>
      into(messages).insert(msg);

  Future<void> updateMessageState(String id, int state) =>
      (update(messages)..where((m) => m.id.equals(id)))
          .write(MessagesCompanion(state: Value(state)));

  Future<int> purgeExpiredMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (delete(messages)
      ..where((m) =>
      m.expiresAt.isNotNull() &
      m.expiresAt.isSmallerThanValue(now)))
        .go();
  }

  Future<void> deleteConversation(String contactId) =>
      (delete(messages)..where((m) => m.contactId.equals(contactId))).go();

  Future<List<OutboxQueueData>> getPendingOutbox(String contactId) =>
      (select(outboxQueue)
        ..where((o) => o.contactId.equals(contactId))
        ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
          .get();

  Future<void> enqueue(OutboxQueueCompanion item) =>
      into(outboxQueue).insert(item);

  Future<void> dequeue(String id) =>
      (delete(outboxQueue)..where((o) => o.id.equals(id))).go();

  Future<void> bumpRetry(String id, {required int nextRetryAt}) async {
    final row = await (select(outboxQueue)
      ..where((o) => o.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (update(outboxQueue)..where((o) => o.id.equals(id))).write(
      OutboxQueueCompanion(
        retryCount:  Value(row.retryCount + 1),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  Future<BackupSlot?> getBackupSlot(int slot) =>
      (select(backupSlots)..where((b) => b.slot.equals(slot)))
          .getSingleOrNull();

  Future<List<BackupSlot>> getAllBackupSlots() => select(backupSlots).get();

  Future<void> saveBackupSlot(BackupSlotsCompanion slot) =>
      into(backupSlots).insertOnConflictUpdate(slot);
}