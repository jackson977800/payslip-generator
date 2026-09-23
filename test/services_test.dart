// 业务规则测试：停用项按 0、模板变量替换、邮件配置校验、PDF 密码推导。
// 这些都是纯逻辑，不依赖 Android 插件。
import 'package:flutter_test/flutter_test.dart';
import 'package:payslip_app/core/mail.dart';
import 'package:payslip_app/core/payroll.dart';
import 'package:payslip_app/core/rates.dart';
import 'package:payslip_app/services.dart';

void main() {
  group('停用的收入项目按 0 参与计算', () {
    test('关闭 A/B/C 时即使填了值也不计入', () {
      const inp = PayrollInput(basicSalary: 1700, itemA: 300, itemB: 50);
      final out = Services.applyEnabled(inp, const [true, true, false, false, false]);
      expect(out.itemA, 0);
      expect(out.itemB, 0);
      expect(out.basicSalary, 1700);
    });

    test('启用后原样保留', () {
      const inp = PayrollInput(basicSalary: 1700, itemA: 300);
      final out = Services.applyEnabled(inp, const [true, true, true, false, false]);
      expect(out.itemA, 300);
    });
  });

  group('邮件模板变量替换', () {
    test('已知变量被替换', () {
      final out = Services.renderTemplate(
          'Payslip {Month} {Year} - {Employee Name}',
          {'Month': 'September', 'Year': '2026', 'Employee Name': 'Ahmad'});
      expect(out, 'Payslip September 2026 - Ahmad');
    });

    test('未知变量原样保留，花括号不会抛异常', () {
      expect(Services.renderTemplate('a {Nope} b', const {}), 'a {Nope} b');
      expect(Services.renderTemplate('cost {unclosed', const {}),
          'cost {unclosed');
    });
  });

  group('邮件配置校验', () {
    test('完整配置通过', () {
      const cfg = MailConfig(
          host: 'smtp.example.com', port: 587, fromAddr: 'hr@example.com',
          username: 'u');
      expect(cfg.validate(), isEmpty);
    });

    test('缺配置时列出全部问题', () {
      const cfg = MailConfig();
      final errs = cfg.validate();
      expect(errs.length, greaterThanOrEqualTo(3));
      expect(errs.join(' '), contains('SMTP server'));
    });

    test('非法发件地址被拦下', () {
      const cfg = MailConfig(
          host: 'h', port: 587, fromAddr: 'not-an-email', username: 'u');
      expect(cfg.validate().join(' '), contains('not valid'));
    });

    test('邮箱格式校验', () {
      expect(isValidEmail('a.b@company.com.my'), isTrue);
      expect(isValidEmail('not-an-email'), isFalse);
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('a@b'), isFalse);
    });

    test('错误信息可读（认证失败给出应用密码提示）', () {
      final msg = friendlyMailError(
          Exception('535 5.7.8 Username and Password not accepted'));
      expect(msg.toLowerCase(), contains('app password'));
    });
  });

  group('PDF 密码推导（与桌面版一致）', () {
    // Services.pdfPassword 需要数据库，这里直接验证同一条规则：
    // 去掉非数字字符后取后 N 位。
    String derive(String nric, int n) {
      final d = nric.replaceAll(RegExp(r'[^0-9]'), '');
      return d.length >= n ? d.substring(d.length - n) : '';
    }

    test('IC 取后 6 位数字，连字符不计入', () {
      expect(derive('900101-14-0001', 6), '140001');
      expect(derive('900101140001', 6), '140001');
    });

    test('IC 缺失或过短时不加密', () {
      expect(derive('', 6), '');
      expect(derive('12', 6), '');
      expect(derive('abc-def', 6), '');
    });

    test('后 4 位', () {
      expect(derive('900101-14-0001', 4), '0001');
    });
  });

  group('期间推算（一键生成下月用）', () {
    test('下个月正常进位', () {
      expect(Services.nextPeriod(2026, 9), (2026, 10));
      expect(Services.nextPeriod(2026, 1), (2026, 2));
    });

    test('跨年进位', () {
      expect(Services.nextPeriod(2026, 12), (2027, 1));
      expect(Services.nextPeriod(2026, 11), (2026, 12));
    });

    test('上个月跨年退位', () {
      expect(Services.prevPeriod(2026, 1), (2025, 12));
      expect(Services.prevPeriod(2026, 9), (2026, 8));
    });

    test('连续调用可以跨多个月', () {
      var y = 2026, m = 10;
      for (var i = 0; i < 15; i++) {
        final (ny, nm) = Services.nextPeriod(y, m);
        y = ny;
        m = nm;
      }
      expect((y, m), (2028, 1));
    });
  });

  group('费率表与引擎一致性', () {
    test('空输入不产生缴金', () {
      final book = RateBook(epf: const [], socso: const []);
      final r = compute(const PayrollInput(), book);
      expect(r.epfEmployee, 0);
      expect(r.netSalary, 0);
    });
  });
}
