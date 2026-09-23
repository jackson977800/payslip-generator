import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/format/dict.dart';
import 'package:pdf/src/pdf/format/num.dart';
import 'package:pdf/src/pdf/format/object_base.dart';
import 'package:pdf/src/pdf/format/string.dart';
import 'package:pdf/src/pdf/obj/object.dart';

/// PDF 标准安全处理器（Standard Security Handler）。
///
/// `pdf` 包只提供了 [PdfEncryption] 抽象类，没有具体实现，
/// 因此这里自行实现 PDF 1.7 规范中的 RC4 128 位方案
/// （/V 2 /R 3），与桌面版 reportlab 的 StandardEncryption 行为对齐：
/// **允许打印，禁止复制内容、修改与加注**。
///
/// 算法依据 PDF 1.7 spec：
///   Algorithm 2 —— 由用户口令推导加密密钥
///   Algorithm 3 —— 计算 /O（拥有者条目）
///   Algorithm 5 —— 计算 /U（用户条目，R >= 3）
///   Algorithm 1 —— 每个间接对象各自的密钥
class StandardSecurityHandler extends PdfEncryption {
  StandardSecurityHandler(
    super.pdfDocument, {
    required this.userPassword,
    String? ownerPassword,
    this.canPrint = true,
    this.canModify = false,
    this.canCopy = false,
    this.canAnnotate = false,
  }) : ownerPassword = ownerPassword ?? userPassword {
    _build();
  }

  final String userPassword;
  final String ownerPassword;
  final bool canPrint;
  final bool canModify;
  final bool canCopy;
  final bool canAnnotate;

  /// PDF 规范规定的 32 字节口令填充串
  static const List<int> _pad = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  static const int _keyLength = 16; // 128 位
  static const int _revision = 3;
  static const int _version = 2;

  late Uint8List _encryptionKey;
  late Uint8List _o;
  late Uint8List _u;
  late int _p;

  /// 文件标识（ID[0]），写入 trailer
  late Uint8List _fileId;

  Uint8List get fileId => _fileId;

  /// 权限位：从全 1 开始，逐位开关。
  /// 位 1、2 必须为 0；位 12 保留必须为 1。
  static int _computePermissions({
    required bool canPrint,
    required bool canModify,
    required bool canCopy,
    required bool canAnnotate,
  }) {
    var p = -1;
    void setBit(int bit, bool on) {
      final mask = 1 << (bit - 1);
      if (on) {
        p |= mask;
      } else {
        p &= ~mask;
      }
    }

    setBit(1, false);
    setBit(2, false);
    setBit(3, canPrint); // 打印
    setBit(4, canModify); // 修改内容
    setBit(5, canCopy); // 复制内容
    setBit(6, canAnnotate); // 加注
    setBit(7, true); // 填写表单
    setBit(8, true); // 填写表单
    setBit(9, true); // 无障碍读取
    setBit(10, false); // 组装文档
    setBit(11, canPrint); // 高分辨率打印
    setBit(12, true); // 保留位，必须为 1
    return p;
  }

  /// 用填充串把口令补齐/截断到 32 字节
  static Uint8List _padPassword(String password) {
    final raw = latin1.encode(password);
    final out = Uint8List(32);
    final n = min(raw.length, 32);
    for (var i = 0; i < n; i++) {
      out[i] = raw[i];
    }
    for (var i = n; i < 32; i++) {
      out[i] = _pad[i - n];
    }
    return out;
  }

  static Uint8List _md5(List<int> data) =>
      Uint8List.fromList(md5.convert(data).bytes);

  static Uint8List _rc4(List<int> key, List<int> data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final out = Uint8List(data.length);
    var a = 0;
    var b = 0;
    for (var k = 0; k < data.length; k++) {
      a = (a + 1) & 0xFF;
      b = (b + s[a]) & 0xFF;
      final t = s[a];
      s[a] = s[b];
      s[b] = t;
      out[k] = data[k] ^ s[(s[a] + s[b]) & 0xFF];
    }
    return out;
  }

  void _build() {
    _p = _computePermissions(
      canPrint: canPrint,
      canModify: canModify,
      canCopy: canCopy,
      canAnnotate: canAnnotate,
    );

    // 文件标识必须与 trailer 里写入的 /ID 完全一致，
    // 否则密钥推导用的是另一个 ID，任何密码都会被判为错误。
    // PdfDocument.documentID 惰性生成且带缓存，trailer 写入的正是它。
    _fileId = Uint8List.fromList(pdfDocument.documentID);

    // ---- Algorithm 3：计算 /O ----
    var ownerKey = _md5(_padPassword(ownerPassword));
    for (var i = 0; i < 50; i++) {
      ownerKey = _md5(ownerKey);
    }
    final rc4Key = Uint8List.sublistView(ownerKey, 0, _keyLength);
    var o = _rc4(rc4Key, _padPassword(userPassword));
    for (var i = 1; i <= 19; i++) {
      final k = Uint8List.fromList(
          List<int>.generate(_keyLength, (n) => rc4Key[n] ^ i));
      o = _rc4(k, o);
    }
    _o = o;

    // ---- Algorithm 2：由用户口令推导加密密钥 ----
    final pBytes = ByteData(4)..setInt32(0, _p, Endian.little);
    final seed = <int>[
      ..._padPassword(userPassword),
      ..._o,
      ...pBytes.buffer.asUint8List(),
      ..._fileId,
    ];
    var key = _md5(seed);
    for (var i = 0; i < 50; i++) {
      key = _md5(Uint8List.sublistView(key, 0, _keyLength));
    }
    _encryptionKey = Uint8List.sublistView(key, 0, _keyLength);

    // ---- Algorithm 5：计算 /U（R >= 3） ----
    final uSeed = <int>[..._pad, ..._fileId];
    var u = _md5(uSeed);
    u = _rc4(_encryptionKey, u);
    for (var i = 1; i <= 19; i++) {
      final k = Uint8List.fromList(
          List<int>.generate(_keyLength, (n) => _encryptionKey[n] ^ i));
      u = _rc4(k, u);
    }
    final uOut = Uint8List(32);
    uOut.setRange(0, 16, u);
    // 后 16 字节为任意值（规范允许），保持 0
    _u = uOut;
  }

  /// Algorithm 1：每个间接对象各自的密钥
  Uint8List _objectKey(int objNum, int genNum) {
    final extra = <int>[
      objNum & 0xFF,
      (objNum >> 8) & 0xFF,
      (objNum >> 16) & 0xFF,
      genNum & 0xFF,
      (genNum >> 8) & 0xFF,
    ];
    final digest = _md5(<int>[..._encryptionKey, ...extra]);
    final n = min(_keyLength + 5, 16);
    return Uint8List.sublistView(digest, 0, n);
  }

  @override
  Uint8List encrypt(Uint8List input, PdfObjectBase object) {
    var objNum = 0;
    var genNum = 0;
    if (object is PdfObject) {
      objNum = object.objser;
      genNum = object.objgen;
    }
    if (objNum == 0) return input;
    return _rc4(_objectKey(objNum, genNum), input);
  }

  @override
  PdfDict get params => PdfDict({
        // 注意：pdf 包的 PdfDict 只在「数字值」前补空格，键必须自带 '/'，
        // 否则 /Standard 会和下一个键粘成 /StandardV、2 会和 R 粘成 2R，
        // 整个字典语法错误 —— 任何 PDF 解析器都会报 UnsupportedSecurityScheme。
        '/Filter': PdfName('/Standard'),
        '/V': PdfNum(_version),
        '/R': PdfNum(_revision),
        '/Length': PdfNum(_keyLength * 8),
        '/P': PdfNum(_p),
        // /O 与 /U 属于安全处理器自身，必须明文写入
        '/O': PdfString(_o, format: PdfStringFormat.binary, encrypted: false),
        '/U': PdfString(_u, format: PdfStringFormat.binary, encrypted: false),
      });
}
