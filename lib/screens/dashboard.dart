import 'package:flutter/material.dart';

import '../core/payslip_pdf.dart';
import '../main.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'batch.dart';

/// 首页：本月概览 + 一键批量 + 快捷入口
class DashboardScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final int refreshToken;

  const DashboardScreen(
      {super.key, required this.onNavigate, required this.refreshToken});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final svc = appState.services;

  int _empCount = 0;
  int _monthCount = 0;
  double _monthNet = 0;
  double _monthEmployer = 0;
  double _monthGross = 0;
  String _company = '';
  final int _year = DateTime.now().year;
  final int _month = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final emps = await svc.db.listEmployees();
    final runs = await svc.db.listRuns(year: _year, month: _month);

    double g(Map<String, dynamic> r, String k) =>
        (r[k] as num?)?.toDouble() ?? 0;

    var gross = 0.0;
    var deductions = 0.0;
    var employer = 0.0;
    for (final r in runs) {
      gross += g(r, 'basic_salary') - g(r, 'unpaid_leave')
          + g(r, 'item_a') + g(r, 'item_b') + g(r, 'item_c');
      deductions += g(r, 'epf_employee') + g(r, 'socso_employee')
          + g(r, 'eis_employee') + g(r, 'pcb') + g(r, 'advance');
      employer += g(r, 'epf_employer') + g(r, 'socso_employer')
          + g(r, 'eis_employer');
    }
    final company = await svc.db.getSetting('company_name');
    if (!mounted) return;
    setState(() {
      _empCount = emps.length;
      _monthCount = runs.length;
      _monthGross = gross;
      _monthNet = gross - deductions;
      _monthEmployer = employer;
      _company = company;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppTheme.pagePadding,
        children: [
          if (_company.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
              child: Row(children: [
                Icon(Icons.storefront_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Text(_company,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),

          _periodHeader(context),
          const SizedBox(height: AppTheme.gapMd),

          // ---- KPI ----
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.75,
            mainAxisSpacing: AppTheme.gapSm,
            crossAxisSpacing: AppTheme.gapSm,
            children: [
              KpiCard(
                label: 'Employees',
                value: '$_empCount',
                icon: Icons.people_alt_outlined,
                onTap: () => widget.onNavigate(1),
              ),
              KpiCard(
                label: 'Records this month',
                value: '$_monthCount',
                icon: Icons.receipt_long_outlined,
                accent: AppTheme.warn(context),
                onTap: () => widget.onNavigate(3),
              ),
              KpiCard(
                label: 'Net payout (RM)',
                value: money(_monthNet),
                icon: Icons.payments_outlined,
                accent: AppTheme.ok(context),
              ),
              KpiCard(
                label: 'Employer EPF/SOCSO (RM)',
                value: money(_monthEmployer),
                icon: Icons.account_balance_outlined,
                accent: scheme.tertiary,
              ),
            ],
          ),

          const SizedBox(height: AppTheme.gapLg),
          _oneClickCard(context),

          const SizedBox(height: AppTheme.gapLg),
          Text('Quick actions',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppTheme.gapSm),
          Wrap(spacing: AppTheme.gapSm, runSpacing: AppTheme.gapSm, children: [
            FilledButton.icon(
              onPressed: () => widget.onNavigate(2),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Enter payroll'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onNavigate(1),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Employees'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onNavigate(3),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('History'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _periodHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Text('${monthName(_month)} $_year',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(width: AppTheme.gapSm),
      StatusChip(
        label: _monthCount == 0 ? 'Nothing yet' : '$_monthCount record(s)',
        tone: _monthCount == 0 ? Tone.neutral : Tone.ok,
      ),
      const Spacer(),
      Text('Gross RM ${money(_monthGross)}',
          style: TextStyle(
              fontSize: 12.5, color: scheme.onSurfaceVariant)),
    ]);
  }

  /// 「一键生成下月工资」入口
  Widget _oneClickCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (ny, nm) = Services.nextPeriod(_year, _month);
    final hasStaff = _empCount > 0;

    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide.none,
      ),
      child: InkWell(
        onTap: !hasStaff
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchScreen(
                      initialYear: ny,
                      initialMonth: nm,
                      initialAlsoEmail: true,
                    ),
                  ),
                );
                await _load();
              },
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(Icons.bolt,
                  size: 22, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generate ${monthName(nm)} $ny payroll',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      )),
                  const SizedBox(height: 3),
                  Text(
                    hasStaff
                        ? 'All $_empCount employee(s), then email each payslip'
                        : 'Add employees first',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimaryContainer
                          .withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
          ]),
        ),
      ),
    );
  }
}
