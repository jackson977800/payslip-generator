// 回归测试：Chip 标签必须有可读的颜色。
//
// 真机反馈：Settings → Email 里那排变量标签几乎看不见。
// 根因是 chipTheme.labelStyle 只写了 fontSize 没写 color ——
// Flutter 会**原样使用**这个 style（不与 M3 默认值合并），
// 于是生效颜色是 null。
//
// 这里直接读出生效的 DefaultTextStyle，不靠肉眼判断。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payslip_app/theme.dart';

Future<List<TextStyle>> _chipStyles(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Center(
        child: Wrap(spacing: 6, runSpacing: 6, children: const [
          // 与 settings.dart 里一致的写法
          Chip(
            label: Text('{Employee Name}'),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      ),
    ),
  ));
  return tester
      .widgetList<DefaultTextStyle>(find.descendant(
        of: find.byType(Chip),
        matching: find.byType(DefaultTextStyle),
      ))
      .map((d) => d.style)
      .toList();
}

void main() {
  testWidgets('浅色主题下 Chip 标签颜色不透明', (tester) async {
    final styles = await _chipStyles(tester, AppTheme.light());
    final withColor = styles.where((s) => s.color != null).toList();
    expect(withColor, isNotEmpty,
        reason: 'Chip 的 DefaultTextStyle 必须有 color，'
            '否则真机上标签不可见');
    expect(withColor.any((s) => s.color!.a > 0.7), isTrue,
        reason: '颜色必须基本不透明');
  });

  testWidgets('深色主题下 Chip 标签颜色不透明', (tester) async {
    final styles = await _chipStyles(tester, AppTheme.dark());
    final withColor = styles.where((s) => s.color != null).toList();
    expect(withColor, isNotEmpty, reason: '深色主题同样必须有 color');
    expect(withColor.any((s) => s.color!.a > 0.7), isTrue);
  });

  testWidgets('Chip 标签颜色与背景有足够对比', (tester) async {
    final theme = AppTheme.light();
    final styles = await _chipStyles(tester, theme);
    final fg = styles.firstWhere((s) => s.color != null).color!;
    final bg = theme.colorScheme.surfaceContainerHighest;

    // 用相对亮度差做粗略对比判断（WCAG 的简化版）
    double lum(Color c) {
      double ch(double v) =>
          v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    final l1 = lum(fg), l2 = lum(bg);
    final ratio = (l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05));
    expect(ratio, greaterThan(3.0),
        reason: '前景/背景对比度 ${ratio.toStringAsFixed(2)}:1 太低，'
            '小字号标签至少要 3:1');
  });
}

double _pow(double x, double e) {
  // 避免依赖 dart:math 的 import
  var r = 1.0;
  var base = x;
  var n = e.toInt();
  while (n > 0) {
    if (n & 1 == 1) r *= base;
    base *= base;
    n >>= 1;
  }
  return r;
}
