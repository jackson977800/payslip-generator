import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/mail.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';

/// 设置页。
///
/// 设计要点（都是踩过坑之后的决定）：
///  1. **Save 按钮固定在底部**，不随内容滚动 —— 之前放在长列表末尾，
///     内容一多就滚不到，看起来像「点了没反应」。
///  2. **分 4 个内层标签**（公司 / 工资项 / 费率 / 邮件），每页都短，
///     不需要长距离滚动。
///  3. 枚举型设置（PDF 密码、邮件加密方式）一律用**下拉选择**，
///     不让用户手打 "ic_last6" 这种内部值。
///  4. 工资项目的 Show / EPF-SOCSO-EIS 用**带列头的对齐表格**，
///     而不是两个并排的勾选块。
class SettingsScreen extends StatefulWidget {
  final VoidCallback onChanged;
  const SettingsScreen({super.key, required this.onChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final svc = appState.services;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  final Map<String, TextEditingController> c = {};
  final List<TextEditingController> earnLabels = [];
  final List<TextEditingController> dedLabels = [];
  final List<bool> earnShow = [false, false, false];
  final List<bool> earnBase = [true, true, true];

  String _smtpSecurity = 'starttls';
  String _pdfPasswordMode = 'ic_last6';
  bool _authRequired = true;

  bool _loading = true;
  bool _dirty = false;
  bool _showSmtpPass = false;
  String? _smtpPassLoaded;

  static const _company = [
    ['company_name', 'Company Name'],
    ['company_address', 'Address'],
    ['company_reg_no', 'Company Reg. No.'],
    ['company_phone', 'Phone'],
    ['company_email', 'Company Email'],
  ];
  static const _rates = [
    ['epf_ceiling', 'EPF ceiling (RM)'],
    ['epf_above_employee_rate', 'EPF employee rate above ceiling (%)'],
    ['epf_above_employer_rate', 'EPF employer rate above ceiling (%)'],
  ];
  static const _smtp = [
    ['smtp_host', 'SMTP server'],
    ['smtp_port', 'Port'],
    ['smtp_username', 'Username'],
    ['mail_from_name', 'From name'],
    ['mail_from_addr', 'From address'],
    ['mail_reply_to', 'Reply-to (optional)'],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final v in c.values) {
      v.dispose();
    }
    for (final v in earnLabels) {
      v.dispose();
    }
    for (final v in dedLabels) {
      v.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    for (final f in [..._company, ..._rates, ..._smtp]) {
      c[f[0]] = TextEditingController(text: await svc.db.getSetting(f[0]));
    }
    c['mail_subject_tpl'] =
        TextEditingController(text: await svc.db.getSetting('mail_subject_tpl'));
    c['mail_body_tpl'] =
        TextEditingController(text: await svc.db.getSetting('mail_body_tpl'));

    _smtpSecurity = await svc.db.getSetting('smtp_security');
    if (_smtpSecurity.isEmpty) _smtpSecurity = 'starttls';
    _pdfPasswordMode = await svc.db.getSetting('mail_pdf_password');
    if (_pdfPasswordMode.isEmpty) _pdfPasswordMode = 'ic_last6';
    _authRequired = (await svc.db.getSetting('smtp_auth_required')) == '1';

    final labels = await svc.earningsLabels();
    final enabled = await svc.earningsEnabled();
    final inBase = await svc.earningsInBase();
    final deds = await svc.deductionLabels();

    earnLabels.clear();
    for (var i = 2; i < 5; i++) {
      earnLabels.add(TextEditingController(
          text: i < labels.length ? labels[i] : 'Item ${i - 1}'));
    }
    for (var i = 0; i < 3; i++) {
      earnShow[i] = enabled.length > i + 2 && enabled[i + 2];
    }
    earnBase[0] = inBase.contains('itemA');
    earnBase[1] = inBase.contains('itemB');
    earnBase[2] = inBase.contains('itemC');

    dedLabels.clear();
    for (var i = 0; i < 2; i++) {
      dedLabels
          .add(TextEditingController(text: i < deds.length ? deds[i] : ''));
    }

    _smtpPassLoaded = await appState.smtpPassword();
    if (mounted) {
      setState(() {
        _loading = false;
        _dirty = false;
      });
    }
  }

  Future<void> _save() async {
    final values = <String, String>{};
    for (final f in [..._company, ..._rates, ..._smtp]) {
      values[f[0]] = c[f[0]]!.text.trim();
    }
    values['smtp_security'] = _smtpSecurity;
    values['smtp_auth_required'] = _authRequired ? '1' : '0';
    values['mail_subject_tpl'] = c['mail_subject_tpl']!.text.trim();
    values['mail_body_tpl'] = c['mail_body_tpl']!.text;
    values['mail_pdf_password'] = _pdfPasswordMode;
    values['earnings_labels'] = jsonEncode(<String>[
      'Basic Salary',
      'Less: Unpaid Leave',
      ...earnLabels.map((e) => e.text.trim()),
    ]);
    values['earnings_enabled'] =
        jsonEncode(<bool>[true, true, earnShow[0], earnShow[1], earnShow[2]]);
    values['earnings_in_base'] = jsonEncode(earnBase);
    values['deduction_labels'] =
        jsonEncode(dedLabels.map((e) => e.text.trim()).toList());

    try {
      await svc.db.setSettings(values);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Settings saved.'),
      duration: Duration(seconds: 2),
    ));
    widget.onChanged();
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);

    return Column(children: [
      Material(
        color: theme.colorScheme.surface,
        child: TabBar(
          controller: _tabs,
          labelStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Company'),
            Tab(text: 'Payslip'),
            Tab(text: 'Rates'),
            Tab(text: 'Email'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _scroll(_companyTab()),
            _scroll(_payslipTab()),
            _scroll(_ratesTab()),
            _scroll(_emailTab()),
          ],
        ),
      ),
      _saveBar(theme),
    ]);
  }

  Widget _scroll(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: children,
      );

  /// 固定在底部的保存栏 —— 关键修复点
  Widget _saveBar(ThemeData theme) {
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: Text(
                _dirty ? 'Unsaved changes' : 'All changes saved',
                style: TextStyle(
                  fontSize: 12,
                  color: _dirty
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: _dirty ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- Company
  List<Widget> _companyTab() => [
        _card('Company profile', 'Shown on every payslip header.', [
          for (final f in _company)
            _tf(f[0], f[1], lines: f[0] == 'company_address' ? 2 : 1),
        ]),
      ];

  // -------------------------------------------------------------- Payslip
  List<Widget> _payslipTab() => [
        _card(
          'Payslip items',
          'Items 3–5 come from the Excel template, where they are labelled '
              'A / B / C. They are OFF by default.',
          [
            const SizedBox(height: 2),
            _itemsTable(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Show — display this item on the Payroll page and the payslip.\n\n'
                'EPF/SOCSO/EIS — add the amount to the contribution base. '
                'EPF, SOCSO and EIS all share one base, so this single '
                'checkbox controls all three. Unticking it means the item is '
                'still paid, but no EPF/SOCSO/EIS is deducted on it.\n\n'
                'Basic Salary always counts. Unpaid Leave always reduces the base.',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
            ),
          ],
        ),
        _card('Deduction labels', 'Names for the two deduction rows.', [
          for (var i = 0; i < 2; i++)
            _tfController(dedLabels[i], 'Deduction ${i + 1}'),
        ]),
      ];

  /// 带列头的对齐表格 —— 替代原来两个并排的勾选块
  Widget _itemsTable() {
    const showW = 62.0;
    const baseW = 118.0;
    final theme = Theme.of(context);
    final headStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(children: [
      Row(children: [
        Expanded(child: Text('Item name', style: headStyle)),
        SizedBox(
            width: showW,
            child:
                Text('Show', style: headStyle, textAlign: TextAlign.center)),
        SizedBox(
            width: baseW,
            child: Text('EPF/SOCSO/EIS',
                style: headStyle, textAlign: TextAlign.center)),
      ]),
      Divider(height: 10, color: theme.dividerColor),
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: earnLabels[i],
                decoration: InputDecoration(
                  labelText: 'Item ${i + 3}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
            SizedBox(
              width: showW,
              child: Center(
                child: Checkbox(
                  value: earnShow[i],
                  onChanged: (v) => setState(() {
                    earnShow[i] = v == true;
                    _dirty = true;
                  }),
                ),
              ),
            ),
            SizedBox(
              width: baseW,
              child: Center(
                child: Checkbox(
                  value: earnBase[i],
                  onChanged: (v) => setState(() {
                    earnBase[i] = v == true;
                    _dirty = true;
                  }),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }

  // ---------------------------------------------------------------- Rates
  List<Widget> _ratesTab() => [
        _card('EPF / SOCSO / EIS', null, [
          for (final f in _rates) _tf(f[0], f[1]),
          const SizedBox(height: 4),
          const Text(
            'SOCSO and EIS are capped at RM 6,000 by the official table.\n'
            'Above the EPF ceiling, EPF is computed as a straight percentage.',
            style: TextStyle(fontSize: 11.5, height: 1.45),
          ),
        ]),
      ];

  // ---------------------------------------------------------------- Email
  List<Widget> _emailTab() => [
        _card('SMTP server', 'Where payslip emails are sent from.', [
          _tf('smtp_host', 'SMTP server'),
          Row(children: [
            SizedBox(width: 110, child: _tf('smtp_port', 'Port')),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown<String>(
                label: 'Encryption',
                value: _smtpSecurity,
                items: const {
                  'starttls': 'STARTTLS (587)',
                  'ssl': 'SSL / TLS (465)',
                  'none': 'None (unencrypted)',
                },
                onChanged: (v) => setState(() {
                  _smtpSecurity = v;
                  _dirty = true;
                }),
              ),
            ),
          ]),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _authRequired,
            onChanged: (v) => setState(() {
              _authRequired = v;
              _dirty = true;
            }),
            title: const Text('Server requires login'),
            subtitle: const Text('Turn off only for an internal relay.'),
          ),
          if (_authRequired) _tf('smtp_username', 'Username'),
          if (_authRequired) _smtpPasswordField(),
        ]),
        _card('Sender', null, [
          _tf('mail_from_name', 'From name'),
          _tf('mail_from_addr', 'From address'),
          _tf('mail_reply_to', 'Reply-to (optional)'),
        ]),
        _card(
          'Payslip PDF password',
          'Payslips are sent as password-protected PDFs. Pick the rule once — '
              'the app derives each employee\'s password from their IC number '
              'automatically, so you never type a password per person.',
          [
            _dropdown<String>(
              label: 'Password rule',
              value: _pdfPasswordMode,
              items: const {
                'ic_last6': 'Last 6 digits of IC  (recommended)',
                'ic_last4': 'Last 4 digits of IC',
                'ic_full': 'Full IC number (digits only)',
                'none': 'No password — send an open PDF',
              },
              onChanged: (v) => setState(() {
                _pdfPasswordMode = v;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 8),
            _passwordPreview(),
          ],
        ),
        _card('Message template', 'Variables are filled in per employee.', [
          _tf('mail_subject_tpl', 'Subject'),
          _tf('mail_body_tpl', 'Body', lines: 6),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [
              '{Employee Name}',
              '{Employee ID}',
              '{Month}',
              '{Year}',
              '{Company Name}',
              '{Net Salary}',
              '{Total Salary}',
              '{PDF Password Note}',
            ]
                .map((v) => Chip(
                      // 不要在这里写 TextStyle —— 会让 chipTheme 的
                      // labelStyle 失效（颜色被覆盖成 null）。
                      label: Text(v),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ]),
        OutlinedButton.icon(
          onPressed: _testMail,
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Save and test connection'),
        ),
      ];

  /// 让用户看到「实际会生成什么密码」，而不是让他手打内部值
  Widget _passwordPreview() {
    final theme = Theme.of(context);
    if (_pdfPasswordMode == 'none') {
      return Text('Employees will receive an unprotected PDF.',
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant));
    }
    const sample = '900101-14-0001';
    final digits = sample.replaceAll(RegExp(r'[^0-9]'), '');
    final n = _pdfPasswordMode == 'ic_last4'
        ? 4
        : (_pdfPasswordMode == 'ic_full' ? digits.length : 6);
    final pw = digits.substring(digits.length - n);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Example — IC $sample  →  password $pw',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ]),
    );
  }

  Future<void> _testMail() async {
    await _save();
    final cfg = await svc.mailConfig(await appState.smtpPassword());
    final err = await testMailConnection(cfg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? 'Connection and login succeeded.'
          : 'Could not connect: $err'),
      duration: const Duration(seconds: 5),
    ));
  }

  // ------------------------------------------------------------- helpers
  Widget _smtpPasswordField() {
    final ctrl = c.putIfAbsent(
      '__pass',
      () => TextEditingController(text: _smtpPassLoaded ?? ''),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        obscureText: !_showSmtpPass,
        decoration: InputDecoration(
          labelText: 'Password / App password',
          helperText: 'Stored in the device secure storage (Android Keystore).',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(_showSmtpPass ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showSmtpPass = !_showSmtpPass),
          ),
        ),
        onChanged: (v) => appState.setSmtpPassword(v),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required void Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items.entries
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value,
                      style: const TextStyle(fontSize: 13.5),
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _tf(String key, String label, {int lines = 1}) {
    final ctrl = c[key];
    if (ctrl == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('(missing field: $key)',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    return _tfController(ctrl, label, lines: lines);
  }

  Widget _tfController(TextEditingController ctrl, String label,
      {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        maxLines: lines,
        onChanged: (_) => _markDirty(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _card(String title, String? hint, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      child: SectionCard(title: title, hint: hint, children: children),
    );
  }
}
