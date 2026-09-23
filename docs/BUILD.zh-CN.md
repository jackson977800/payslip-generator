# 从源码构建

[English →](BUILD.md)

---

## 环境要求

| | 版本 |
|---|---|
| Flutter | 3.35 以上（开发环境为 3.47） |
| JDK | 17 |
| Android SDK | Platform 36、Build-Tools 36、Platform-Tools |
| Android NDK | 28.2.13676358（以 `flutter doctor` 报告的为准） |

先跑 `flutter doctor`，确认 Android toolchain 是绿勾。

## 1. 拉依赖

```bash
flutter pub get
```

## 2. 生成发布签名密钥

**只做一次，并且务必把文件备份好。** Android 用这个密钥证明「新版本确实
出自同一个开发者」。密钥一旦丢失，你将**永远无法**为已安装的 App 发布更新 ——
用户只能卸载重装，本地数据全部丢失。

```bash
keytool -genkeypair \
  -keystore /path/to/payslip-release.jks \
  -alias payslip \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Your Company, OU=Payslip Generator, O=Your Company, L=City, ST=State, C=MY"
```

把 keystore 放在**仓库之外**。然后创建 `android/key.properties`：

```properties
storePassword=<你的口令>
keyPassword=<你的口令>
keyAlias=payslip
storeFile=/绝对路径/payslip-release.jks
```

`android/.gitignore` 已经排除了 `key.properties`、`*.jks`、`*.keystore`，
根目录 `.gitignore` 又重复了一遍作为保险。

> 缺少 `key.properties` 时，release 构建会**故意失败**，而不是静默回退到
> 调试签名 —— 那样产出的 APK 无法覆盖安装到已正确签名的应用上。

## 3. 构建

```bash
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

如果要按 CPU 架构拆分（每个约小 40%）：

```bash
flutter build apk --release --split-per-abi
```

## 4. 验证产物

发布前一定要确认「实际构建出来的东西」是什么。

```bash
# 签名 —— 必须不是 "Android Debug"
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk

# 权限与支持的 CPU 架构
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | \
  grep -E "^package|application-label|native-code"
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

预期结果：

- 签名者 DN 显示你的公司名，**不是** `CN=Android Debug`
- 存在 `uses-permission: android.permission.INTERNET`
- `native-code` 列出 `arm64-v8a`、`armeabi-v7a`、`x86_64`

## 5. 跑测试

```bash
flutter test
```

共 32 项。其中最重要的是**引擎一致性** —— 它会重放 10 组来自原始 Python
引擎的标准向量，逐项断言每一个数字都对到分。改动
`lib/core/payroll.dart` 或 `lib/core/rates.dart` 后，这个测试就是防线。

## 环境坑（都实际踩过）

### `flutter test` 报 `WebSocketException: Invalid WebSocket upgrade request`

代理拦截了测试框架的**本地** WebSocket。症状看起来像「所有测试一起挂了」。
清掉代理变量：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    "NO_PROXY=localhost,127.0.0.1" flutter test
```

### Flutter 需要 `%PROGRAMFILES(X86)%`

Windows 上如果 shell 里没有这个变量：

```bash
env "PROGRAMFILES(X86)=C:\Program Files (x86)" flutter test
```

bash 无法 `export` 带括号的变量名。

### `flutter create` 会把 `/c/foo` 当成相对路径

实际创建在 `C:\Users\<你>\c\foo`。要用 Windows 风格路径：

```bash
flutter create "C:/payslip-app"
```

### 项目路径不要有空格

Gradle 与 Android 工具链对空格处理很差。`C:\payslip-app` 是安全的；
像 `C:\Users\me\My Projects\app` 这种可能直接构建失败。

## 代码结构说明

- **`assets/`** 放 `epf_table.json` 与 `socso_eis_table.json`，
  从参考 Excel 工作簿提取。法定费率表变动时更新这两个文件。
- **`lib/core/payroll.dart`** 必须与电脑版引擎保持一致。
  任何改动都要重跑一致性向量。
- **`lib/core/pdf_security.dart`** 是从零实现的 PDF 标准安全处理器，
  因为 `pdf` 包只提供了抽象接口。有两处极易写错，文件里都有注释：
  字典的键必须带前导 `/`；加密密钥必须由 `PdfDocument.documentID` 推导，
  才能与 trailer 里的 `/ID` 对上。
