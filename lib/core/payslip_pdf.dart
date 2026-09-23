import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'payroll.dart';
import 'pdf_security.dart';

/// 配色（取自参考 Excel，与桌面版一致）
const _dark = PdfColor.fromInt(0xFF1F2937);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _green = PdfColor.fromInt(0xFFDCE9DC);
const _gray = PdfColor.fromInt(0xFFF3F4F6);
const _line = PdfColor.fromInt(0xFF9CA3AF);
const _red = PdfColor.fromInt(0xFFB91C1C);

/// 数据行固定高度 —— 左右两张表并排时必须一致，否则行会错位
const _dataRowH = 15.0;
const _fillerRows = 8;

const _months = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(int m) => (m >= 1 && m <= 12) ? _months[m] : m.toString();

/// 金额格式化：千分位 + 两位小数。
/// 注意 -0.0 要归一为 0.00，避免工资单上出现 "-0.00"。
String money(dynamic v, {String symbol = ''}) {
  var n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  if (n == 0) n = 0.0;
  final s = NumberFormat('#,##0.00').format(n);
  return symbol.isEmpty ? s : '$symbol $s';
}

String safeName(String s) => s
    .trim()
    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
    .replaceAll(RegExp(r'\s+'), '_');

String pdfFileName(String employeeName, int month, int year) =>
    'Payslip_${safeName(employeeName)}_${monthName(month)}_$year.pdf';

String zipFileName(int month, int year) =>
    'Payslips_${monthName(month)}_$year.zip';

/// 一张工资单所需的全部数据
class PayslipData {
  final Map<String, dynamic> company;
  final Map<String, dynamic> employee;
  final int year;
  final int month;
  final PayrollResult result;

  /// (标签, 金额) —— 收入侧
  final List<List<dynamic>> earnings;

  /// (标签, 雇员, 雇主) —— 扣款侧
  final List<List<dynamic>> deductions;

  final Map<String, dynamic> options;

  PayslipData({
    required this.company,
    required this.employee,
    required this.year,
    required this.month,
    required this.result,
    required this.earnings,
    required this.deductions,
    required this.options,
  });
}

/// 生成单页 A4 工资单 PDF。
///
/// [password] 非空时用标准 PDF 加密（RC4 128 位）保护文件：
/// 允许打印，禁止复制内容与修改 —— 与桌面版行为一致。
///
/// **字体限制**：用的是 PDF 内置的 Helvetica / Times（Type1 + WinAnsi），
/// 只支持 ASCII / Latin-1。非 ASCII 字符（如中文）会被**静默丢弃** ——
/// 实测 `陈大文 Tan Tai Wen` 会渲染成 `Tan Tai Wen`。
/// 当前业务不使用中文姓名，因此不引入体积约 10MB 的 CJK 字体；
/// 若将来需要，替换成嵌入 TTF 的方式即可。
Future<Uint8List> buildPayslipPdf(PayslipData data, {String? password}) async {
  final r = data.result;
  final comp = data.company;
  final emp = data.employee;
  final opt = data.options;

  final doc = pw.Document(
    title: 'Payslip ${emp['name'] ?? ''} ${monthName(data.month)} ${data.year}',
    author: (comp['company_name'] ?? '').toString(),
    subject: 'Salary Slip',
    creator: 'Payslip Generator',
  );

  final tb = pw.Font.timesBold();
  final h = pw.Font.helvetica();
  final hb = pw.Font.helveticaBold();

  pw.TextStyle st({pw.Font? font, double size = 8.5, PdfColor color = _dark}) =>
      pw.TextStyle(font: font ?? h, fontSize: size, color: color);

  pw.Widget txt(String s,
          {pw.Font? font,
          double size = 8.5,
          PdfColor color = _dark,
          pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Text(s, style: st(font: font, size: size, color: color), textAlign: align);

  // ---------------- 员工资料 ----------------
  final infoRows = <List<String>>[
    ['Name:', '${emp['name'] ?? ''}', 'Job Title:', '${emp['job_title'] ?? ''}'],
    ['NRIC No.:', '${emp['nric'] ?? ''}', 'Department:', '${emp['department'] ?? ''}'],
    ['EPF No.:', '${emp['epf_no'] ?? ''}', 'Employee No.:',
     '${emp['employee_no'] ?? ''}'],
  ];
  if ('${emp['socso_no'] ?? ''}'.isNotEmpty || '${emp['eis_no'] ?? ''}'.isNotEmpty) {
    infoRows.add(['SOCSO No.:', '${emp['socso_no'] ?? ''}', 'EIS No.:',
                  '${emp['eis_no'] ?? ''}']);
  }

  // ---------------- 收入 / 扣款两张并排表 ----------------
  final earnRows = data.earnings;
  final dedRows = data.deductions;
  final nData = [earnRows.length, dedRows.length, 1].reduce((a, b) => a > b ? a : b);

  pw.TableRow headRow(List<pw.Widget> cells) =>
      pw.TableRow(decoration: const pw.BoxDecoration(color: _green),
          children: cells);

  pw.Widget pad(pw.Widget c, {bool right = false}) => pw.Container(
        height: _dataRowH,
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        child: c,
      );

  // ---- 收入表 ----
  final earnChildren = <pw.TableRow>[
    headRow([
      pad(txt('No.', font: hb, align: pw.TextAlign.center)),
      pad(txt('Descriptions', font: hb)),
      pad(txt('Total', font: hb), right: true),
    ]),
  ];
  for (var i = 0; i < nData; i++) {
    final e = i < earnRows.length ? earnRows[i] : null;
    final v = e == null ? 0.0 : (e[1] as num).toDouble();
    earnChildren.add(pw.TableRow(
      decoration: e == null ? const pw.BoxDecoration(color: _gray) : null,
      children: [
        pad(txt(e == null ? '' : '${i + 1}', align: pw.TextAlign.center)),
        pad(txt(e == null ? '' : '${e[0]}')),
        pad(txt(e == null ? '' : money(v), color: v < 0 ? _red : _dark),
            right: true),
      ],
    ));
  }
  for (var i = 0; i < _fillerRows; i++) {
    earnChildren.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: _gray),
      children: [
        pad(txt('', size: 8)),
        pad(txt('', size: 8)),
        pad(txt('', size: 8)),
      ],
    ));
  }
  // 合计行。
  // 注意：pdf 包不支持跨列，标签必须放在**最宽的描述列**里，
  // 放最窄的 No. 列会被截断成 "Sub-"（真机上已复现）。
  earnChildren.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: _green),
    children: [
      pad(txt('', size: 8)),
      pad(txt('Sub-Total', font: hb, size: 9)),
      pad(txt(money(r.totalSalary), font: hb, size: 9), right: true),
    ],
  ));

  // ---- 扣款表 ----
  final dedChildren = <pw.TableRow>[
    headRow([
      pad(txt('No.', font: hb, align: pw.TextAlign.center)),
      pad(txt('Descriptions', font: hb)),
      pad(txt("Emp'yee", font: hb), right: true),
      pad(txt("Emp'yer", font: hb), right: true),
    ]),
  ];
  for (var i = 0; i < nData; i++) {
    final d = i < dedRows.length ? dedRows[i] : null;
    dedChildren.add(pw.TableRow(
      decoration: d == null ? const pw.BoxDecoration(color: _gray) : null,
      children: [
        pad(txt(d == null ? '' : '${i + 1}', align: pw.TextAlign.center)),
        pad(txt(d == null ? '' : '${d[0]}')),
        pad(txt(d == null ? '' : money(d[1]), color: d == null ? _muted : _dark),
            right: true),
        pad(txt(d == null ? '' : money(d[2]), color: d == null ? _muted : _dark),
            right: true),
      ],
    ));
  }
  for (var i = 0; i < _fillerRows; i++) {
    dedChildren.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: _gray),
      children: [
        pad(txt('', size: 8)),
        pad(txt('', size: 8)),
        pad(txt('', size: 8)),
        pad(txt('', size: 8)),
      ],
    ));
  }
  dedChildren.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: _green),
    children: [
      pad(txt('', size: 8)),
      pad(txt('Total Deductions', font: hb, size: 9)),
      pad(txt(money(r.totalEmployeeContribution), font: hb, size: 9),
          right: true),
      pad(txt('', size: 8)),
    ],
  ));

  final border = pw.TableBorder.all(color: _line, width: 0.4);

  final mainTables = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 4,
        child: pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(1.0),
          },
          children: earnChildren,
        ),
      ),
      pw.Expanded(
        flex: 5,
        child: pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(1.0),
          },
          children: dedChildren,
        ),
      ),
    ],
  );

  // ---------------- 组装页面 ----------------
  final extra = _companyExtra(comp, opt);

  final content = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      txt('${comp['company_name'] ?? 'Company Name'}',
          font: tb, size: 16, align: pw.TextAlign.center),
      if ('${comp['company_address'] ?? ''}'.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: txt('${comp['company_address']}', size: 9,
              align: pw.TextAlign.center),
        ),
      if (extra.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: txt(extra, size: 8.5, color: _muted,
              align: pw.TextAlign.center),
        ),
      pw.SizedBox(height: 10),

      pw.Row(children: [
        pw.Expanded(
          child: txt('Salary Slip for', font: tb, size: 12,
              align: pw.TextAlign.right),
        ),
        pw.SizedBox(width: 6),
        pw.Container(
          width: 90,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _dark)),
          child: txt(monthName(data.month), font: tb, size: 11,
              align: pw.TextAlign.center),
        ),
        pw.SizedBox(width: 4),
        pw.Container(
          width: 64,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _dark)),
          child: txt('${data.year}', font: tb, size: 11,
              align: pw.TextAlign.center),
        ),
      ]),
      pw.SizedBox(height: 9),

      pw.Table(
        border: null,
        columnWidths: const {
          0: pw.FixedColumnWidth(52),
          1: pw.FlexColumnWidth(3),
          2: pw.FixedColumnWidth(74),
          3: pw.FlexColumnWidth(3),
        },
        children: infoRows
            .map((row) => pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 1.5),
                      child: txt(row[0], size: 8.5, color: _muted)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 1.5),
                      child: txt(row[1].isEmpty ? '-' : row[1], font: hb, size: 9)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 1.5),
                      child: txt(row[2], size: 8.5, color: _muted)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 1.5),
                      child: txt(row[3].isEmpty ? '-' : row[3], font: hb, size: 9)),
                ]))
            .toList(),
      ),
      pw.SizedBox(height: 10),

      mainTables,
      pw.SizedBox(height: 8),

      pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _dark, width: 0.8), color: _green),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: pw.Row(children: [
          txt('NET SALARY', font: hb, size: 11),
          pw.Spacer(),
          txt(money(r.netSalary, symbol: 'RM'), font: hb, size: 13),
        ]),
      ),
      pw.SizedBox(height: 8),

      if ('${opt['pdf_show_contribution_summary'] ?? '1'}' == '1')
        _contributionTable(r, txt, hb, border),
    ],
  );

  // ---- 加密（可选）----
  final pw_ = password?.trim() ?? '';
  if (pw_.isNotEmpty) {
    doc.document.encryption =
        StandardSecurityHandler(doc.document, userPassword: pw_);
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(14 * PdfPageFormat.mm,
        12 * PdfPageFormat.mm, 14 * PdfPageFormat.mm, 12 * PdfPageFormat.mm),
    build: (_) => [content],
    footer: (_) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: txt(
          'Generated by Payslip Generator  ·  '
          '${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
          size: 7.5,
          color: _muted),
    ),
  ));

  return doc.save();
}

String _companyExtra(Map<String, dynamic> comp, Map<String, dynamic> opt) {
  final parts = <String>[];
  if ('${opt['pdf_show_company_reg'] ?? '1'}' == '1' &&
      '${comp['company_reg_no'] ?? ''}'.isNotEmpty) {
    parts.add('Reg. No.: ${comp['company_reg_no']}');
  }
  if ('${comp['company_phone'] ?? ''}'.isNotEmpty) {
    parts.add('Tel: ${comp['company_phone']}');
  }
  if ('${comp['company_email'] ?? ''}'.isNotEmpty) {
    parts.add('Email: ${comp['company_email']}');
  }
  return parts.join('   |   ');
}

pw.Widget _contributionTable(
  PayrollResult r,
  pw.Widget Function(String,
      {pw.Font? font, double size, PdfColor color, pw.TextAlign align}) txt,
  pw.Font hb,
  pw.TableBorder border,
) {
  pw.Widget cell(pw.Widget c, {bool right = false}) => pw.Container(
        height: _dataRowH,
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        child: c,
      );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: _green),
      children: [
        cell(txt('CONTRIBUTIONS (RM)', font: hb)),
        cell(txt("Emp'yee", font: hb), right: true),
        cell(txt("Emp'yer", font: hb), right: true),
        cell(txt('Total', font: hb), right: true),
      ],
    ),
  ];

  for (final item in <List<dynamic>>[
    ['EPF', r.epfEmployee, r.epfEmployer],
    ['SOCSO', r.socsoEmployee, r.socsoEmployer],
    ['EIS', r.eisEmployee, r.eisEmployer],
  ]) {
    final ee = item[1] as double;
    final er = item[2] as double;
    rows.add(pw.TableRow(children: [
      cell(txt('${item[0]}')),
      cell(txt(money(ee)), right: true),
      cell(txt(money(er)), right: true),
      cell(txt(money(ee + er)), right: true),
    ]));
  }

  rows.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: _green),
    children: [
      cell(txt('Total', font: hb)),
      cell(txt(money(r.totalEmployeeContribution), font: hb), right: true),
      cell(txt(money(r.totalEmployerContribution), font: hb), right: true),
      cell(txt(money(r.totalContribution), font: hb), right: true),
    ],
  ));

  return pw.Table(
    border: border,
    columnWidths: const {
      0: pw.FlexColumnWidth(2.4),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(1.2),
      3: pw.FlexColumnWidth(1.4),
    },
    children: rows,
  );
}
