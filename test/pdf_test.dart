// 生成工资单 PDF 并落盘，供外部工具独立验证（尤其是加密是否真的生效）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payslip_app/core/payroll.dart';
import 'package:payslip_app/core/payslip_pdf.dart';
import 'package:payslip_app/core/rates.dart';

List<dynamic> jsonList(String s) => jsonDecode(s) as List<dynamic>;

bool _hasEncrypt(List<int> bytes) =>
    latin1.decode(bytes, allowInvalid: true).contains('/Encrypt');

void main() {
  test('生成工资单 PDF（明文 + 加密）', () async {
    final epf = File('assets/epf_table.json').readAsStringSync();
    final socso = File('assets/socso_eis_table.json').readAsStringSync();
    final book = RateBook.fromRows(jsonList(epf), jsonList(socso));

    final r = compute(const PayrollInput(basicSalary: 1700), book);

    final data = PayslipData(
      company: {
        'company_name': 'Be Happy Staff Enterprise',
        'company_address': '12, Jalan Besar, 50000 Kuala Lumpur',
        'company_reg_no': '202301234567',
        'company_phone': '03-1234 5678',
        'company_email': 'hr@behappy.com.my',
      },
      employee: {
        'name': 'Jackson Chang Cheun Seng',
        'nric': '900101-14-1234',
        'employee_no': 'A01',
        'job_title': 'Hairdresser',
        'department': 'Salon',
        'epf_no': 'EPF123456',
        'bank_name': 'MAYBANK',
        'bank_account': '1234567890',
      },
      year: 2026,
      month: 9,
      result: r,
      earnings: const [
        ['Basic Salary / Gaji Pokok', 1700.00],
        ['Less: Unpaid Leave / (Cuti Tanpa Gaji)', -0.00],
      ],
      deductions: const [
        ['EPF (Employee)', 187.00, 221.00],
        ['SOCSO (Employee)', 20.60, 28.85],
        ['EIS (Employee)', 3.30, 3.30],
        ['Income Tax (PCB)', 0.00, 0.00],
      ],
      options: const {
        'pdf_show_contribution_summary': '1',
        'pdf_show_company_reg': '1',
      },
    );

    final outDir = Directory('build/pdf_out')..createSync(recursive: true);

    final plain = await buildPayslipPdf(data);
    File('${outDir.path}/plain.pdf').writeAsBytesSync(plain);
    expect(plain.length, greaterThan(3000));
    expect(String.fromCharCodes(plain.take(5)), '%PDF-');

    final enc = await buildPayslipPdf(data, password: '141234');
    File('${outDir.path}/enc.pdf').writeAsBytesSync(enc);
    expect(enc.length, greaterThan(3000));

    expect(_hasEncrypt(plain), isFalse, reason: '明文件不应含 /Encrypt');
    expect(_hasEncrypt(enc), isTrue, reason: '加密件必须含 /Encrypt');

    expect(pdfFileName('Jackson Chang Cheun Seng', 9, 2026),
        'Payslip_Jackson_Chang_Cheun_Seng_September_2026.pdf');
    // -0.0 必须显示为 0.00
    expect(money(-0.0), '0.00');
    expect(money(-150), '-150.00');
    expect(money(1489.1, symbol: 'RM'), 'RM 1,489.10');
    expect(monthName(9), 'September');
  });
}
