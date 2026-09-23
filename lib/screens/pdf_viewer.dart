import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/mail.dart';
import '../main.dart';

/// 工资单 PDF 预览与导出。
///
/// 关键设计：
///  1. **预览用无密码副本，分享/导出用带密码副本**。
///     只生成带密码那一份的话，老板自己也打不开自己刚生成的工资单。
///  2. `PdfPreview` 自带的分享按钮固定用 `document.pdf` 这个名字，
///     所以关掉它，改用自己的按钮并显式传文件名。
///  3. 可直接把这份 PDF 邮件发给员工 —— 不必绕回批量页。
class PdfViewerScreen extends StatefulWidget {
  /// 无密码，用于应用内查看
  final List<int> previewBytes;

  /// 带密码，用于分享/邮件发给员工
  final List<int> protectedBytes;

  /// 形如 Payslip_jackson_August_2026.pdf
  final String fileName;

  /// 员工端需要的密码；空字符串表示未启用密码
  final String password;

  final String employeeName;

  /// 员工邮箱；为空则隐藏邮件按钮
  final String emailTo;

  /// 形如 "August 2026"，用于邮件主题
  final String periodLabel;

  /// 用于邮件日志关联
  final int? employeeId;
  final int? periodYear;
  final int? periodMonth;

  const PdfViewerScreen({
    super.key,
    required this.previewBytes,
    required this.protectedBytes,
    required this.fileName,
    required this.password,
    required this.employeeName,
    this.emailTo = '',
    this.periodLabel = '',
    this.employeeId,
    this.periodYear,
    this.periodMonth,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _sending = false;

  bool get _hasPw => widget.password.trim().isNotEmpty;
  bool get _canEmail => isValidEmail(widget.emailTo);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: _hasPw ? 'Share protected PDF' : 'Share PDF',
            onPressed: () => _share(widget.protectedBytes),
          ),
        ],
      ),
      body: Column(children: [
        // 密码说明条 —— 让老板知道员工会收到什么、用什么密码打开
        Container(
          width: double.infinity,
          color: _hasPw
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            Icon(_hasPw ? Icons.lock_outline : Icons.lock_open,
                size: 18,
                color: _hasPw
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: _hasPw
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The preview below is unprotected so you can read it.',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.employeeName} gets this file protected '
                          'with password:  ${widget.password}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'PDF password is off — the file is sent unprotected.',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
            ),
          ]),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) async => Uint8List.fromList(widget.previewBytes),
            allowSharing: false,
            allowPrinting: true,
            pdfFileName: widget.fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_canEmail)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _emailToEmployee,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline, size: 18),
                  label: Text(_sending
                      ? 'Sending…'
                      : 'Email to ${widget.emailTo}'),
                ),
              ),
            if (_canEmail) const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _share(widget.protectedBytes),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(_hasPw ? 'Share protected' : 'Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _share(widget.previewBytes),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Unprotected'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _share(List<int> bytes) async {
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: widget.fileName,
    );
  }

  /// 直接把这份工资单邮件发给员工。
  /// 发的是**带密码**那份，与批量发送行为一致。
  Future<void> _emailToEmployee() async {
    final svc = appState.services;
    final cfg = await svc.mailConfig(await appState.smtpPassword());
    final errs = cfg.validate();
    if (errs.isNotEmpty) {
      _snack('Email is not configured:\n${errs.join('\n')}');
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send this payslip?'),
        content: Text('To: ${widget.emailTo}'
            '\nSubject: ${widget.periodLabel.isEmpty ? widget.fileName : widget.periodLabel}'
            '${_hasPw ? '\n\nProtected with password ${widget.password}' : '\n\nUnprotected PDF'}'
            '\n\nA sent email cannot be recalled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sending = true);

    // 写一份临时文件作为附件
    final dir = await appDir();
    final f = File('${dir.path}/${widget.fileName}');
    await f.writeAsBytes(widget.protectedBytes);

    final subject = widget.periodLabel.isEmpty
        ? widget.fileName
        : 'Payslip ${widget.periodLabel} - ${widget.employeeName}';
    final body = StringBuffer()
      ..writeln('Dear ${widget.employeeName},')
      ..writeln()
      ..writeln('Please find attached your payslip for '
          '${widget.periodLabel.isEmpty ? '' : widget.periodLabel}.')
      ..writeln();
    if (_hasPw) {
      body
        ..writeln('The attached file is password-protected. '
            'Your password is: ${widget.password}')
        ..writeln();
    }
    body
      ..writeln('If you have any questions, please contact us.')
      ..writeln()
      ..writeln('Best regards,');

    final err = await sendMail(
      cfg: cfg,
      toAddr: widget.emailTo,
      subject: subject,
      body: body.toString(),
      attachmentPath: f.path,
    );

    await svc.db.logMail({
      if (widget.employeeId != null) 'employee_id': widget.employeeId,
      'employee_name': widget.employeeName,
      if (widget.periodYear != null) 'period_year': widget.periodYear,
      if (widget.periodMonth != null) 'period_month': widget.periodMonth,
      'to_addr': widget.emailTo,
      'subject': subject,
      'status': err == null ? 'Sent' : 'Failed',
      'error': err ?? '',
    });

    if (!mounted) return;
    setState(() => _sending = false);
    _snack(err == null
        ? 'Payslip sent to ${widget.emailTo}'
        : 'Could not send: $err');
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 4)));
  }
}
