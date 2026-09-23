import 'dart:io';

import 'package:flutter/material.dart';

import '../core/mail.dart';
import '../core/payroll.dart';
import '../core/payslip_pdf.dart';
import '../main.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'batch_result.dart';

/// 批量生成 / 批量发送工资单。
///
/// 从两个地方进入：
///  - 首页的「一键生成下月工资」（预置下个月 + 全员勾选 + 预开邮件）
///  - History 页的浮动按钮（默认当前月，可自由调整）
class BatchScreen extends StatefulWidget {
  final int? initialYear;
  final int? initialMonth;

  /// 打开时是否默认勾选「同时发邮件」
  final bool initialAlsoEmail;

  const BatchScreen({
    super.key,
    this.initialYear,
    this.initialMonth,
    this.initialAlsoEmail = false,
  });

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final svc = appState.services;
  late int _year;
  late int _month;

  List<Map<String, dynamic>> _emps = [];
  final Map<int, bool> _checked = {};
  final Map<int, String> _status = {};
  final Map<int, PayrollResult?> _results = {};
  late bool _alsoEmail;
  bool _busy = false;
  String _progress = '';
  int _done = 0;
  int _total = 0;
  List<String> _log = [];
  List<int> _years = const [];

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? DateTime.now().year;
    _month = widget.initialMonth ?? DateTime.now().month;
    _alsoEmail = widget.initialAlsoEmail;
    _boot();
  }

  Future<void> _boot() async {
    final years = await svc.yearChoices();
    if (!mounted) return;
    setState(() {
      _years = years;
      if (!_years.contains(_year)) _year = DateTime.now().year;
    });
    await _reload();
  }

  Future<void> _reload() async {
    final emps = await svc.db.listEmployees();
    final logs = await svc.db.lastMailStatus(_year, _month);
    final checked = <int, bool>{};
    final status = <int, String>{};
    final results = <int, PayrollResult?>{};
    for (final e in emps) {
      final id = (e['id'] as num).toInt();
      final (_, res, st) = await svc.monthStatus(e, _year, _month);
      results[id] = res;
      final prev = logs[id];
      final sent = prev != null && prev['status'] == 'Sent';
      final canSend = res != null && st != Services.statusMissing;
      // 已发过的默认不勾，避免重复发送
      checked[id] = canSend && !sent;
      status[id] = sent
          ? 'Sent ${'${prev['sent_at']}'.substring(0, 10)}'
          : (st == Services.statusReady
              ? 'Ready'
              : st == Services.statusDefault
                  ? 'Basic salary only'
                  : 'Missing basic salary');
    }
    if (!mounted) return;
    setState(() {
      _emps = emps;
      _checked
        ..clear()
        ..addAll(checked);
      _status
        ..clear()
        ..addAll(status);
      _results
        ..clear()
        ..addAll(results);
    });
  }

  int get _selected =>
      _emps.where((e) => _checked[(e['id'] as num).toInt()] == true).length;

  int get _selectable => _emps
      .where((e) => _status[(e['id'] as num).toInt()] != 'Missing basic salary')
      .length;

  Future<void> _run() async {
    final chosen = _emps
        .where((e) => _checked[(e['id'] as num).toInt()] == true)
        .toList();
    if (chosen.isEmpty) return;

    final withMail = _alsoEmail;
    if (withMail) {
      final cfg = await svc.mailConfig(await appState.smtpPassword());
      final errs = cfg.validate();
      if (errs.isNotEmpty) {
        _snack('Email is not configured:\n${errs.join('\n')}');
        return;
      }
      final missing = chosen
          .where((e) => !isValidEmail(Services.mailRecipient(e)))
          .length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Generate and email?'),
          content: Text('${chosen.length} payslip(s) will be generated and '
              'emailed for ${monthName(_month)} $_year.'
              '${missing > 0 ? '\n\n$missing of them have no valid email '
                  'address and will be skipped.' : ''}'
              '\n\nSent emails cannot be recalled.'),
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
    }

    setState(() {
      _busy = true;
      _total = chosen.length;
      _done = 0;
      _log = [];
      _progress = 'Preparing…';
    });

    final dir = await appDir();
    final items = <BatchResultItem>[];

    for (var i = 0; i < chosen.length; i++) {
      final emp = chosen[i];
      final id = (emp['id'] as num).toInt();
      if (!mounted) return;
      setState(() =>
          _progress = 'Generating ${emp['name']}…   (${i + 1} of ${chosen.length})');
      await Future.delayed(const Duration(milliseconds: 1));

      final (res, _) = await svc.ensureRun(emp, _year, _month);
      if (res == null) continue;

      // 两份都留着：无密码的给结果页预览，带密码的给分享/发送
      final (protectedBytes, name) =
          await svc.renderPayslip(emp, _year, _month, res);
      final (previewBytes, _) =
          await svc.renderPayslip(emp, _year, _month, res, withPassword: false);
      final pw = await svc.pdfPassword(emp);
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(protectedBytes);

      final to = Services.mailRecipient(emp);
      var status = 'generated';
      var error = '';

      if (withMail) {
        if (!mounted) return;
        setState(() =>
            _progress = 'Emailing ${emp['name']}…   (${i + 1} of ${chosen.length})');
        if (!isValidEmail(to)) {
          status = 'failed';
          error = 'No valid email address';
          _log.add('${emp['name']}: no valid email address');
        } else {
          final cfg = await svc.mailConfig(await appState.smtpPassword());
          final subject = await svc.mailSubject(emp, _year, _month, res);
          final err = await sendMail(
            cfg: cfg,
            toAddr: to,
            subject: subject,
            body: await svc.mailBody(emp, _year, _month, res),
            attachmentPath: f.path,
          );
          if (err == null) {
            status = 'sent';
            await svc.db.logMail({
              'employee_id': id,
              'employee_name': '${emp['name']}',
              'period_year': _year,
              'period_month': _month,
              'to_addr': to,
              'subject': subject,
              'status': 'Sent',
              'error': '',
            });
          } else {
            status = 'failed';
            error = err;
            _log.add('${emp['name']}: $err');
            await svc.db.logMail({
              'employee_id': id,
              'employee_name': '${emp['name']}',
              'period_year': _year,
              'period_month': _month,
              'to_addr': to,
              'subject': '',
              'status': 'Failed',
              'error': err,
            });
          }
        }
      }

      items.add(BatchResultItem(
        employee: emp,
        year: _year,
        month: _month,
        fileName: name,
        previewBytes: previewBytes,
        protectedBytes: protectedBytes,
        password: pw,
        netSalary: res.netSalary,
        emailTo: to,
        status: status,
        error: error,
      ));

      if (!mounted) return;
      setState(() => _done = i + 1);

      // 连接/认证类错误会波及所有人，立即中止
      if (status == 'failed' &&
          error.toLowerCase().contains('auth') ||
          error.toLowerCase().contains('refused')) {
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = '';
    });
    await _reload();
    if (!mounted) return;

    // 直接进结果列表 —— 只弹一句「已保存到 <路径>」在 Android 上没用，
    // 应用私有目录用文件管理器进不去，用户拿不到文件也就发不出去。
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchResultScreen(
          items: items,
          year: _year,
          month: _month,
        ),
      ),
    );
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _setAll(bool v) {
    setState(() {
      for (final e in _emps) {
        final id = (e['id'] as num).toInt();
        if (_status[id] != 'Missing basic salary') _checked[id] = v;
      }
    });
  }

  void _jumpToNextMonth() {
    final (y, m) = Services.nextPeriod(_year, _month);
    setState(() {
      _year = y;
      _month = m;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Generate & Send')),
      body: Column(children: [
        // ---- 期间选择 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
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
                onChanged: _busy
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() => _month = v);
                        await _reload();
                      },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 108,
              child: DropdownButtonFormField<int>(
                initialValue: _year,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Year',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: (_years.isEmpty ? [DateTime.now().year] : _years)
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() => _year = v);
                        await _reload();
                      },
              ),
            ),
          ]),
        ),

        // ---- 快捷操作 ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            TextButton.icon(
              onPressed: _busy ? null : _jumpToNextMonth,
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('Next month'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy || _selected == _selectable
                  ? null
                  : () => _setAll(true),
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: _busy || _selected == 0 ? null : () => _setAll(false),
              child: const Text('None'),
            ),
          ]),
        ),

        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(children: [
              LinearProgressIndicator(
                  value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 6),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_progress, style: theme.textTheme.bodySmall)),
            ]),
          ),

        // ---- 员工列表 ----
        Expanded(
          child: _emps.isEmpty
              ? const Center(child: Text('No employees yet.'))
              : ListView.builder(
                  itemCount: _emps.length,
                  itemBuilder: (_, i) {
                    final e = _emps[i];
                    final id = (e['id'] as num).toInt();
                    final st = _status[id] ?? '';
                    final res = _results[id];
                    final canSend = st != 'Missing basic salary';
                    final email = Services.mailRecipient(e);
                    final sent = st.startsWith('Sent');
                    final tone = sent
                        ? Tone.ok
                        : (canSend ? Tone.warn : Tone.bad);
                    return CheckboxListTile(
                      dense: true,
                      value: _checked[id] ?? false,
                      onChanged: _busy || !canSend
                          ? null
                          : (v) => setState(() => _checked[id] = v == true),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gapSm),
                      title: Text('${e['name']}',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Row(children: [
                            if (res != null)
                              MoneyText(res.netSalary,
                                  showSymbol: true, bold: true, size: 13),
                            const SizedBox(width: AppTheme.gapSm),
                            Flexible(
                              child: StatusChip(
                                  label: st, tone: tone, dense: true),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            email.isEmpty ? 'no email address' : email,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: email.isEmpty
                                  ? AppTheme.neg(context)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),

        // ---- 底部操作区 ----
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Column(children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _alsoEmail,
                onChanged: _busy ? null : (v) => setState(() => _alsoEmail = v),
                title: const Text('Also email each payslip'),
                subtitle: const Text(
                    'Each employee receives their own PDF, '
                    'password-protected when an IC is on file.'),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || _selected == 0 ? null : _run,
                  icon: Icon(_alsoEmail ? Icons.send : Icons.picture_as_pdf),
                  label: Text(_alsoEmail
                      ? 'Generate & Send ($_selected)'
                      : 'Generate ($_selected)'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
