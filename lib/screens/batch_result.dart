import 'package:flutter/material.dart';

import '../core/payslip_pdf.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pdf_viewer.dart';

/// 批量生成后的结果列表。
///
/// 为什么需要这个页面：批量跑完只弹一句「已保存到 <路径>」在 Android 上
/// 等于没说 —— 应用私有目录用文件管理器根本进不去，用户拿不到文件、
/// 也就没法发给员工。
///
/// 这里把每份工资单列出来，点一下就能看 PDF / 邮件发送 / 分享。
class BatchResultItem {
  final Map<String, dynamic> employee;
  final int year;
  final int month;
  final String fileName;
  final List<int> previewBytes;
  final List<int> protectedBytes;
  final String password;
  final double netSalary;
  final String emailTo;

  /// sent | failed | generated
  final String status;
  final String error;

  const BatchResultItem({
    required this.employee,
    required this.year,
    required this.month,
    required this.fileName,
    required this.previewBytes,
    required this.protectedBytes,
    required this.password,
    required this.netSalary,
    required this.emailTo,
    required this.status,
    this.error = '',
  });
}

class BatchResultScreen extends StatefulWidget {
  final List<BatchResultItem> items;
  final int year;
  final int month;

  const BatchResultScreen({
    super.key,
    required this.items,
    required this.year,
    required this.month,
  });

  @override
  State<BatchResultScreen> createState() => _BatchResultScreenState();
}

class _BatchResultScreenState extends State<BatchResultScreen> {
  /// 本地状态：在结果页里发过邮件的，直接标记为已发送
  late final List<String> _status =
      widget.items.map((e) => e.status).toList();

  int get _sentCount => _status.where((s) => s == 'sent').length;
  int get _failedCount => _status.where((s) => s == 'failed').length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${monthName(widget.month)} ${widget.year}'),
      ),
      body: Column(children: [
        // 汇总条
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text(
            '$n payslip(s) generated'
            '${_sentCount > 0 ? '  ·  $_sentCount emailed' : ''}'
            '${_failedCount > 0 ? '  ·  $_failedCount failed' : ''}'
            '\nTap any row to view, email or share that payslip.',
            style: TextStyle(
                fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              final st = _status[i];
              final email = it.emailTo;

              late final Tone tone;
              late final IconData icon;
              late final String label;
              switch (st) {
                case 'sent':
                  icon = Icons.mark_email_read_outlined;
                  tone = Tone.ok;
                  label = 'Emailed to $email';
                  break;
                case 'failed':
                  icon = Icons.error_outline;
                  tone = Tone.bad;
                  label = it.error.isEmpty ? 'Send failed' : it.error;
                  break;
                default:
                  icon = Icons.picture_as_pdf_outlined;
                  tone = email.isEmpty ? Tone.bad : Tone.warn;
                  label = email.isEmpty ? 'No email address' : 'Not sent yet';
              }
              final color = switch (tone) {
                Tone.ok => AppTheme.ok(context),
                Tone.warn => AppTheme.warn(context),
                Tone.bad => AppTheme.neg(context),
                Tone.neutral => theme.colorScheme.onSurfaceVariant,
              };

              return ListTile(
                onTap: () => _open(i),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapMd, vertical: AppTheme.gapXs),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Icon(icon, size: 19, color: color),
                ),
                title: Text('${it.employee['name'] ?? ''}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    MoneyText(it.netSalary,
                        showSymbol: true, bold: true, size: 13.5),
                    const SizedBox(height: 5),
                    StatusChip(label: label, tone: tone, icon: icon, dense: true),
                  ],
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right, size: 20),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(int i) async {
    final it = widget.items[i];
    final before = _status[i];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          previewBytes: it.previewBytes,
          protectedBytes: it.protectedBytes,
          fileName: it.fileName,
          password: it.password,
          employeeName: '${it.employee['name'] ?? ''}',
          emailTo: it.emailTo,
          periodLabel: '${monthName(it.month)} ${it.year}',
          employeeId: (it.employee['id'] as num?)?.toInt(),
          periodYear: it.year,
          periodMonth: it.month,
        ),
      ),
    );
    // 从预览页回来时，若之前没发过而现在发过了，刷新状态
    if (!mounted) return;
    final svc = appState.services;
    final logs = await svc.db.lastMailStatus(it.year, it.month);
    final rec = logs[(it.employee['id'] as num).toInt()];
    final now = rec != null && rec['status'] == 'Sent'
        ? 'sent'
        : (rec != null && rec['status'] == 'Failed' ? 'failed' : before);
    if (mounted && now != _status[i]) setState(() => _status[i] = now);
  }
}
