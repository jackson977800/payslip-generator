import 'dart:convert';

import 'core/database.dart';
import 'core/mail.dart';
import 'core/payroll.dart';
import 'core/payslip_pdf.dart';
import 'core/rates.dart';

/// 业务规则层 —— 与桌面版 services.py 一一对应。
/// 所有「停用项按 0」「额外项是否计入缴金基数」「PDF 密码」等规则都在这里，
/// 界面不直接调用 compute()，避免漏掉规则。
class Services {
  final AppDatabase db;
  Services(this.db);

  // ------------------------------------------------------------ 设置读取
  Future<Map<String, String>> _settings() async {
    final out = <String, String>{};
    for (final k in AppDatabase.defaultSettings.keys) {
      out[k] = await db.getSetting(k);
    }
    return out;
  }

  static List<String> _jsonList(String s, List<String> fallback) {
    try {
      final v = jsonDecode(s);
      if (v is List) return v.map((e) => '$e').toList();
    } catch (_) {}
    return fallback;
  }

  static List<bool> _jsonBoolList(String s, List<bool> fallback) {
    try {
      final v = jsonDecode(s);
      if (v is List) return v.map((e) => e == true || e == 'true').toList();
    } catch (_) {}
    return fallback;
  }

  Future<List<String>> earningsLabels() async {
    final s = await db.getSetting('earnings_labels');
    return _jsonList(s, const ['Basic Salary', 'Less: Unpaid Leave',
                               'Item A', 'Item B', 'Item C']);
  }

  Future<List<bool>> earningsEnabled() async {
    final s = await db.getSetting('earnings_enabled');
    return _jsonBoolList(s, const [true, true, false, false, false]);
  }

  /// 需要计入 EPF / SOCSO / EIS 计费基数的额外收入项
  Future<Set<String>> earningsInBase() async {
    final s = await db.getSetting('earnings_in_base');
    final flags = _jsonBoolList(s, const [true, true, true]);
    const keys = ['itemA', 'itemB', 'itemC'];
    final out = <String>{};
    for (var i = 0; i < 3 && i < flags.length; i++) {
      if (flags[i]) out.add(keys[i]);
    }
    return out;
  }

  Future<List<String>> deductionLabels() async {
    final s = await db.getSetting('deduction_labels');
    return _jsonList(s, const ['Income Tax (PCB)', 'Advance to Staff']);
  }

  /// 下一个月，跨年自动进位。
  /// 例：2026-12 → (2027, 1)
  static (int, int) nextPeriod(int year, int month) =>
      month >= 12 ? (year + 1, 1) : (year, month + 1);

  /// 上一个月，跨年自动退位。
  static (int, int) prevPeriod(int year, int month) =>
      month <= 1 ? (year - 1, 12) : (year, month - 1);

  /// 年份候选列表（升序）。
  ///
  /// 以当前年份为中心前后各留 [back] / [forward] 年，
  /// **并合并数据库里已有记录的年份** —— 这样任何历史或未来年份都不会被漏掉。
  /// 与电脑版 services.year_choices 行为一致。
  Future<List<int>> yearChoices({int back = 20, int forward = 10}) async {
    final now = DateTime.now().year;
    final years = <int>{
      for (var y = now - back; y <= now + forward; y++) y,
    };
    try {
      final d = await db.db;
      final rows =
          await d.rawQuery('SELECT DISTINCT period_year FROM payroll_runs');
      for (final r in rows) {
        final y = r['period_year'];
        if (y is num) years.add(y.toInt());
      }
    } catch (_) {
      // 数据库不可用时退回默认区间，不阻塞界面
    }
    final out = years.where((y) => y >= 1900 && y <= 2200).toList()..sort();
    return out;
  }

  Future<RateBook> rateBook() async {
    final s = await _settings();
    return RateBook.load(
      epfCeiling: double.tryParse(s['epf_ceiling'] ?? '20000') ?? 20000,
      epfAboveEe: double.tryParse(s['epf_above_employee_rate'] ?? '11') ?? 11,
      epfAboveEr: double.tryParse(s['epf_above_employer_rate'] ?? '12') ?? 12,
      epfRoundUp: (s['epf_round_total_up'] ?? '1') == '1',
    );
  }

  // ------------------------------------------------------------ 计算
  /// 停用的收入项目按 0 参与计算
  static PayrollInput applyEnabled(PayrollInput inp, List<bool> en) {
    return PayrollInput(
      basicSalary: inp.basicSalary,
      unpaidLeave: inp.unpaidLeave,
      itemA: (en.length > 2 && en[2]) ? inp.itemA : 0,
      itemB: (en.length > 3 && en[3]) ? inp.itemB : 0,
      itemC: (en.length > 4 && en[4]) ? inp.itemC : 0,
      pcb: inp.pcb,
      advance: inp.advance,
    );
  }

  /// 按当前设置计算 —— 业务路径统一走这里
  Future<PayrollResult> computeFor(PayrollInput inp) async {
    final book = await rateBook();
    final en = await earningsEnabled();
    final base = await earningsInBase();
    return compute(applyEnabled(inp, en), book, extrasInBase: base);
  }

  // ------------------------------------------------- 收入 / 扣款行（PDF）
  Future<List<List<dynamic>>> buildEarnings(PayrollResult r) async {
    final labels = await earningsLabels();
    final en = await earningsEnabled();
    final rows = <List<dynamic>>[];
    rows.add([labels[0], r.basicSalary]);
    rows.add([labels[1], r.unpaidLeave == 0 ? 0.0 : -r.unpaidLeave]);
    if (en.length > 2 && en[2]) rows.add([labels[2], r.itemA]);
    if (en.length > 3 && en[3]) rows.add([labels[3], r.itemB]);
    if (en.length > 4 && en[4]) rows.add([labels[4], r.itemC]);
    return rows;
  }

  Future<List<List<dynamic>>> buildDeductions(PayrollResult r) async {
    final labels = await deductionLabels();
    return [
      ['EPF (Employee)', r.epfEmployee, r.epfEmployer],
      ['SOCSO (Employee)', r.socsoEmployee, r.socsoEmployer],
      ['EIS (Employee)', r.eisEmployee, r.eisEmployer],
      [labels.isNotEmpty ? labels[0] : 'Income Tax (PCB)', r.pcb, 0.0],
      [labels.length > 1 ? labels[1] : 'Advance to Staff', r.advance, 0.0],
    ];
  }

  // ---------------------------------------------------- 当月记录状态
  static const statusReady = 'Ready';
  static const statusDefault = 'Basic salary only';
  static const statusMissing = 'Missing basic salary';

  /// 返回 (记录, 结果, 状态)。
  /// 当月没有记录但员工有基本工资时，直接按基本工资算出结果。
  Future<(Map<String, dynamic>?, PayrollResult?, String)> monthStatus(
      Map<String, dynamic> employee, int year, int month) async {
    final id = (employee['id'] as num).toInt();
    final run = await db.getRun(id, year, month);
    if (run != null) {
      final inp = _inputFromRun(run);
      return (run, await computeFor(inp), statusReady);
    }
    final basic = (employee['basic_salary'] as num?)?.toDouble() ?? 0;
    if (basic <= 0) return (null, null, statusMissing);
    final res = await computeFor(PayrollInput(basicSalary: basic));
    return (null, res, statusDefault);
  }

  static PayrollInput _inputFromRun(Map<String, dynamic> run) {
    double g(String k) => (run[k] as num?)?.toDouble() ?? 0;
    return PayrollInput(
      basicSalary: g('basic_salary'),
      unpaidLeave: g('unpaid_leave'),
      itemA: g('item_a'),
      itemB: g('item_b'),
      itemC: g('item_c'),
      pcb: g('pcb'),
      advance: g('advance'),
    );
  }

  static PayrollInput inputFromRun(Map<String, dynamic> run) =>
      _inputFromRun(run);

  /// 无记录时按基本工资创建记录并落库（History 可查）
  Future<(PayrollResult?, bool)> ensureRun(
      Map<String, dynamic> employee, int year, int month) async {
    final id = (employee['id'] as num).toInt();
    final existing = await db.getRun(id, year, month);
    if (existing != null) {
      return (await computeFor(_inputFromRun(existing)), false);
    }
    final basic = (employee['basic_salary'] as num?)?.toDouble() ?? 0;
    if (basic <= 0) return (null, false);
    final inp = PayrollInput(basicSalary: basic);
    final res = await computeFor(inp);
    await saveRun(employee, year, month, inp, res);
    return (res, true);
  }

  Future<void> saveRun(Map<String, dynamic> employee, int year, int month,
      PayrollInput inp, PayrollResult r) async {
    await db.upsertRun({
      'employee_id': (employee['id'] as num).toInt(),
      'period_year': year,
      'period_month': month,
      'basic_salary': r.basicSalary,
      'unpaid_leave': r.unpaidLeave,
      'item_a': r.itemA,
      'item_b': r.itemB,
      'item_c': r.itemC,
      'pcb': r.pcb,
      'advance': r.advance,
      'epf_base': r.epfBase,
      'socso_base': r.socsoBase,
      'eis_base': r.eisBase,
      'epf_employee': r.epfEmployee,
      'epf_employer': r.epfEmployer,
      'socso_employee': r.socsoEmployee,
      'socso_employer': r.socsoEmployer,
      'eis_employee': r.eisEmployee,
      'eis_employer': r.eisEmployer,
    });
  }

  // -------------------------------------------------------- PDF 生成
  Future<Map<String, dynamic>> company() async => {
        'company_name': await db.getSetting('company_name'),
        'company_address': await db.getSetting('company_address'),
        'company_reg_no': await db.getSetting('company_reg_no'),
        'company_phone': await db.getSetting('company_phone'),
        'company_email': await db.getSetting('company_email'),
      };

  Future<Map<String, dynamic>> pdfOptions() async => {
        'pdf_show_contribution_summary':
            await db.getSetting('pdf_show_contribution_summary'),
        'pdf_show_company_reg': await db.getSetting('pdf_show_company_reg'),
        'currency_symbol': await db.getSetting('currency_symbol'),
      };

  /// 按设置从员工资料推导 PDF 密码；无法推导时返回空串（不加密）。
  ///
  /// 马来西亚 IC 形如 900101-14-1234，先去掉非数字字符再取后 N 位 ——
  /// 「后 6 位」指后 6 个**数字**，不能把连字符算进去。
  Future<String> pdfPassword(Map<String, dynamic> employee) async {
    final rule = await db.getSetting('mail_pdf_password');
    if (rule == 'none' || rule.isEmpty) return '';
    final digits =
        '${employee['nric'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (rule == 'ic_full') return digits;
    final n = rule == 'ic_last4' ? 4 : 6;
    return digits.length >= n ? digits.substring(digits.length - n) : '';
  }

  Future<String> passwordNote(Map<String, dynamic>? employee) async {
    final rule = await db.getSetting('mail_pdf_password');
    if (rule == 'none' || rule.isEmpty) return '';
    if (employee != null && (await pdfPassword(employee)).isEmpty) return '';
    if (rule == 'ic_last4') {
      return 'The attached payslip is password-protected. '
          'Your password is the last 4 digits of your IC number.';
    }
    if (rule == 'ic_full') {
      return 'The attached payslip is password-protected. '
          'Your password is your full IC number (digits only).';
    }
    return 'The attached payslip is password-protected. '
        'Your password is the last 6 digits of your IC number.';
  }

  /// 生成工资单 PDF，返回文件字节与文件名。
  ///
  /// [withPassword] 为 false 时生成**不带密码**的副本 ——
  /// 用于应用内预览（否则老板自己也打不开自己生成的工资单）。
  /// 发给员工的始终是带密码的那一份。
  Future<(List<int>, String)> renderPayslip(
    Map<String, dynamic> employee,
    int year,
    int month,
    PayrollResult r, {
    bool withPassword = true,
  }) async {
    final data = PayslipData(
      company: await company(),
      employee: employee,
      year: year,
      month: month,
      result: r,
      earnings: await buildEarnings(r),
      deductions: await buildDeductions(r),
      options: await pdfOptions(),
    );
    final pw = withPassword ? await pdfPassword(employee) : '';
    final bytes = await buildPayslipPdf(data, password: pw);
    return (bytes, pdfFileName('${employee['name'] ?? ''}', month, year));
  }

  // ------------------------------------------------------------ 邮件
  Future<MailConfig> mailConfig(String password) async {
    return MailConfig(
      host: await db.getSetting('smtp_host'),
      port: int.tryParse(await db.getSetting('smtp_port')) ?? 587,
      security: await db.getSetting('smtp_security'),
      username: await db.getSetting('smtp_username'),
      password: password,
      fromName: await db.getSetting('mail_from_name'),
      fromAddr: await db.getSetting('mail_from_addr'),
      replyTo: await db.getSetting('mail_reply_to'),
      authRequired: (await db.getSetting('smtp_auth_required')) == '1',
    );
  }

  static String renderTemplate(String tpl, Map<String, String> m) {
    var out = tpl;
    m.forEach((k, v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }

  Future<Map<String, String>> templateMapping(
      Map<String, dynamic> employee, int year, int month,
      PayrollResult? r) async {
    return {
      'Employee Name': '${employee['name'] ?? ''}',
      'Employee ID': '${employee['employee_no'] ?? ''}',
      'Month': monthName(month),
      'Year': '$year',
      'Company Name': await db.getSetting('company_name'),
      'Net Salary': money(r?.netSalary ?? 0),
      'Total Salary': money(r?.totalSalary ?? 0),
      'PDF Password Note': await passwordNote(employee),
    };
  }

  Future<String> mailSubject(Map<String, dynamic> employee, int year,
      int month, PayrollResult? r) async {
    final tpl = await db.getSetting('mail_subject_tpl');
    return renderTemplate(tpl, await templateMapping(employee, year, month, r));
  }

  Future<String> mailBody(Map<String, dynamic> employee, int year, int month,
      PayrollResult? r) async {
    final tpl = await db.getSetting('mail_body_tpl');
    var body = renderTemplate(tpl, await templateMapping(employee, year, month, r));
    // 旧模板没有 {PDF Password Note} 时把说明补到末尾，
    // 否则员工收到加密附件却不知道密码。
    final note = await passwordNote(employee);
    if (note.isNotEmpty && !tpl.contains('{PDF Password Note}') &&
        !body.contains(note)) {
      body = '${body.trimRight()}\n\n$note';
    }
    while (body.contains('\n\n\n')) {
      body = body.replaceAll('\n\n\n', '\n\n');
    }
    return '${body.trim()}\n';
  }

  static String mailRecipient(Map<String, dynamic> e) =>
      '${e['email'] ?? ''}'.trim();
}
