// 用桌面版（Python）导出的标准向量验证 Dart 计算引擎。
//
// 向量由 payslip-generator 的引擎生成，逐一比对
// TOTAL / 计费基数 / EPF / SOCSO / EIS / NET —— 必须与桌面版逐分一致。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payslip_app/core/rates.dart';
import 'package:payslip_app/core/payroll.dart';

void main() {
  late RateBook book;
  late List<dynamic> vectors;

  setUp(() {
    final epf = jsonDecode(File('assets/epf_table.json').readAsStringSync());
    final socso =
        jsonDecode(File('assets/socso_eis_table.json').readAsStringSync());
    book = RateBook.fromRows(epf as List<dynamic>, socso as List<dynamic>);
    vectors = jsonDecode(File('test/vectors.json').readAsStringSync());
  });

  /// 桌面版默认停用了 A/B/C 三项，停用的项目按 0 参与计算。
  PayrollInput applyEnabled(PayrollInput inp) => PayrollInput(
        basicSalary: inp.basicSalary,
        unpaidLeave: inp.unpaidLeave,
        itemA: 0,
        itemB: 0,
        itemC: 0,
        pcb: inp.pcb,
        advance: inp.advance,
      );

  void expectClose(String label, double actual, double expected) {
    expect(
      (actual - expected).abs() < 0.005,
      isTrue,
      reason: '$label: got $actual, expected $expected',
    );
  }

  test('费率表加载正确', () {
    expect(book.epf.length, greaterThan(300));
    expect(book.socso.length, greaterThan(50));
    // 必须按 from 升序，近似匹配才成立
    for (var i = 1; i < book.epf.length; i++) {
      expect(
        (book.epf[i]['from'] as num).toDouble() >=
            (book.epf[i - 1]['from'] as num).toDouble(),
        isTrue,
      );
    }
  });

  test('与桌面版引擎逐分一致', () {
    for (final v in vectors) {
      final name = v['name'] as String;
      final i = v['in'] as Map<String, dynamic>;
      final o = v['out'] as Map<String, dynamic>;

      final raw = PayrollInput(
        basicSalary: (i['basic'] as num).toDouble(),
        unpaidLeave: (i['unpaid'] as num).toDouble(),
        itemA: (i['a'] as num).toDouble(),
        itemB: (i['b'] as num).toDouble(),
        itemC: (i['c'] as num).toDouble(),
        pcb: (i['pcb'] as num).toDouble(),
        advance: (i['advance'] as num).toDouble(),
      );
      final r = compute(applyEnabled(raw), book,
          extrasInBase: {'itemA', 'itemB', 'itemC'});

      expectClose('$name total', r.totalSalary, (o['total'] as num).toDouble());
      expectClose('$name base', r.epfBase, (o['base'] as num).toDouble());
      expectClose('$name epf_ee', r.epfEmployee, (o['epf_ee'] as num).toDouble());
      expectClose('$name epf_er', r.epfEmployer, (o['epf_er'] as num).toDouble());
      expectClose(
          '$name socso_ee', r.socsoEmployee, (o['socso_ee'] as num).toDouble());
      expectClose(
          '$name socso_er', r.socsoEmployer, (o['socso_er'] as num).toDouble());
      expectClose('$name eis_ee', r.eisEmployee, (o['eis_ee'] as num).toDouble());
      expectClose('$name eis_er', r.eisEmployer, (o['eis_er'] as num).toDouble());
      expectClose('$name net', r.netSalary, (o['net'] as num).toDouble());
    }
  });

  test('派生合计与净工资公式', () {
    final r = compute(PayrollInput(basicSalary: 1700), book);
    expectClose('雇员合计', r.totalEmployeeContribution,
        r.epfEmployee + r.socsoEmployee + r.eisEmployee);
    expectClose('雇主合计', r.totalEmployerContribution,
        r.epfEmployer + r.socsoEmployer + r.eisEmployer);
    // NET = TOTAL - EPF雇员 - SOCSO雇员 - EIS雇员 - PCB - Advance
    expectClose('net', r.netSalary,
        r.totalSalary - r.totalDeductions);
    expect(r.netSalary, 1489.10);
  });

  test('额外收入项可计入计费基数', () {
    final inp = PayrollInput(basicSalary: 1700, itemA: 300);
    final without = compute(inp, book);
    final withBase = compute(inp, book, extrasInBase: {'itemA'});

    expect(without.epfBase, 1700.00);
    expect(withBase.epfBase, 2000.00);
    expect(withBase.epfEmployee, 220.00);
    expect(withBase.socsoEmployee, 24.40);
    expect(withBase.eisEmployee, 3.90);
    // Total Salary 两种情况下都一样 —— 佣金照发，只影响缴金基数
    expect(withBase.totalSalary, without.totalSalary);
    // 计入基数后扣缴更多，净工资更低
    expect(withBase.netSalary, lessThan(without.netSalary));
  });

  test('超过 EPF 上限时按比例计算', () {
    final r = compute(PayrollInput(basicSalary: 21000), book);
    expect(r.epfBase, 21000.00);
    expect(r.epfEmployee, 2310.00); // 21000 * 11%
    expect(r.epfEmployer, 2520.00); // 21000 * 12%
    // SOCSO / EIS 仍按 6000 上限封顶
    expect(r.socsoEmployee, 74.40);
    expect(r.eisEmployee, 11.90);
  });

  test('无薪假按扣减处理', () {
    final r = compute(PayrollInput(basicSalary: 1700, unpaidLeave: 30), book);
    expect(r.totalSalary, 1670.00);
    expect(r.epfBase, 1670.00);
    expect(r.netSalary, 1461.10);
  });

  test('校验规则', () {
    expect(validatePayslip('', 2026, 9, PayrollInput(basicSalary: 1700)),
        isNotEmpty);
    expect(validatePayslip('Ahmad', null, 9, PayrollInput(basicSalary: 1700)),
        isNotEmpty);
    expect(validatePayslip('Ahmad', 2026, 9, PayrollInput()), isNotEmpty);
    expect(validatePayslip('Ahmad', 2026, 9, PayrollInput(basicSalary: 1700)),
        isEmpty);
    expect(
        validatePayslip(
            'Ahmad', 2026, 9, PayrollInput(basicSalary: 1700, unpaidLeave: -5)),
        isNotEmpty);
  });
}
