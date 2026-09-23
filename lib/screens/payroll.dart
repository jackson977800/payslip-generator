import 'package:flutter/material.dart';

import '../core/payroll.dart';
import '../core/payslip_pdf.dart';
import '../main.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pdf_viewer.dart';

/// Payroll 录入页：选员工与月份 → 填金额 → 实时算出 EPF/SOCSO/EIS/净工资
class PayrollScreen extends StatefulWidget {
  final int refreshToken;
  final VoidCallback onChanged;

  const PayrollScreen(
      {super.key, required this.refreshToken, required this.onChanged});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final svc = appState.services;

  List<Map<String, dynamic>> _emps = [];
  List<String> _earnLabels = [];
  List<bool> _earnEnabled = [];
  List<String> _dedLabels = [];

  int? _empId;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  /// 年份候选 —— 由 services.yearChoices() 给出（含数据库已有年份）
  List<int> _years = const [];

  final Map<String, TextEditingController> _inp = {
    'basic_salary': TextEditingController(),
    'unpaid_leave': TextEditingController(),
    'item_a': TextEditingController(),
    'item_b': TextEditingController(),
    'item_c': TextEditingController(),
    'pcb': TextEditingController(),
    'advance': TextEditingController(),
  };

  PayrollResult? _result;

  @override
  void initState() {
    super.initState();
    _boot();
    for (final c in _inp.values) {
      c.addListener(_recalc);
    }
  }

  @override
  void dispose() {
    for (final c in _inp.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PayrollScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _boot();
  }

  Future<void> _boot() async {
    final emps = await svc.db.listEmployees(onlyActive: true);
    final labels = await svc.earningsLabels();
    final enabled = await svc.earningsEnabled();
    final deds = await svc.deductionLabels();
    final years = await svc.yearChoices();
    if (!mounted) return;
    setState(() {
      _emps = emps;
      _earnLabels = labels;
      _earnEnabled = enabled;
      _dedLabels = deds;
      _years = years;
      if (!_years.contains(_year)) _year = DateTime.now().year;
      if (_empId == null && emps.isNotEmpty) {
        _empId = (emps.first['id'] as num).toInt();
      }
    });
    await _loadPeriod();
  }

  Map<String, dynamic>? get _employee {
    if (_empId == null) return null;
    for (final e in _emps) {
      if ((e['id'] as num).toInt() == _empId) return e;
    }
    return null;
  }

  /// 选中员工或切换月份时，载入该月的已存记录
  Future<void> _loadPeriod() async {
    final emp = _employee;
    if (emp == null) return;
    final run = await svc.db.getRun((emp['id'] as num).toInt(), _year, _month);
    if (!mounted) return;
    if (run == null) {
      _inp['basic_salary']!.text =
          ((emp['basic_salary'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
      for (final k in _inp.keys) {
        if (k != 'basic_salary') _inp[k]!.text = '';
      }
    } else {
      final p = Services.inputFromRun(run);
      _inp['basic_salary']!.text = p.basicSalary.toStringAsFixed(2);
      _inp['unpaid_leave']!.text =
          p.unpaidLeave == 0 ? '' : p.unpaidLeave.toStringAsFixed(2);
      _inp['item_a']!.text = p.itemA == 0 ? '' : p.itemA.toStringAsFixed(2);
      _inp['item_b']!.text = p.itemB == 0 ? '' : p.itemB.toStringAsFixed(2);
      _inp['item_c']!.text = p.itemC == 0 ? '' : p.itemC.toStringAsFixed(2);
      _inp['pcb']!.text = p.pcb == 0 ? '' : p.pcb.toStringAsFixed(2);
      _inp['advance']!.text = p.advance == 0 ? '' : p.advance.toStringAsFixed(2);
    }
    _recalc();
  }

  PayrollInput _input() {
    double v(String k) => double.tryParse(_inp[k]!.text.trim()) ?? 0;
    return PayrollInput(
      basicSalary: v('basic_salary'),
      unpaidLeave: v('unpaid_leave'),
      itemA: v('item_a'),
      itemB: v('item_b'),
      itemC: v('item_c'),
      pcb: v('pcb'),
      advance: v('advance'),
    );
  }

  Future<void> _recalc() async {
    final inp = _input();
    final r = await svc.computeFor(inp);
    if (mounted) setState(() => _result = r);
  }

  Future<void> _save() async {
    final emp = _employee;
    final r = _result;
    if (emp == null || r == null) return;
    final errs = validatePayslip('${emp['name']}', _year, _month, _input());
    if (errs.isNotEmpty) {
      _snack(errs.join('\n'));
      return;
    }
    await svc.saveRun(emp, _year, _month, _input(), r);
    _snack('Record saved for ${emp['name']} — ${monthName(_month)} $_year');
    widget.onChanged();
  }

  Future<void> _generate() async {
    final emp = _employee;
    final r = _result;
    if (emp == null || r == null) return;
    final errs = validatePayslip('${emp['name']}', _year, _month, _input());
    if (errs.isNotEmpty) {
      _snack(errs.join('\n'));
      return;
    }

    // 先生成并存档 —— 否则 History 里看不到这条记录，
    // 用户会以为「必须点 Save 才能进 History」。
    await svc.saveRun(emp, _year, _month, _input(), r);
    widget.onChanged();

    // 生成两份：无密码的用于预览，带密码的用于导出/发送。
    final (protectedBytes, name) =
        await svc.renderPayslip(emp, _year, _month, r);
    final (previewBytes, _) =
        await svc.renderPayslip(emp, _year, _month, r, withPassword: false);
    final pw = await svc.pdfPassword(emp);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          previewBytes: previewBytes,
          protectedBytes: protectedBytes,
          fileName: name,
          password: pw,
          employeeName: '${emp['name'] ?? ''}',
          emailTo: Services.mailRecipient(emp),
          periodLabel: '${monthName(_month)} $_year',
          employeeId: (emp['id'] as num).toInt(),
          periodYear: _year,
          periodMonth: _month,
        ),
      ),
    );
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    if (_emps.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No employees yet.\nAdd one in the Staff tab first.',
            textAlign: TextAlign.center),
      ));
    }
    final theme = Theme.of(context);
    final r = _result;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _empId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Employee',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: _emps
                  .map((e) => DropdownMenuItem(
                        value: (e['id'] as num).toInt(),
                        child: Text('${e['name']}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) async {
                setState(() => _empId = v);
                await _loadPeriod();
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(monthName(m)))
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _month = v);
                await _loadPeriod();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Year',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: _years
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _year = v);
                await _loadPeriod();
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings & Deductions',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _num(_earnLabels.isNotEmpty ? _earnLabels[0] : 'Basic Salary',
                    'basic_salary', required: true),
                _num(_earnLabels.length > 1
                        ? _earnLabels[1]
                        : 'Less: Unpaid Leave',
                    'unpaid_leave'),
                if (_earnEnabled.length > 2 && _earnEnabled[2])
                  _num(_earnLabels[2], 'item_a'),
                if (_earnEnabled.length > 3 && _earnEnabled[3])
                  _num(_earnLabels[3], 'item_b'),
                if (_earnEnabled.length > 4 && _earnEnabled[4])
                  _num(_earnLabels[4], 'item_c'),
                const Divider(),
                _num(_dedLabels.isNotEmpty ? _dedLabels[0] : 'Income Tax (PCB)',
                    'pcb'),
                _num(_dedLabels.length > 1
                        ? _dedLabels[1]
                        : 'Advance to Staff',
                    'advance'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (r != null)
          SectionCard(
            title: 'Auto calculation',
            hint: 'Updates as you type. Employer contributions are not '
                'deducted from the employee.',
            children: [
              AmountRow('Total Salary', value: r.totalSalary),
              AmountRow('Contribution base', value: r.epfBase, muted: true),
              const Divider(height: AppTheme.gapLg),
              AmountRow('EPF (Employee)', value: r.epfEmployee, negative: true),
              AmountRow('SOCSO (Employee)', value: r.socsoEmployee, negative: true),
              AmountRow('EIS (Employee)', value: r.eisEmployee, negative: true),
              AmountRow('Income Tax (PCB)', value: r.pcb, negative: true),
              AmountRow('Advance to Staff', value: r.advance, negative: true),
              const Divider(height: AppTheme.gapLg),
              AmountRow('Employer EPF', value: r.epfEmployer, muted: true),
              AmountRow('Employer SOCSO', value: r.socsoEmployer, muted: true),
              AmountRow('Employer EIS', value: r.eisEmployer, muted: true),
              const SizedBox(height: AppTheme.gapMd),
              // 净工资单独强调 —— 这是老板最关心的那个数
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapMd, vertical: AppTheme.gapMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Row(children: [
                  Text('NET SALARY',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      )),
                  const Spacer(),
                  MoneyText(r.netSalary,
                      showSymbol: true,
                      bold: true,
                      size: 17,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer),
                ]),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save only'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Save & Payslip'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Saving also adds this month to History. '
          '"Save & Payslip" opens the PDF, where you can email it straight '
          'to the employee.',
          style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _num(String label, String key, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _inp[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixText: 'RM ',
        ),
      ),
    );
  }
}
