import 'dart:convert';
import 'package:flutter/services.dart';

/// 与 Python 版 `round(x + 1e-9, 2)` 等价的取整。
///
/// 桌面版用 round2() 消除浮点半值歧义；这里保持同样语义：
/// 先加一个极小正数，再取两位小数。有此 epsilon 后
/// 「银行家舍入」与「四舍五入」在半值处的结果一致，
/// 因此可安全使用 toStringAsFixed。
double round2(double x) {
  final v = x + 1e-9;
  final s = v.toStringAsFixed(2);
  final d = double.tryParse(s);
  return d ?? 0.0;
}

/// 费率表：EPF / SOCSO / EIS。
///
/// 完全复刻参考 Excel 的 VLOOKUP 近似匹配：
/// 取「下限 <= 薪资基数」的最后一行。
class RateBook {
  final List<Map<String, dynamic>> epf;
  final List<Map<String, dynamic>> socso;

  final double epfCeiling;
  final double epfAboveEe;
  final double epfAboveEr;
  final bool epfRoundUp;

  RateBook({
    required this.epf,
    required this.socso,
    this.epfCeiling = 20000,
    this.epfAboveEe = 11,
    this.epfAboveEr = 12,
    this.epfRoundUp = true,
  });

  static double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory RateBook.fromRows(
    List<dynamic> epfRows,
    List<dynamic> socsoRows, {
    double epfCeiling = 20000,
    double epfAboveEe = 11,
    double epfAboveEr = 12,
    bool epfRoundUp = true,
  }) {
    List<Map<String, dynamic>> norm(List<dynamic> src) {
      final out = src
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => _num(a['from']).compareTo(_num(b['from'])));
      return out;
    }

    return RateBook(
      epf: norm(epfRows),
      socso: norm(socsoRows),
      epfCeiling: epfCeiling,
      epfAboveEe: epfAboveEe,
      epfAboveEr: epfAboveEr,
      epfRoundUp: epfRoundUp,
    );
  }

  /// 从打包资源加载费率表。
  static Future<RateBook> load({
    double epfCeiling = 20000,
    double epfAboveEe = 11,
    double epfAboveEr = 12,
    bool epfRoundUp = true,
  }) async {
    final epfRaw =
        jsonDecode(await rootBundle.loadString('assets/epf_table.json'));
    final socsoRaw =
        jsonDecode(await rootBundle.loadString('assets/socso_eis_table.json'));
    return RateBook.fromRows(
      epfRaw as List<dynamic>,
      socsoRaw as List<dynamic>,
      epfCeiling: epfCeiling,
      epfAboveEe: epfAboveEe,
      epfAboveEr: epfAboveEr,
      epfRoundUp: epfRoundUp,
    );
  }

  double _vlookup(List<Map<String, dynamic>> rows, double value, String column) {
    Map<String, dynamic>? found;
    for (final r in rows) {
      final lo = _num(r['from']);
      if (lo <= value) {
        found = r;
      } else {
        break;
      }
    }
    if (found == null) return 0.0;
    return _num(found[column]);
  }

  /// EPF 缴纳额（雇员, 雇主）
  List<double> epfContribution(double base) {
    if (base <= 0) return [0.0, 0.0];
    if (base > epfCeiling) {
      final ee = round2(base * epfAboveEe / 100.0);
      var er = round2(base * epfAboveEr / 100.0);
      if (epfRoundUp) {
        final total = round2(ee + er).ceilToDouble();
        er = round2(total - ee);
      }
      return [ee, er];
    }
    return [
      round2(_vlookup(epf, base, 'employee')),
      round2(_vlookup(epf, base, 'employer')),
    ];
  }

  /// SOCSO 缴纳额（雇员, 雇主）
  List<double> socsoContribution(double base) {
    if (base <= 0) return [0.0, 0.0];
    return [
      round2(_vlookup(socso, base, 'socso_employee')),
      round2(_vlookup(socso, base, 'socso_employer')),
    ];
  }

  /// EIS 缴纳额（雇员, 雇主）
  List<double> eisContribution(double base) {
    if (base <= 0) return [0.0, 0.0];
    return [
      round2(_vlookup(socso, base, 'eis_employee')),
      round2(_vlookup(socso, base, 'eis_employer')),
    ];
  }
}
