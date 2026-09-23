
import 'package:flutter/material.dart';

import '../core/payslip_pdf.dart';
import '../main.dart';
import '../services.dart';
import '../widgets.dart';
import 'batch.dart';
import 'pdf_viewer.dart';
/// 历史记录 + 批量生成 / 批量发送工资单
class HistoryScreen extends StatefulWidget {
  final int refreshToken;
  final VoidCallback onChanged;

  const HistoryScreen(
      {super.key, required this.refreshToken, required this.onChanged});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final svc = appState.services;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final rows = await svc.db.listRuns();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _batch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BatchScreen()),
    );
    await _load();
    widget.onChanged();
  }

  /// 从**存档值**算净工资 —— 历史记录应当反映当初实际发出的数字，
  /// 不随之后修改设置而变。
  static double netOf(Map<String, dynamic> r) {
    double g(String k) => (r[k] as num?)?.toDouble() ?? 0;
    var net = g('basic_salary') - g('unpaid_leave')
        + g('item_a') + g('item_b') + g('item_c');
    for (final k in [
      'epf_employee', 'socso_employee', 'eis_employee', 'pcb', 'advance',
    ]) {
      net -= g(k);
    }
    return net;
  }

  /// 点开一条记录看完整明细
  Future<void> _detail(Map<String, dynamic> r) async {
    final empId = (r['employee_id'] as num?)?.toInt();
    final emp = empId == null ? null : await svc.db.getEmployee(empId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        double g(String k) => (r[k] as num?)?.toDouble() ?? 0;
        final m = (r['period_month'] as num).toInt();
        final y = (r['period_year'] as num).toInt();

        Widget line(String label, double v,
            {bool bold = false, bool negative = false, bool muted = false}) {
          return AmountRow(label,
              value: v, bold: bold, negative: negative, muted: muted);
        }

        final total = g('basic_salary') - g('unpaid_leave')
            + g('item_a') + g('item_b') + g('item_c');

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.95,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text('${r['employee_name'] ?? '(deleted)'}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${monthName(m)} $y'
                  '${'${r['employee_no'] ?? ''}'.isEmpty ? '' : '  ·  ${r['employee_no']}'}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant)),
              const Divider(height: 22),

              Text('Earnings',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              line('Basic Salary', g('basic_salary')),
              if (g('unpaid_leave') != 0)
                line('Less: Unpaid Leave', g('unpaid_leave'), negative: true),
              if (g('item_a') != 0) line('Item A', g('item_a')),
              if (g('item_b') != 0) line('Item B', g('item_b')),
              if (g('item_c') != 0) line('Item C', g('item_c')),
              const Divider(height: 18),
              line('Total Salary', total, bold: true),

              const SizedBox(height: 14),
              Text('Deductions (employee)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              line('EPF', g('epf_employee'), negative: true),
              line('SOCSO', g('socso_employee'), negative: true),
              line('EIS', g('eis_employee'), negative: true),
              line('Income Tax (PCB)', g('pcb'), negative: true),
              line('Advance to Staff', g('advance'), negative: true),
              const Divider(height: 18),
              line('NET SALARY', netOf(r), bold: true),

              const SizedBox(height: 14),
              Text('Employer contributions',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              line('EPF', g('epf_employer'), muted: true),
              line('SOCSO', g('socso_employer'), muted: true),
              line('EIS', g('eis_employer'), muted: true),

              const SizedBox(height: 14),
              Text('Contribution base: RM ${money(g('epf_base'))}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant)),

              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: emp == null
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _viewPdf(emp, m, y);
                          },
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('View PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Delete record',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _deleteRun(r);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              if (emp == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'This employee has been deleted, so no PDF can be made.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.error)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _viewPdf(Map<String, dynamic> emp, int month, int year) async {
    final (res, _) = await svc.ensureRun(emp, year, month);
    if (res == null) return;
    final (protectedBytes, name) = await svc.renderPayslip(emp, year, month, res);
    final (previewBytes, _) =
        await svc.renderPayslip(emp, year, month, res, withPassword: false);
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
          periodLabel: '${monthName(month)} $year',
          employeeId: (emp['id'] as num).toInt(),
          periodYear: year,
          periodMonth: month,
        ),
      ),
    );
  }

  Future<void> _deleteRun(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text('${r['employee_name']} — '
            '${monthName((r['period_month'] as num).toInt())} '
            '${r['period_year']}. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await svc.db.deleteRun((r['id'] as num).toInt());
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No payroll records yet',
        message: 'Generate a whole month in one go — every employee gets '
            'their own payslip.',
        action: FilledButton.icon(
          onPressed: _batch,
          icon: const Icon(Icons.playlist_add_check, size: 18),
          label: const Text('Generate & Send'),
        ),
      );
    }

    // 按「年-月」分组，越新的越靠前
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final key = '${r['period_year']}-${r['period_month']}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final pa = a.split('-').map(int.parse).toList();
        final pb = b.split('-').map(int.parse).toList();
        return pb[0] != pa[0] ? pb[0].compareTo(pa[0]) : pb[1].compareTo(pa[1]);
      });

    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          for (final k in keys) ...[
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Text(
                  '${monthName(int.parse(k.split('-')[1]))} '
                  '${k.split('-')[0]}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const Spacer(),
                Text('${groups[k]!.length} record(s)',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            for (final r in groups[k]!)
              ListTile(
                dense: true,
                onTap: () => _detail(r),
                title: Text('${r['employee_name'] ?? '(deleted)'}'),
                subtitle: Text('${r['employee_no'] ?? ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('RM ${money(netOf(r))}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Icon(Icons.chevron_right, size: 18),
                ]),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _batch,
        icon: const Icon(Icons.playlist_add_check),
        label: const Text('Generate & Send'),
      ),
    );
  }
}
