import 'package:flutter/material.dart';

import '../core/rates.dart' show round2;
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';

/// 员工管理：列表 + 新增/编辑/删除
class EmployeesScreen extends StatefulWidget {
  final int refreshToken;
  final VoidCallback onChanged;

  const EmployeesScreen(
      {super.key, required this.refreshToken, required this.onChanged});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final svc = appState.services;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EmployeesScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    var rows = await svc.db.listEmployees();
    rows = rows.where((e) {
      final active = (e['active'] as num?)?.toInt() != 0;
      return _showArchived ? true : active;
    }).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      rows = rows.where((e) {
        final hay = ['name', 'employee_no', 'job_title', 'department', 'nric',
                     'email']
            .map((k) => '${e[k] ?? ''}')
            .join(' ')
            .toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _EmployeeForm(existing: existing)),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }

  /// 归档 —— 保留全部工资历史，只是从「在职」列表里移走。
  Future<void> _archive(Map<String, dynamic> e) async {
    final id = (e['id'] as num).toInt();
    final runs = await svc.db.runCountFor(id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive this employee?'),
        content: Text('${e['name']} will be moved to Archived and hidden '
            'from the payroll list.\n\n'
            'Their ${runs == 0 ? 'records' : '$runs payroll record(s)'} '
            'are kept — you can restore them at any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true) return;
    await svc.db.archiveEmployee(id);
    await _load();
    widget.onChanged();
  }

  Future<void> _restore(Map<String, dynamic> e) async {
    await svc.db.restoreEmployee((e['id'] as num).toInt());
    await _load();
    widget.onChanged();
  }

  /// 彻底删除 —— 会连工资历史一起抹掉，必须二次确认。
  Future<void> _purge(Map<String, dynamic> e) async {
    final id = (e['id'] as num).toInt();
    final runs = await svc.db.runCountFor(id);
    if (!mounted) return;
    final typed = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Delete permanently?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('This erases ${e['name']} AND their $runs payroll '
                'record(s). Payslips already sent to the employee are not '
                'affected, but you will lose your own copy of the records.\n\n'
                'Type DELETE to confirm.',
                style: const TextStyle(height: 1.45)),
            const SizedBox(height: AppTheme.gapMd),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'DELETE', border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, ''),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );
    if (typed != 'DELETE') return;
    await svc.db.purgeEmployee(id);
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search name / ID / email',
            ),
            onChanged: (v) {
              _query = v;
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapSm),
          child: Row(children: [
            Expanded(
              child: Text(
                _showArchived
                    ? 'Showing archived employees too'
                    : 'Showing active employees',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _showArchived = !_showArchived);
                _load();
              },
              icon: Icon(
                  _showArchived
                      ? Icons.visibility_off_outlined
                      : Icons.archive_outlined,
                  size: 16),
              label: Text(_showArchived ? 'Hide archived' : 'Show archived',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty
              ? EmptyState(
                  icon: _query.isEmpty
                      ? Icons.people_outline
                      : Icons.search_off,
                  title: _query.isEmpty
                      ? 'No employees yet'
                      : 'Nothing matches "$_query"',
                  message: _query.isEmpty
                      ? 'Add your staff so you can start generating payslips.'
                      : 'Try a different name, ID or email.',
                  action: _query.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text('Add employee'),
                        )
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _rows[i];
                    final email = '${e['email'] ?? ''}';
                    final name = '${e['name'] ?? ''}';
                    final archived = (e['active'] as num?)?.toInt() == 0;
                    final subtitle = [
                      '${e['employee_no'] ?? ''}',
                      '${e['job_title'] ?? ''}',
                    ].where((s) => s.trim().isNotEmpty).join('  ·  ');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gapMd, vertical: AppTheme.gapXs),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          name.isEmpty
                              ? '?'
                              : name.characters.first.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (subtitle.isNotEmpty)
                            Text(subtitle,
                                style: const TextStyle(fontSize: 12.5)),
                          const SizedBox(height: 3),
                          Row(children: [
                            MoneyText(
                              (e['basic_salary'] as num?)?.toDouble() ?? 0,
                              showSymbol: true,
                              size: 12.5,
                            ),
                            const SizedBox(width: AppTheme.gapSm),
                            if (archived)
                              const StatusChip(
                                  label: 'Archived',
                                  tone: Tone.neutral,
                                  icon: Icons.archive_outlined,
                                  dense: true)
                            else if (email.isEmpty)
                              const StatusChip(
                                  label: 'no email',
                                  tone: Tone.warn,
                                  icon: Icons.mail_outline,
                                  dense: true)
                            else
                              Flexible(
                                child: Text(email,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5)),
                              ),
                          ]),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              _edit(e);
                            case 'archive':
                              _archive(e);
                            case 'restore':
                              _restore(e);
                            case 'purge':
                              _purge(e);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.edit_outlined, size: 18),
                                  title: Text('Edit'))),
                          if (archived)
                            const PopupMenuItem(
                                value: 'restore',
                                child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        Icon(Icons.unarchive_outlined, size: 18),
                                    title: Text('Restore')))
                          else
                            const PopupMenuItem(
                                value: 'archive',
                                child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading:
                                        Icon(Icons.archive_outlined, size: 18),
                                    title: Text('Archive'))),
                          PopupMenuItem(
                              value: 'purge',
                              child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_forever_outlined,
                                      size: 18,
                                      color:
                                          Theme.of(context).colorScheme.error),
                                  title: Text('Delete permanently',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)))),
                        ],
                      ),
                      onTap: () => _edit(e),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
    );
  }
}

/// 新增 / 编辑员工表单
class _EmployeeForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _EmployeeForm({this.existing});

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final svc = appState.services;
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;

  static const _fields = [
    ['name', 'Employee Name *'],
    ['employee_no', 'Employee ID'],
    ['nric', 'NRIC No.'],
    ['job_title', 'Job Title'],
    ['department', 'Department'],
    ['epf_no', 'EPF No.'],
    ['socso_no', 'SOCSO No.'],
    ['eis_no', 'EIS No.'],
    ['bank_name', 'Bank Name'],
    ['bank_account', 'Bank Account Number'],
    ['email', 'Email (for payslip delivery)'],
    ['basic_salary', 'Basic Salary (RM) *'],
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    c = {
      for (final f in _fields)
        f[0]: TextEditingController(text: '${e[f[0]] ?? ''}'),
    };
  }

  @override
  void dispose() {
    for (final v in c.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final basic = double.tryParse(c['basic_salary']!.text.trim()) ?? 0;
    final values = <String, dynamic>{
      for (final f in _fields) f[0]: c[f[0]]!.text.trim(),
      'basic_salary': basic,
      'active': 1,
    };
    final email = '${values['email']}'.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Email address looks invalid.')));
      return;
    }
    if (widget.existing == null) {
      await svc.db.addEmployee(values);
    } else {
      await svc.db
          .updateEmployee((widget.existing!['id'] as num).toInt(), values);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Employee' : 'Edit Employee'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  controller: c[f[0]],
                  decoration: InputDecoration(
                    labelText: f[1],
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: f[0] == 'basic_salary'
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : (f[0] == 'email'
                          ? TextInputType.emailAddress
                          : TextInputType.text),
                  validator: (v) {
                    if (f[0] == 'name' && (v ?? '').trim().isEmpty) {
                      return 'Employee Name is required';
                    }
                    if (f[0] == 'basic_salary') {
                      final d = double.tryParse((v ?? '').trim());
                      if (d == null || round2(d) <= 0) {
                        return 'Enter a valid basic salary';
                      }
                    }
                    return null;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
