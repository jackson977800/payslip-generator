# Payslip Generator 工资单生成器

面向马来西亚小型企业的算薪工具 —— 自动计算 **EPF / SOCSO / EIS**，
生成带密码保护的工资单 PDF，并直接邮件发给员工。

**简体中文** · [English](docs/README.en.md)

---

## 各端状态

| 端 | 界面 | 状态 |
|---|---|---|
| Android | Flutter | ✅ 已发布 — 1.0.0 |
| Windows | PySide6 | ✅ 已发布 — 参考实现 |

安卓版是 Windows 版的移植。两者共用同一套计算引擎，算出的数字完全一致。

## 下载

### ➡️ [**前往 Releases 页面下载**](https://github.com/jackson977800/payslip-generator/releases/latest)

| 端 | 文件 | 说明 |
|---|---|---|
| Android | `PayslipGenerator-1.0.0-android.apk` | Android 7.0+ · arm64-v8a / armeabi-v7a / x86_64 |
| Windows | `Payslip-1.0.0-windows.exe` | 免安装单文件，双击即用 |

**安卓安装**：把 APK 传到手机 → 点开 → 按提示允许「安装未知来源应用」

**Windows**：双击 `Payslip-1.0.0-windows.exe` 直接运行。
无需安装 Python 或任何依赖，不写注册表，删除文件即卸载。

> 两个成品都经过验证：APK 用正式发布密钥签名（非调试密钥）；
> EXE 的**冻结构建**跑过 77 项自检 —— 构建日志绿不代表能跑，
> 只有打包后的 .exe 本身跑通才算数。

## 功能

| 功能 | 说明 | Android | Windows |
|---|---|---|---|
| 员工档案 | IC、EPF/SOCSO/EIS 编号、银行账户、邮箱 | ✅ | ✅ |
| 工资录入 | 底薪、无薪假、最多 3 个额外项、PCB、预支 | ✅ | ✅ |
| EPF / SOCSO / EIS | 法定费率表，复刻 `VLOOKUP` 近似匹配语义 | ✅ | ✅ |
| 工资单 PDF | 单页 A4，版式与原 Excel 模板一致 | ✅ | ✅ |
| PDF 加密 | RC4 128 位 · 允许打印、禁止复制与修改 | ✅ | ✅ |
| 邮件发送 | SMTP，支持 STARTTLS / SSL / 不加密，每人一封 | ✅ | ✅ |
| 批量生成 | 一键生成整月全部员工 | ✅ | — |
| 逐人结果列表 | 可单独查看、重发、分享每一份 | ✅ | — |
| 历史记录 | 按月份分组，点开看完整明细 | ✅ | ✅ |
| 员工归档 | 保留工资历史（法定留存） | ✅ | ✅ |
| 自定义收入项 | 控制显示 / 隐藏，以及是否计入缴金基数 | ✅ | ✅ |

✅ 可用 · — 该端不适用

## 界面预览

### 首页

![首页](docs/images/screenshots/01-home.png)

本月概览，以及一键生成下月全部员工工资单的入口。

### 算薪

![算薪](docs/images/screenshots/02-payroll.png)

输入即算。员工扣款项带负号，雇主缴纳部分弱化显示 ——
避免被误当成从工资里扣的钱。

### 工资单 PDF

![PDF 预览](docs/images/screenshots/03-pdf-preview.png)

**你看到的预览是不加密的**，所以随时能核对。上方说明条写明了员工端
需要的密码，而你发出去的附件是加密的。

### 批量结果

![批量结果](docs/images/screenshots/04-batch-result.png)

批量跑完给你一份逐人列表，而不是一个文件路径 ——
Android 上应用私有目录用文件管理器根本进不去，路径等于没说。

### 历史明细

![历史明细](docs/images/screenshots/05-history-detail.png)

点任意一条看完整拆分。数字用的是**当时存档的值**，
不会因为你后来改了设置而变化。

## 为什么数字可信

计算引擎是**逐行复刻原 Excel 工作簿**，不是凭理解重写。

| Excel 列 | 含义 | 实现 |
|---|---|---|
| `H` | TOTAL 合计 | `底薪 − 无薪假 + A + B + C` |
| `AG/AH/AI` | 缴金基数 | `底薪 − 无薪假`（+ 你勾选计入的项目） |
| `I` / `J` | EPF 雇员 / 雇主 | `VLOOKUP(base, EPF!B15:F415, 5 / 4)` |
| `L` / `M` | SOCSO 雇员 / 雇主 | `VLOOKUP(base, SOCSOEIS!D7:J71, 5 / 4)` |
| `O` / `P` | EIS 雇员 / 雇主 | `VLOOKUP(base, SOCSOEIS!D7:J71, 7 / 6)` |
| `T` | NET 净工资 | `合计 − EPF − SOCSO − EIS − PCB − 预支` |

`VLOOKUP` 的近似匹配语义被完整还原：**取下限 ≤ 薪资基数的最后一行**。

移植结果用 **10 组标准向量**与原始 Python 引擎逐项比对，
覆盖无薪假、佣金、PCB、以及超过 EPF 上限的薪资 —— 每个数字都对到分。

## 目录结构

```
payslip-app/
├── lib/
│   ├── core/
│   │   ├── payroll.dart         计算引擎（对应 Excel 公式）
│   │   ├── rates.dart           EPF / SOCSO / EIS 查表
│   │   ├── payslip_pdf.dart     工资单 PDF 生成
│   │   ├── pdf_security.dart    PDF 标准安全处理器（RC4 128 位）
│   │   ├── database.dart        SQLite 表结构与数据访问
│   │   └── mail.dart            SMTP 发信
│   ├── screens/                 一个页面一个文件
│   ├── services.dart            业务规则
│   ├── theme.dart               设计系统
│   └── widgets.dart             共用组件
├── assets/                      EPF 与 SOCSO/EIS 费率表
├── docs/
│   ├── README.en.md             英文说明
│   ├── USER-GUIDE.zh-CN.md      使用教程
│   ├── BUILD.zh-CN.md           构建与签名
│   └── images/screenshots/      界面截图
└── test/                        32 项测试
```

## 测试

```bash
flutter test
```

| 范围 | 断言内容 |
|---|---|
| 引擎一致性 | 10 组来自原始 Python 引擎的标准向量，逐项对到分 |
| PDF | 生成、加密、以及 `Sub-Total` / `Total Deductions` 不被截断 |
| 数据层 | 设置持久化、归档而非删除、年份范围 |
| 业务规则 | 邮件模板、配置校验、PDF 密码推导 |

## 从源码构建

见 [构建指南](docs/BUILD.zh-CN.md)。

```bash
flutter pub get
flutter build apk --release
```

发布构建**必须**有 `android/key.properties`，找不到会**直接失败**，
而不是静默回退到调试签名。

## 文档

| 文档 | 面向 |
|---|---|
| [使用教程](docs/USER-GUIDE.zh-CN.md) | 使用这个 App 的老板 |
| [构建指南](docs/BUILD.zh-CN.md) | 从源码构建与签名 |
| [更新日志](CHANGELOG.md) | 版本变更 |
| [English docs](docs/README.en.md) | English readers |

## 免责声明

- **与 EPF / SOCSO / EIS 官方机构无关联。** 费率表转录自参考工作簿。
  用于法定申报前，请与官方费率表核对。
- **数据只存在设备本地。** 没有服务器、没有遥测。
  换手机前必须先导出数据，否则会丢。
- **PDF 仅支持 ASCII 字符。** 内置 Helvetica / Times 是 Type1 + WinAnsi 编码，
  非 ASCII 字符（如中文）会被**静默丢弃**。当前业务只用拉丁字符姓名；
  若需要中文，需改为嵌入 TTF 字体，APK 体积约增加 10MB。
- **APK 仅 v2 签名方案。** `minSdk >= 24` 时这是正确做法。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
