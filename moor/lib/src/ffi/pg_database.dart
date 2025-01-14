import 'package:postgres/postgres.dart';

import '../../backends.dart';

///
class PgDatabase extends DelegatedDatabase {
  ///
  PgDatabase(PostgreSQLConnection connection)
      : super(_PgDelegate(connection, connection),
            isSequential: true, logStatements: true);

  ///
  factory PgDatabase.open(String host, int port, String databaseName,
      {String? username,
      String? password,
      int timeoutInSeconds = 30,
      int queryTimeoutInSeconds = 30,
      String timeZone = 'UTC',
      bool useSSL = false,
      bool isUnixSocket = false}) {
    return PgDatabase(PostgreSQLConnection(host, port, databaseName,
        username: username,
        password: password,
        timeoutInSeconds: timeoutInSeconds,
        queryTimeoutInSeconds: queryTimeoutInSeconds,
        timeZone: timeZone,
        useSSL: useSSL,
        isUnixSocket: isUnixSocket));
  }
}

///
class _PgDelegate extends DatabaseDelegate {
  final PostgreSQLConnection _db;
  final PostgreSQLExecutionContext _ec;

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  _PgDelegate(this._db, this._ec) : closeUnderlyingWhenClosed = true;

  bool _hasCreatedDatabase = false;
  bool _isOpen = false;

  final bool closeUnderlyingWhenClosed;

  @override
  TransactionDelegate get transactionDelegate => _PgTransactionDelegate(_db);

  @override
  late DbVersionDelegate versionDelegate;

  @override
  Future<bool> get isOpen => Future.value(_isOpen);

  @override
  Future<void> open(QueryExecutorUser user) async {
    if (!_hasCreatedDatabase) {
      _createDatabase();
      _initializeDatabase();
    }

    versionDelegate = _PgVersionDelegate(_db);
    await _db.open();

    _isOpen = true;
    return Future.value();
  }

  Future _ensureOpen() async {
    if (_db.isClosed) {
      await _db.open();
    }
  }

  void _createDatabase() {
    // TODO: check database existence
    assert(!_hasCreatedDatabase);
    _hasCreatedDatabase = true;
  }

  void _initializeDatabase() {
    // TODO: Do we need create these functions?
    //_db.useMoorVersions();
    //setup?.call(_db);
    versionDelegate = _PgVersionDelegate(_db);
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    await _ensureOpen();
    for (var i = 0; i < statements.statements.length; i++) {
      final stmt = statements.statements[i];
      final args = statements.arguments[i].arguments;

      await _ec.execute(stmt,
          substitutionValues: args
              .asMap()
              .map((key, value) => MapEntry(key.toString(), value)));
    }

    return Future.value();
  }

  Future<int> _runWithArgs(String statement, List<Object?> args) async {
    await _ensureOpen();
    if (args.isEmpty) {
      return _ec.execute(statement);
    } else {
      return _ec.execute(statement,
          substitutionValues: args
              .asMap()
              .map((key, value) => MapEntry(key.toString(), value)));
    }
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    await _runWithArgs(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    await _ensureOpen();
    PostgreSQLResult result;
    if (args.isEmpty) {
      result = await _ec.query(statement);
    } else {
      result = await _ec.query(statement,
          substitutionValues: args
              .asMap()
              .map((key, value) => MapEntry(key.toString(), value)));
    }
    final id = result[0][0];
    return id as int;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    return _runWithArgs(statement, args);
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    await _ensureOpen();
    final result = await _ec.query(statement,
        substitutionValues:
            args.asMap().map((key, value) => MapEntry(key.toString(), value)));

    return Future.value(QueryResult.fromRows(
        result.map((e) => e.toColumnMap()).toList(growable: false)));
  }

  @override
  Future<void> close() async {
    if (closeUnderlyingWhenClosed) {
      await _db.close();
    }
  }
}

/// TODO: create migrate version table
class _PgVersionDelegate extends NoVersionDelegate {
  final PostgreSQLConnection database;

  _PgVersionDelegate(this.database);
}

class _PgTransactionDelegate extends SupportedTransactionDelegate {
  final PostgreSQLConnection _db;

  const _PgTransactionDelegate(this._db);

  @override
  void startTransaction(Future Function(QueryDelegate p1) run) {
    _db.transaction((connection) => run(_PgDelegate(_db, connection)));
  }
}
