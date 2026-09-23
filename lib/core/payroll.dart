import 'rates.dart';

/// 工资单输入。与桌面版 PayrollInput 字段一一对应。
///
/// 注意：unpaidLeave 以**正数**录入（老板视角是扣款），
/// 内部按 Excel 的负数语义参与运算。
class PayrollInput {
  final double basicSalary;
  final double unpaidLeave;
  final double itemA;
  final double itemB;
  final double itemC;
  final double pcb;
  final double advance;

  const PayrollInput({
    this.basicSalary = 0,
    this.unpaidLeave = 0,
    this.itemA = 0,
    this.itemB = 0,
    this.itemC = 0,
    this.pcb = 0,
    this.advance = 0,
  });

  PayrollInput copyWith({
    double? basicSalary,
    double? unpaidLeave,
    double? itemA,
    double? itemB,
    double? itemC,
    double? pcb,
    double? advance,
  }) =>
      PayrollInput(
        basicSalary: basicSalary ?? this.basicSalary,
        unpaidLeave: unpaidLeave ?? this.unpaidLeave,
        itemA: itemA ?? this.itemA,
        itemB: itemB ?? this.itemB,
        itemC: itemC ?? this.itemC,
        pcb: pcb ?? this.pcb,
        advance: advance ?? this.advance,
      );
}

/// 计算结果。字段名与桌面版 Python 的 PayrollResult 一一对应。
class PayrollResult {
  final double basicSalary;
  final double unpaidLeave;
  final double itemA;
  final double itemB;
  final double itemC;
  final double pcb;
  final double advance;

  final double epfBase;
  final double socsoBase;
  final double eisBase;

  final double totalSalary;
  final double epfEmployee;
  final double epfEmployer;
  final double socsoEmployee;
  final double socsoEmployer;
  final double eisEmployee;
  final double eisEmployer;

  final double netSalary;

  final double totalEmployeeContribution;
  final double totalEmployerContribution;
  final double totalContribution;
  final double totalDeductions;

  const PayrollResult({
    required this.basicSalary,
    required this.unpaidLeave,
    required this.itemA,
    required this.itemB,
    required this.itemC,
    required this.pcb,
    required this.advance,
    required this.epfBase,
    required this.socsoBase,
    required this.eisBase,
    required this.totalSalary,
    required this.epfEmployee,
    required this.epfEmployer,
    required this.socsoEmployee,
    required this.socsoEmployer,
    required this.eisEmployee,
    required this.eisEmployer,
    required this.netSalary,
    required this.totalEmployeeContribution,
    required this.totalEmployerContribution,
    required this.totalContribution,
    required this.totalDeductions,
  });
}

/// 计算一张工资单 —— 严格复刻参考 Excel 的公式。
///
/// Excel 原始公式：
///   H  TOTAL   = Basic + UnpaidLeave(负) + A + B + C
///   AG/AH/AI   = Basic + UnpaidLeave(负)   [+ 勾选了 EPF/SOCSO/EIS 的额外项目]
///   I/J  EPF   = VLOOKUP(AG, EPF!$B$15:$F$415, 5/4)
///   L/M  SOCSO = VLOOKUP(AH, SOCSOEIS!$D$7:$J$71, 5/4)
///   O/P  EIS   = VLOOKUP(AI, SOCSOEIS!$D$7:$J$71, 7/6)
///   T  NET     = H - I - L - O - R - S   （雇主缴纳部分不扣减）
///
/// [extrasInBase]：需要计入 EPF/SOCSO/EIS 计费基数的额外收入项目，
/// 例如 {'itemA'}。默认为空 —— 与 Excel 的 AG/AH/AI 列完全一致。
PayrollResult compute(
  PayrollInput inp,
  RateBook book, {
  Set<String> extrasInBase = const {},
}) {
  final basic = round2(inp.basicSalary);
  final unpaid = round2(inp.unpaidLeave);
  final a = round2(inp.itemA);
  final b = round2(inp.itemB);
  final c = round2(inp.itemC);
  final pcb = round2(inp.pcb);
  final adv = round2(inp.advance);

  // TOTAL = Basic - UnpaidLeave + A + B + C
  final total = round2(basic - unpaid + a + b + c);

  // 计费基数 = Basic - UnpaidLeave (+ 额外项目)
  var base = round2(basic - unpaid);
  if (extrasInBase.contains('itemA')) base = round2(base + a);
  if (extrasInBase.contains('itemB')) base = round2(base + b);
  if (extrasInBase.contains('itemC')) base = round2(base + c);
  if (base < 0) base = 0.0;

  final epf = book.epfContribution(base);
  final socso = book.socsoContribution(base);
  final eis = book.eisContribution(base);

  final eeTotal = round2(epf[0] + socso[0] + eis[0]);
  final erTotal = round2(epf[1] + socso[1] + eis[1]);
  final contribTotal = round2(eeTotal + erTotal);
  final deductions = round2(eeTotal + pcb + adv);

  return PayrollResult(
    basicSalary: basic,
    unpaidLeave: unpaid,
    itemA: a,
    itemB: b,
    itemC: c,
    pcb: pcb,
    advance: adv,
    epfBase: base,
    socsoBase: base,
    eisBase: base,
    totalSalary: total,
    epfEmployee: epf[0],
    epfEmployer: epf[1],
    socsoEmployee: socso[0],
    socsoEmployer: socso[1],
    eisEmployee: eis[0],
    eisEmployer: eis[1],
    netSalary: round2(total - deductions),
    totalEmployeeContribution: eeTotal,
    totalEmployerContribution: erTotal,
    totalContribution: contribTotal,
    totalDeductions: deductions,
  );
}

/// 生成工资单前的必填校验。返回错误信息列表（空 = 通过）。
List<String> validatePayslip(
  String employeeName,
  int? year,
  int? month,
  PayrollInput inp,
) {
  final errors = <String>[];
  if (employeeName.trim().isEmpty) {
    errors.add('Please complete the required fields: Employee Name.');
  }
  if (year == null || month == null) {
    errors.add('Please complete the required fields: Payroll Month.');
  }
  if (round2(inp.basicSalary) <= 0) {
    errors.add('Please complete the required fields: Basic Salary.');
  }
  if (round2(inp.unpaidLeave) < 0) {
    errors.add('Unpaid Leave cannot be negative.');
  }
  return errors;
}
