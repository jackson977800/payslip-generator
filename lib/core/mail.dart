import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 邮件配置。与桌面版 Settings → Email 的字段一一对应。
class MailConfig {
  final String host;
  final int port;
  final String security; // starttls / ssl / none
  final String username;
  final String password;
  final String fromName;
  final String fromAddr;
  final String replyTo;
  final bool authRequired;

  const MailConfig({
    this.host = '',
    this.port = 587,
    this.security = 'starttls',
    this.username = '',
    this.password = '',
    this.fromName = '',
    this.fromAddr = '',
    this.replyTo = '',
    this.authRequired = true,
  });

  /// 返回缺失项说明；为空表示配置完整。
  List<String> validate() {
    final errs = <String>[];
    if (host.trim().isEmpty) errs.add('SMTP server is not set.');
    if (port < 1 || port > 65535) errs.add('SMTP port is invalid.');
    if (fromAddr.trim().isEmpty) {
      errs.add('Sender email address is not set.');
    } else if (!isValidEmail(fromAddr)) {
      errs.add('Sender email address is not valid.');
    }
    if (replyTo.trim().isNotEmpty && !isValidEmail(replyTo)) {
      errs.add('Reply-to address is not valid.');
    }
    if (authRequired && username.trim().isEmpty) {
      errs.add('SMTP username is not set.');
    }
    return errs;
  }

  SmtpServer server() {
    final needAuth = authRequired && username.trim().isNotEmpty;
    return SmtpServer(
      host.trim(),
      port: port,
      ssl: security == 'ssl',
      // 仅在内网明文端口上允许不安全连接
      allowInsecure: security == 'none',
      username: needAuth ? username.trim() : null,
      password: needAuth ? password : null,
    );
  }
}

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

bool isValidEmail(String s) => _emailRe.hasMatch(s.trim());

/// 把底层异常翻译成使用者能看懂的一句话。
String friendlyMailError(Object e) {
  final s = e.toString();
  final low = s.toLowerCase();
  if (low.contains('535') ||
      low.contains('authentication') ||
      low.contains('username and password not accepted') ||
      low.contains('invalid credentials')) {
    return 'Authentication failed. For Gmail / Outlook you must use an app '
        'password, not your normal login password.';
  }
  if (low.contains('connection refused')) {
    return 'Connection refused — check the SMTP host and port.';
  }
  if (low.contains('failed host lookup') || low.contains('nodename')) {
    return 'Server address not found — check the SMTP host name.';
  }
  if (low.contains('timed out') || low.contains('timeout')) {
    return 'Connection timed out.';
  }
  if (low.contains('certificate') ||
      low.contains('handshake') ||
      low.contains('tls')) {
    return 'TLS/SSL error — check the encryption setting '
        '(try STARTTLS on 587, or SSL on 465).';
  }
  if (low.contains('recipient') && low.contains('refused')) {
    return 'Recipient refused by the server.';
  }
  return s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

/// 发送一封带附件的邮件。成功返回 null，失败返回错误说明。
Future<String?> sendMail({
  required MailConfig cfg,
  required String toAddr,
  required String subject,
  required String body,
  String? attachmentPath,
}) async {
  if (!isValidEmail(toAddr)) return 'Invalid recipient address: $toAddr';
  final errs = cfg.validate();
  if (errs.isNotEmpty) return errs.join(' ');

  final msg = Message()
    ..from = cfg.fromName.trim().isEmpty
        ? cfg.fromAddr.trim()
        : '${cfg.fromName.trim()} <${cfg.fromAddr.trim()}>'
    ..recipients.add(toAddr.trim())
    ..subject = subject
    ..text = body;
  if (cfg.replyTo.trim().isNotEmpty) {
    msg.headers['Reply-To'] = cfg.replyTo.trim();
  }
  if (attachmentPath != null) {
    final f = File(attachmentPath);
    if (await f.exists()) msg.attachments.add(FileAttachment(f));
  }

  try {
    await send(msg, cfg.server());
    return null;
  } catch (e) {
    return friendlyMailError(e);
  }
}

/// 测试连接与登录。成功返回 null。
Future<String?> testMailConnection(MailConfig cfg) async {
  final errs = cfg.validate();
  if (errs.isNotEmpty) return errs.join(' ');
  try {
    await checkCredentials(cfg.server(),
        timeout: const Duration(seconds: 20));
    return null;
  } catch (e) {
    return friendlyMailError(e);
  }
}

/// 应用私有目录（生成的工资单 PDF 放这里）
Future<Directory> appDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory(p.join(base.path, 'payslips'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}
