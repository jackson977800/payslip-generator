import 'package:flutter/material.dart';

import 'core/payslip_pdf.dart';
import 'theme.dart';

/// 金额显示：等宽数字 + 右对齐，保证一列数字的个位对齐。
class MoneyText extends StatelessWidget {
  final double value;
  final bool showSymbol;
  final bool bold;
  final bool negative;
  final Color? color;
  final double size;

  const MoneyText(
    this.value, {
    super.key,
    this.showSymbol = false,
    this.bold = false,
    this.negative = false,
    this.color,
    this.size = 13.5,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '${negative ? '−' : ''}${money(value, symbol: showSymbol ? 'RM' : '')}',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: color ?? scheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 统一的卡片：标题 + 可选副标题 + 内容。
/// 设置页、批量页、明细页都用它，保证同一件事长得一样。
class SectionCard extends StatelessWidget {
  final String? title;
  final String? hint;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const SectionCard({
    super.key,
    this.title,
    this.hint,
    this.trailing,
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding ??
            const EdgeInsets.fromLTRB(
                AppTheme.gapLg, AppTheme.gapMd, AppTheme.gapLg, AppTheme.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || trailing != null)
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                      if (hint != null) ...[
                        const SizedBox(height: 3),
                        Text(hint!,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ]),
            if (title != null || trailing != null)
              const SizedBox(height: AppTheme.gapMd),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 空状态：图标 + 一句话 + 可选操作。
/// 之前各页的空状态都是裸 Text，既不统一也不告诉用户下一步做什么。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTheme.gapLg),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: AppTheme.gapSm),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.gapLg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 状态胶囊：已发送 / 未发送 / 失败 / 仅底薪
enum Tone { ok, warn, bad, neutral }

class StatusChip extends StatelessWidget {
  final String label;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  const StatusChip({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color fg;
    switch (tone) {
      case Tone.ok:
        fg = AppTheme.ok(context);
        break;
      case Tone.warn:
        fg = AppTheme.warn(context);
        break;
      case Tone.bad:
        fg = AppTheme.neg(context);
        break;
      case Tone.neutral:
        fg = scheme.onSurfaceVariant;
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 11 : 13, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: dense ? 10.5 : 11.5,
                fontWeight: FontWeight.w600,
                color: fg),
          ),
        ),
      ]),
    );
  }
}

/// 首页 KPI 卡片
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: scheme.onSurfaceVariant)),
                ),
              ]),
              const SizedBox(height: AppTheme.gapSm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「标签 —— 金额」一行，用于各种明细
class AmountRow extends StatelessWidget {
  final String label;
  final double? value;
  final String? text;
  final bool bold;
  final bool negative;
  final bool muted;
  final bool dividerAbove;

  const AmountRow(
    this.label, {
    super.key,
    this.value,
    this.text,
    this.bold = false,
    this.negative = false,
    this.muted = false,
    this.dividerAbove = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted ? scheme.onSurfaceVariant : scheme.onSurface;
    return Column(children: [
      if (dividerAbove) const Divider(height: AppTheme.gapLg),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
          if (text != null)
            Text(text!,
                style: TextStyle(
                    fontSize: 13.5,
                    color: color,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500))
          else
            MoneyText(value ?? 0,
                bold: bold,
                negative: negative,
                color: negative ? AppTheme.neg(context) : color),
        ]),
      ),
    ]);
  }
}
