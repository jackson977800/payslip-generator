# Building from source

[中文 →](BUILD.zh-CN.md)

---

## Requirements

| | Version |
|---|---|
| Flutter | 3.35 or newer (developed on 3.47) |
| JDK | 17 |
| Android SDK | Platform 36, Build-Tools 36, Platform-Tools |
| Android NDK | 28.2.13676358 (or whatever `flutter doctor` reports) |

Run `flutter doctor` and make sure the Android toolchain shows a green tick.

## 1. Get the dependencies

```bash
flutter pub get
```

## 2. Create a release keystore

**Do this once, and back the file up.** Android uses this key to prove that
future updates come from you. If you lose it you can never update an installed
app — users would have to uninstall and lose their data.

```bash
keytool -genkeypair \
  -keystore /path/to/payslip-release.jks \
  -alias payslip \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Your Company, OU=Payslip Generator, O=Your Company, L=City, ST=State, C=MY"
```

Store the keystore **outside the repository**. Then create
`android/key.properties`:

```properties
storePassword=<your password>
keyPassword=<your password>
keyAlias=payslip
storeFile=/absolute/path/to/payslip-release.jks
```

`android/.gitignore` already excludes `key.properties`, `*.jks` and
`*.keystore`. The root `.gitignore` repeats those rules as a safety net.

> The release build **fails on purpose** if `key.properties` is missing. It will
> not quietly fall back to debug signing — that would produce an APK that cannot
> be installed over a properly signed one.

## 3. Build

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

For smaller per-architecture APKs (roughly 40 % smaller each):

```bash
flutter build apk --release --split-per-abi
```

## 4. Verify the build

Never ship an APK without checking what was actually built.

```bash
# Signature — must NOT say "Android Debug"
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk

# Permissions and target architectures
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | \
  grep -E "^package|application-label|native-code"
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

Expected:

- Signer DN shows your organisation, not `CN=Android Debug`
- `uses-permission: android.permission.INTERNET` is present
- `native-code` lists `arm64-v8a`, `armeabi-v7a`, `x86_64`

## 5. Run the tests

```bash
flutter test
```

32 tests. The important one is *engine parity* — it replays 10 reference vectors
taken from the original Python engine and asserts every figure matches to the
cent. If you touch `lib/core/payroll.dart` or `lib/core/rates.dart`, this is the
test that catches a mistake.

## Environment gotchas

These cost real time when setting this up. Writing them down so they do not
cost it again.

### `flutter test` fails with `WebSocketException: Invalid WebSocket upgrade request`

A proxy is intercepting the test harness's **local** WebSocket. It looks like
every test in the suite broke at once. Clear the proxy variables:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
    "NO_PROXY=localhost,127.0.0.1" flutter test
```

### Flutter needs `%PROGRAMFILES(X86)%`

On Windows, if the shell does not define it:

```bash
env "PROGRAMFILES(X86)=C:\Program Files (x86)" flutter test
```

Bash cannot `export` a name containing parentheses.

### `flutter create` treats `/c/foo` as a relative path

It creates `C:\Users\<you>\c\foo`. Use a Windows-style path instead:

```bash
flutter create "C:/payslip-app"
```

### Keep the project path free of spaces

Gradle and the Android toolchain handle spaces poorly. `C:\payslip-app` is a
safe choice; a path like `C:\Users\me\My Projects\app` may break the build.

## Project structure notes

- **`assets/`** holds `epf_table.json` and `socso_eis_table.json`, extracted from
  the reference Excel workbook. If the statutory tables change, update these.
- **`lib/core/payroll.dart`** must stay in step with the desktop app's engine.
  Any change there needs the parity vectors re-verified.
- **`lib/core/pdf_security.dart`** implements the PDF standard security handler
  from scratch, because the `pdf` package ships only the abstract interface.
  Two details are easy to get wrong and both are commented in the file:
  dictionary keys must carry their leading `/`, and the encryption key must be
  derived from `PdfDocument.documentID` so it matches the trailer.
