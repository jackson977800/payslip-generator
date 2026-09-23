
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地 SQLite 数据库。表结构与桌面版完全一致，
/// 因此两台设备上的数据文件可以互相拷贝。
class AppDatabase {
  static const _dbName = 'payslip.db';
  static const _version = 2;

  /// 测试时注入临时目录（配合 sqflite_common_ffi）。
  /// 生产环境传 null，走平台默认目录。
  final String? directoryOverride;

  AppDatabase({this.directoryOverride});

  Database? _db;

  Future<Database> get db async {
    final d = _db;
    if (d != null) return d;
    // 用 databaseFactory 而不是顶层 openDatabase，
    // 这样测试里换成 databaseFactoryFfi 就能在桌面跑同一套逻辑。
    final dir = directoryOverride ?? await databaseFactory.getDatabasesPath();
    _db = await databaseFactory.openDatabase(
      p.join(dir, _dbName),
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, version) async {
          await _create(db);
          await _seedDefaults(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _addColumn(db, 'employees', 'email', "TEXT DEFAULT ''");
            await db.execute('''CREATE TABLE IF NOT EXISTS mail_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                employee_id INTEGER, employee_name TEXT,
                period_year INTEGER, period_month INTEGER,
                to_addr TEXT, subject TEXT, status TEXT, error TEXT,
                sent_at TEXT)''');
          }
        },
      ),
    );
    return _db!;
  }

  /// 关闭连接。测试清理临时目录前必须调用，
  /// 否则文件仍被占用（Windows 上会直接报 errno 32）。
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _addColumn(
      Database db, String table, String column, String decl) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final names = cols.map((r) => r['name'].toString()).toSet();
    if (!names.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $decl');
    }
  }

  static Future<void> _create(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY, value TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, nric TEXT DEFAULT '', employee_no TEXT DEFAULT '',
        job_title TEXT DEFAULT '', department TEXT DEFAULT '',
        epf_no TEXT DEFAULT '', socso_no TEXT DEFAULT '', eis_no TEXT DEFAULT '',
        bank_name TEXT DEFAULT '', bank_account TEXT DEFAULT '',
        email TEXT DEFAULT '', basic_salary REAL DEFAULT 0,
        active INTEGER DEFAULT 1, created_at TEXT, updated_at TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS payroll_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL, period_year INTEGER NOT NULL,
        period_month INTEGER NOT NULL,
        basic_salary REAL DEFAULT 0, unpaid_leave REAL DEFAULT 0,
        item_a REAL DEFAULT 0, item_b REAL DEFAULT 0, item_c REAL DEFAULT 0,
        pcb REAL DEFAULT 0, advance REAL DEFAULT 0,
        epf_base REAL DEFAULT 0, socso_base REAL DEFAULT 0, eis_base REAL DEFAULT 0,
        epf_employee REAL DEFAULT 0, epf_employer REAL DEFAULT 0,
        socso_employee REAL DEFAULT 0, socso_employer REAL DEFAULT 0,
        eis_employee REAL DEFAULT 0, eis_employer REAL DEFAULT 0,
        created_at TEXT, updated_at TEXT,
        UNIQUE(employee_id, period_year, period_month))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rate_tables (
        key TEXT PRIMARY KEY, payload TEXT, updated_at TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS mail_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER, employee_name TEXT,
        period_year INTEGER, period_month INTEGER,
        to_addr TEXT, subject TEXT, status TEXT, error TEXT, sent_at TEXT)''');
  }

  // ---------------------------------------------------------------- 设置
  static const Map<String, String> defaultSettings = {
    'company_name': '',
    'company_address': '',
    'company_reg_no': '',
    'company_phone': '',
    'company_email': '',
    'epf_ceiling': '20000',
    'epf_above_employee_rate': '11',
    'epf_above_employer_rate': '12',
    'epf_round_total_up': '1',
    'socso_ceiling': '6000',
    'eis_ceiling': '6000',
    'earnings_labels': '["Basic Salary","Less: Unpaid Leave","Item A","Item B","Item C"]',
    'earnings_enabled': '[true,true,false,false,false]',
    'earnings_in_base': '[true,true,true]',
    'deduction_labels': '["Income Tax (PCB)","Advance to Staff"]',
    'pdf_show_contribution_summary': '1',
    'pdf_show_company_reg': '1',
    'currency_symbol': 'RM',
    'smtp_host': '',
    'smtp_port': '587',
    'smtp_security': 'starttls',
    'smtp_username': '',
    'smtp_auth_required': '1',
    'mail_from_name': '',
    'mail_from_addr': '',
    'mail_reply_to': '',
    'mail_subject_tpl': 'Payslip {Month} {Year} - {Employee Name}',
    'mail_body_tpl':
        'Dear {Employee Name},\n\nPlease find attached your payslip for {Month} {Year}.\n\n{PDF Password Note}\n\nIf you have any questions about this payslip, please contact {Company Name}.\n\nBest regards,\n{Company Name}',
    'mail_attach_pdf': '1',
    'mail_pdf_password': 'ic_last6',
  };

  static Future<void> _seedDefaults(Database db) async {
    final batch = db.batch();
    defaultSettings.forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    await batch.commit(noResult: true);
  }

  Future<String> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return defaultSettings[key] ?? '';
    return (rows.first['value'] ?? '').toString();
  }

  Future<void> setSettings(Map<String, String> values) async {
    final d = await db;
    final batch = d.batch();
    values.forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------ 费率表
  Future<String> getRateTable(String key) async {
    final d = await db;
    final rows = await d.query('rate_tables',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return '';
    return (rows.first['payload'] ?? '').toString();
  }

  Future<void> setRateTable(String key, String payload) async {
    final d = await db;
    await d.insert('rate_tables', {
      'key': key,
      'payload': payload,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // -------------------------------------------------------------- 员工
  Future<List<Map<String, dynamic>>> listEmployees({bool onlyActive = false}) async {
    final d = await db;
    return d.query('employees',
        where: onlyActive ? 'active = 1' : null,
        orderBy: 'active DESC, name COLLATE NOCASE');
  }

  Future<Map<String, dynamic>?> getEmployee(int id) async {
    final d = await db;
    final rows =
        await d.query('employees', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> addEmployee(Map<String, dynamic> values) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    return d.insert('employees', {
      ...values,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateEmployee(int id, Map<String, dynamic> values) async {
    final d = await db;
    await d.update('employees', {...values, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 归档员工（**软删除**）。
  ///
  /// 不删 `employees` 行、更不删 `payroll_runs` ——
  /// 工资记录属于法定留存资料，删掉是合规问题，
  /// 而且 History 里那条记录会直接消失。与电脑版行为一致。
  Future<void> archiveEmployee(int id) async {
    final d = await db;
    await d.update(
      'employees',
      {'active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 恢复已归档的员工
  Future<void> restoreEmployee(int id) async {
    final d = await db;
    await d.update(
      'employees',
      {'active': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 该员工是否已有工资记录（决定能不能「彻底删除」）
  Future<int> runCountFor(int employeeId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT COUNT(*) AS n FROM payroll_runs WHERE employee_id = ?',
        [employeeId]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// 彻底删除：连同工资记录一起抹掉。**不可恢复**。
  /// 只在用户明确确认、且清楚会丢失历史时才调用。
  Future<void> purgeEmployee(int id) async {
    final d = await db;
    await d.delete('payroll_runs', where: 'employee_id = ?', whereArgs: [id]);
    await d.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------- 工资单记录
  Future<Map<String, dynamic>?> getRun(
      int employeeId, int year, int month) async {
    final d = await db;
    final rows = await d.query('payroll_runs',
        where: 'employee_id = ? AND period_year = ? AND period_month = ?',
        whereArgs: [employeeId, year, month],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertRun(Map<String, dynamic> values) async {
    final d = await db;
    await d.insert('payroll_runs', {
      ...values,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> listRuns({int? year, int? month}) async {
    final d = await db;
    String? where;
    List<dynamic> args = [];
    if (year != null && month != null) {
      where = 'period_year = ? AND period_month = ?';
      args = [year, month];
    } else if (year != null) {
      where = 'period_year = ?';
      args = [year];
    }
    return d.rawQuery('''SELECT r.*, e.name AS employee_name,
            e.employee_no, e.nric, e.email
        FROM payroll_runs r LEFT JOIN employees e ON e.id = r.employee_id
        ${where == null ? '' : 'WHERE $where'}
        ORDER BY r.period_year DESC, r.period_month DESC, e.name''', args);
  }

  Future<void> deleteRun(int id) async {
    final d = await db;
    await d.delete('payroll_runs', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ 邮件日志
  Future<void> logMail(Map<String, dynamic> values) async {
    final d = await db;
    await d.insert('mail_log', {
      ...values,
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<int, Map<String, dynamic>>> lastMailStatus(
      int year, int month) async {
    final d = await db;
    final rows = await d.query('mail_log',
        where: 'period_year = ? AND period_month = ?',
        whereArgs: [year, month],
        orderBy: 'id');
    final out = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = r['employee_id'];
      if (id != null) out[(id as num).toInt()] = r;
    }
    return out;
  }
}
