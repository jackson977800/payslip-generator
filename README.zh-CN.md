# 工资单生成器 Payslip Generator

面向马来西亚小型企业的算薪工具 —— 自动计算 **EPF / SOCSO / EIS**，
生成带密码保护的工资单 PDF，并直接邮件发给员工。

提供 **安卓版** 与 **Windows 电脑版** 两套。两者共用同一套计算引擎，
算出的数字完全一致。

[English →](README.md)

---

## 功能

| | |
|---|---|
| **员工管理** | 记录 IC、EPF/SOCSO/EIS 编号、银行账户、邮箱 |
| **工资录入** | 输入底薪、无薪假、最多三个额外项目、PCB 与预支。EPF / SOCSO / EIS 自动查表 |
| **工资单 PDF** | 单页 A4，版式与原 Excel 模板一致，可选加密 |
| **邮件发送** | 每人一封，密码由 IC 号码自动推导 |
| **批量生成** | 一键生成整月全部员工工资单并发送 |
| **历史记录** | 每一张工资单都留存，点开可看完整明细 |

## 为什么数字可信

计算引擎是**逐行复刻原 Excel 工作簿**，不是凭理解重写：

| Excel 列 | 含义 | 实现 |
|---|---|---|
| `H` | TOTAL 合计 | `底薪 − 无薪假 + A + B + C` |
| `AG/AH/AI` | 缴金基数 | `底薪 − 无薪假`（+ 你勾选计入的项目） |
| `I` / `J` | EPF 雇员 / 雇主 | `VLOOKUP(base, EPF!B15:F415, 5 / 4)` |
| `L` / `M` | SOCSO 雇员 / 雇主 | `VLOOKUP(base, SOCSOEIS!D7:J71, 5 / 4)` |
| `O` / `P` | EIS 雇员 / 雇主 | `VLOOKUP(base, SOCSOEIS!D7:J71, 7 / 6)` |
| `T` | NET 净工资 | `合计 − EPF − SOCSO − EIS − PCB − 预支` |

`VLOOKUP` 的近似匹配语义被完整还原：**取下限 ≤ 薪资基数的最后一行**。

移植结果用 **10 组标准向量**与原始 Python 引擎逐项比对，覆盖无薪假、
佣金、PCB、以及超过 EPF 上限的薪资 —— 每一个数字都对到分。

## 安装（安卓）

1. 下载 `PayslipGenerator.apk`
2. 在手机上打开，按提示允许「安装未知来源应用」
3. 启动 **Payslip Generator**

需要 Android 7.0 或更高（支持 arm64-v8a / armeabi-v7a / x86_64）。

## 快速上手

1. **设置 → 公司** —— 填公司名、地址、注册号，会印在每张工资单抬头
2. **设置 → 邮件** —— 填 SMTP 服务器与授权码。
   *Gmail / Outlook 必须用「应用专用密码」，不能用登录密码*
3. **设置 → 工资单 PDF 密码** —— 选规则（默认取 IC 后 6 位）。
   页面下方会实时显示示例，让你知道员工要输什么
4. **员工 → 新增** —— 录入你的员工
5. **首页 → 生成下个月工资** —— 一键生成全部工资单并发送。
   之后会进到一个列表，可以逐个查看、重发、分享

完整图文流程见 [使用教程](docs/USER-GUIDE.zh-CN.md)。

## 目录结构

```
payslip-app/                 安卓应用（Flutter）
├── lib/
│   ├── core/
│   │   ├── payroll.dart         计算引擎（对应 Excel 公式）
│   │   ├── rates.dart           EPF / SOCSO / EIS 查表
│   │   ├── payslip_pdf.dart     工资单 PDF 生成
│   │   ├── pdf_security.dart    PDF 标准安全处理器（RC4 128 位）
│   │   ├── database.dart        SQLite 表结构与数据访问
│   │   └── mail.dart            SMTP 发信
│   ├── screens/                 一个页面一个文件
│   ├── services.dart            业务规则（哪些项目启用等）
│   ├── theme.dart               设计系统
│   └── widgets.dart             共用组件
├── assets/                   EPF 与 SOCSO/EIS 费率表（来自工作簿）
└── test/                     32 项测试，含与电脑版的引擎一致性比对
```

## 测试

```bash
flutter test
```

覆盖：

- **引擎一致性** —— 10 组来自原始 Python 引擎的标准向量
- **PDF** —— 生成、加密、以及 `Sub-Total` / `Total Deductions` 不被截断
- **数据层** —— 设置持久化、归档而非删除、年份范围
- **业务规则** —— 邮件模板、配置校验、PDF 密码推导

## 从源码构建

见 [docs/BUILD.zh-CN.md](docs/BUILD.zh-CN.md)。简而言之：

```bash
flutter pub get
flutter build apk --release
```

发布构建**必须**有 `android/key.properties`。找不到时构建会**直接失败**，
而不是静默回退到调试签名 —— 避免你以为发的是正式版、实际发的是调试版。

## 已知限制

- **PDF 仅支持 ASCII 字符。** 内置 Helvetica / Times 是 Type1 + WinAnsi 编码，
  非 ASCII 字符（如中文）会被**静默丢弃**。当前业务只用拉丁字符姓名；
  若将来需要中文，需改为嵌入 TTF 字体，APK 体积约增加 10MB。
- **工资单在设备本地生成。** 除发送邮件外，全部功能离线可用。

## 授权

见 [LICENSE](LICENSE)。
