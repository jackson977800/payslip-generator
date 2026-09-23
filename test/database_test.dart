// 数据层测试：重点验证「保存设置」这条路径真的写进数据库并且能读回来。
//
// 用 sqflite_common_ffi 在桌面上跑真实的 SQLite，
// 与 Android 上是同一套 SQL 逻辑。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payslip_app/core/database.dart';
import 'package:payslip_app/core/payroll.dart';
import 'package:payslip_app/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late AppDatabase database;

  setUpAll(() {
    // Services.computeFor 会经 rootBundle 读 assets/ 下的费率表，
    // 没有初始化绑定的话会拿不到资源。
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('payslip_db_test');
    database = AppDatabase(directoryOverride: tmp.path);
  });

  tearDown(() async {
    // 先关连接，否则 Windows 上临时目录删不掉（errno 32）
    await database.close();
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {
      // 清理失败不应让测试变红
    }
  });

  test('首次打开会建表并写入全部默认设置', () async {
    await database.db;
    final all = await database.db.then((d) => d.query('settings'));
    expect(all.length, AppDatabase.defaultSettings.length,
        reason: '默认设置应全部落库');
    expect(await database.getSetting('company_name'), '');
    expect(await database.getSetting('mail_pdf_password'), 'ic_last6');
    expect(await database.getSetting('epf_ceiling'), '20000');
  });

  test('保存设置后能读回新值（覆盖写）', () async {
    await database.db;
    await database.setSettings({
      'company_name': 'Demo Salon Sdn Bhd',
      'company_reg_no': '202301234567',
      'smtp_host': 'smtp.gmail.com',
      'smtp_port': '587',
      'mail_pdf_password': 'ic_last4',
    });

    expect(await database.getSetting('company_name'),
        'Demo Salon Sdn Bhd');
    expect(await database.getSetting('company_reg_no'), '202301234567');
    expect(await database.getSetting('smtp_host'), 'smtp.gmail.com');
    expect(await database.getSetting('mail_pdf_password'), 'ic_last4');
    // 未改动的项必须保持原值，不能被清空
    expect(await database.getSetting('epf_ceiling'), '20000');
  });

  test('保存设置不会重复插入行（key 是主键）', () async {
    await database.db;
    final before = (await database.db.then((d) => d.query('settings'))).length;
    await database.setSettings({'company_name': 'A'});
    await database.setSettings({'company_name': 'B'});
    await database.setSettings({'company_name': 'C'});
    final after = (await database.db.then((d) => d.query('settings'))).length;
    expect(after, before, reason: '重复保存不应新增行');
    expect(await database.getSetting('company_name'), 'C');
  });

  test('重开数据库后设置仍在（真的落盘了）', () async {
    await database.db;
    await database.setSettings({'company_name': 'Persisted Sdn Bhd'});
    // 换一个全新实例，模拟应用重启
    final reopened = AppDatabase(directoryOverride: tmp.path);
    expect(await reopened.getSetting('company_name'), 'Persisted Sdn Bhd');
  });

  test('设置页会写入的每一项都能存能读', () async {
    await database.db;
    final values = <String, String>{
      // 公司
      'company_name': 'Test Salon',
      'company_address': '12, Jalan Besar',
      'company_reg_no': 'REG123',
      'company_phone': '03-1234 5678',
      'company_email': 'hr@test.my',
      // 费率
      'epf_ceiling': '20000',
      'epf_above_employee_rate': '11',
      'epf_above_employer_rate': '12',
      // 邮件
      'smtp_host': 'smtp.example.com',
      'smtp_port': '465',
      'smtp_security': 'ssl',
      'smtp_username': 'user@test.my',
      'smtp_auth_required': '1',
      'mail_from_name': 'HR',
      'mail_from_addr': 'hr@test.my',
      'mail_reply_to': 'boss@test.my',
      'mail_subject_tpl': 'Payslip {Month} {Year}',
      'mail_body_tpl': 'Dear {Employee Name},\n\nAttached.\n',
      'mail_pdf_password': 'ic_last6',
      // 工资项（JSON）
      'earnings_labels':
          jsonEncode(['Basic Salary', 'Less: Unpaid Leave', 'Commission',
                      'Bonus', 'Item C']),
      'earnings_enabled': jsonEncode([true, true, true, false, false]),
      'earnings_in_base': jsonEncode([true, false, true]),
      'deduction_labels': jsonEncode(['PCB', 'Advance']),
    };

    await database.setSettings(values);
    for (final e in values.entries) {
      expect(await database.getSetting(e.key), e.value,
          reason: '${e.key} 应能原样读回');
    }

    // JSON 字段要能被业务层正确解析
    final labels = jsonDecode(await database.getSetting('earnings_labels'))
        as List<dynamic>;
    expect(labels[2], 'Commission');
    final enabled = jsonDecode(await database.getSetting('earnings_enabled'))
        as List<dynamic>;
    expect(enabled[2], isTrue);
    expect(enabled[3], isFalse);
  });

  test('员工与工资记录可写入并读回', () async {
    await database.db;
    final id = await database.addEmployee({
      'name': 'Ahmad bin Ali',
      'nric': '900101-14-0001',
      'employee_no': 'A01',
      'email': 'jackson@test.my',
      'basic_salary': 1700.0,
      'active': 1,
    });
    expect(id, greaterThan(0));

    final emp = await database.getEmployee(id);
    expect(emp!['name'], 'Ahmad bin Ali');
    expect((emp['basic_salary'] as num).toDouble(), 1700.0);

    await database.upsertRun({
      'employee_id': id,
      'period_year': 2026,
      'period_month': 9,
      'basic_salary': 1700.0,
      'epf_base': 1700.0,
      'epf_employee': 187.0,
      'epf_employer': 221.0,
    });
    final run = await database.getRun(id, 2026, 9);
    expect(run, isNotNull);
    expect((run!['epf_employee'] as num).toDouble(), 187.0);

    // 同一员工同一月份重复写应该覆盖而不是新增
    await database.upsertRun({
      'employee_id': id,
      'period_year': 2026,
      'period_month': 9,
      'basic_salary': 1800.0,
      'epf_base': 1800.0,
      'epf_employee': 198.0,
      'epf_employer': 234.0,
    });
    final runs = await database.listRuns(year: 2026, month: 9);
    expect(runs.length, 1, reason: '同月同员工应只有一条');
    expect((runs.first['epf_employee'] as num).toDouble(), 198.0);
  });

  group('归档而非删除 —— 工资历史必须留存', () {
    late int empId;

    setUp(() async {
      await database.db;
      empId = await database.addEmployee({
        'name': 'Ahmad bin Ali',
        'nric': '900101-14-0001',
        'employee_no': 'A01',
        'basic_salary': 1700.0,
        'active': 1,
      });
      await database.upsertRun({
        'employee_id': empId,
        'period_year': 2026,
        'period_month': 8,
        'basic_salary': 1700.0,
        'epf_employee': 187.0,
      });
      await database.upsertRun({
        'employee_id': empId,
        'period_year': 2026,
        'period_month': 9,
        'basic_salary': 1700.0,
        'epf_employee': 187.0,
      });
    });

    test('归档后员工还在，工资记录一条不少', () async {
      await database.archiveEmployee(empId);

      // 员工行保留（只是 active=0）
      final emp = await database.getEmployee(empId);
      expect(emp, isNotNull, reason: '不能真的删掉员工行');
      expect((emp!['active'] as num).toInt(), 0);

      // 关键断言：工资记录必须还在
      expect(await database.runCountFor(empId), 2);
      final runs = await database.listRuns();
      expect(runs.length, 2, reason: '工资历史属于留存资料，归档不能动它');
    });

    test('归档后不出现在「在职」列表，但仍在完整列表里', () async {
      await database.archiveEmployee(empId);

      final active = await database.listEmployees(onlyActive: true);
      expect(active.where((e) => (e['id'] as num).toInt() == empId), isEmpty,
          reason: '归档员工不该出现在算薪列表');

      final all = await database.listEmployees();
      expect(all.where((e) => (e['id'] as num).toInt() == empId), isNotEmpty,
          reason: '归档员工要能被找到并恢复');
    });

    test('可以恢复归档员工', () async {
      await database.archiveEmployee(empId);
      await database.restoreEmployee(empId);

      final emp = await database.getEmployee(empId);
      expect((emp!['active'] as num).toInt(), 1);
      final active = await database.listEmployees(onlyActive: true);
      expect(active.where((e) => (e['id'] as num).toInt() == empId), isNotEmpty);
      expect(await database.runCountFor(empId), 2, reason: '恢复不该影响历史');
    });

    test('彻底删除才会清掉工资记录', () async {
      await database.purgeEmployee(empId);

      expect(await database.getEmployee(empId), isNull);
      expect(await database.runCountFor(empId), 0);
      expect((await database.listRuns()).length, 0);
    });

    test('runCountFor 让 UI 能提前告知会丢多少条记录', () async {
      expect(await database.runCountFor(empId), 2);
      await database.upsertRun({
        'employee_id': empId,
        'period_year': 2026,
        'period_month': 10,
        'basic_salary': 1700.0,
      });
      expect(await database.runCountFor(empId), 3);
    });
  });

  group('保存时不能抹掉停用项目的已存金额', () {
    late Services svc;
    late Map<String, dynamic> emp;

    setUp(() async {
      await database.db;
      svc = Services(database);
      final id = await database.addEmployee({
        'name': 'Ahmad bin Ali',
        'nric': '900101-14-0001',
        'employee_no': 'D01',
        'basic_salary': 1700.0,
        'active': 1,
      });
      emp = (await database.getEmployee(id))!;
    });

    test('启用 Item A 时正常存下佣金', () async {
      await database.setSettings({
        'earnings_enabled': jsonEncode([true, true, true, false, false]),
      });
      final inp = const PayrollInput(basicSalary: 1700, itemA: 150);
      final r = await svc.computeFor(inp);
      await svc.saveRun(emp, 2026, 9, inp, r);

      final run = await database.getRun((emp['id'] as num).toInt(), 2026, 9);
      expect((run!['item_a'] as num).toDouble(), 150.0);
    });

    test('之后停用 Item A，再保存旧月份不会抹掉那笔佣金', () async {
      // 1) 先启用并录一笔佣金
      await database.setSettings({
        'earnings_enabled': jsonEncode([true, true, true, false, false]),
      });
      final inp1 = const PayrollInput(basicSalary: 1700, itemA: 150);
      await svc.saveRun(emp, 2026, 9, inp1, await svc.computeFor(inp1));

      // 2) 设置里把 Item A 关掉 —— 界面上这个字段会隐藏，
      //    用户不可能再去改它
      await database.setSettings({
        'earnings_enabled': jsonEncode([true, true, false, false, false]),
      });

      // 3) 用户回到这个旧月份点保存。表单里读到的是空 → 0
      final inp2 = const PayrollInput(basicSalary: 1700);
      await svc.saveRun(emp, 2026, 9, inp2, await svc.computeFor(inp2));

      // 4) 那笔佣金必须还在
      final run = await database.getRun((emp['id'] as num).toInt(), 2026, 9);
      expect((run!['item_a'] as num).toDouble(), 150.0,
          reason: '停用的项目在界面上是隐藏的，保存不该把已存金额清零');
    });

    test('用户主动把项目改成别的金额时，新值要生效', () async {
      await database.setSettings({
        'earnings_enabled': jsonEncode([true, true, true, false, false]),
      });
      final a = const PayrollInput(basicSalary: 1700, itemA: 150);
      await svc.saveRun(emp, 2026, 9, a, await svc.computeFor(a));

      // 用户把佣金改成 300 —— 应该覆盖，不是保留 150
      final b = const PayrollInput(basicSalary: 1700, itemA: 300);
      await svc.saveRun(emp, 2026, 9, b, await svc.computeFor(b));

      final run = await database.getRun((emp['id'] as num).toInt(), 2026, 9);
      expect((run!['item_a'] as num).toDouble(), 300.0);
    });

    test('新月份本来就没有值，保存后仍是 0（防护不误伤）', () async {
      await database.setSettings({
        'earnings_enabled': jsonEncode([true, true, false, false, false]),
      });
      final inp = const PayrollInput(basicSalary: 1700);
      await svc.saveRun(emp, 2026, 11, inp, await svc.computeFor(inp));

      final run = await database.getRun((emp['id'] as num).toInt(), 2026, 11);
      expect((run!['item_a'] as num).toDouble(), 0.0);
    });
  });

  test('年份候选覆盖当前年份前后，并合并数据库已有年份', () async {
    await database.db;
    final svc = Services(database);
    final now = DateTime.now().year;

    final years = await svc.yearChoices();
    expect(years.contains(now), isTrue, reason: '必须包含今年');
    expect(years.contains(now + 5), isTrue, reason: '未来年份要够用');
    expect(years.contains(now - 15), isTrue, reason: '历史年份要够用');
    expect(years, orderedEquals(List<int>.from(years)..sort()),
        reason: '必须升序');

    // 数据库里存在一个超出默认区间之外的年份，也必须出现
    final id = await database.addEmployee({'name': 'X', 'basic_salary': 1.0});
    await database.upsertRun({
      'employee_id': id,
      'period_year': now + 40,
      'period_month': 1,
    });
    final withFuture = await svc.yearChoices();
    expect(withFuture.contains(now + 40), isTrue,
        reason: '数据库已有的年份不能被漏掉');
  });
}
