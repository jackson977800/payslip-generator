# Payslip Generator

A Malaysian payroll app for small businesses — computes **EPF / SOCSO / EIS**,
generates password-protected payslip PDFs, and emails them to staff.

Ships as an **Android app** and a **Windows desktop app**. Both share the same
calculation engine and produce identical numbers.

[中文说明 →](README.zh-CN.md)

---

## What it does

| | |
|---|---|
| **Employees** | Store staff details — NRIC, EPF/SOCSO/EIS numbers, bank account, email |
| **Payroll entry** | Enter basic salary, unpaid leave, up to three extra items, PCB and advance. EPF / SOCSO / EIS are looked up automatically |
| **Payslip PDF** | One-page A4 payslip matching the original Excel template, optionally password-protected |
| **Email** | Send each employee their own payslip, password derived from their IC number |
| **Batch** | Generate a whole month for every employee in one tap, then email them all |
| **History** | Every payslip is kept. Open any record to see the full breakdown |

## Why the numbers are trustworthy

The calculation engine is a **line-by-line port of the reference Excel
workbook**, not a reimplementation:

| Excel column | Meaning | Implemented as |
|---|---|---|
| `H` | TOTAL | `Basic − UnpaidLeave + A + B + C` |
| `AG/AH/AI` | Contribution bases | `Basic − UnpaidLeave` (+ items you tick) |
| `I` / `J` | EPF employee / employer | `VLOOKUP(base, EPF!B15:F415, 5 / 4)` |
| `L` / `M` | SOCSO employee / employer | `VLOOKUP(base, SOCSOEIS!D7:J71, 5 / 4)` |
| `O` / `P` | EIS employee / employer | `VLOOKUP(base, SOCSOEIS!D7:J71, 7 / 6)` |
| `T` | NET | `TOTAL − EPF − SOCSO − EIS − PCB − Advance` |

`VLOOKUP` approximate-match semantics are reproduced exactly: take the **last
row whose lower bound is ≤ the base**.

The port is verified against the original Python engine on **10 reference
vectors** covering unpaid leave, commission, PCB, and salaries above the EPF
ceiling — every figure matches to the cent.

## Install (Android)

1. Download `PayslipGenerator.apk`
2. Open it on the phone and allow *Install unknown apps* when prompted
3. Launch **Payslip Generator**

Requires Android 7.0 or newer (arm64-v8a / armeabi-v7a / x86_64).

## Quick start

1. **Settings → Company** — enter your business name, address and registration
   number. This appears at the top of every payslip.
2. **Settings → Email** — enter your SMTP details and an app password.
   *Gmail and Outlook require an app password, not your normal login password.*
3. **Settings → Payslip PDF password** — pick the rule (default: last 6 digits
   of IC). The app shows an example so you can see what staff will need to type.
4. **Staff → Add** — add your employees.
5. **Home → Generate <next month> payroll** — one tap generates every payslip
   and emails them. You then get a list where you can review, resend or share
   each one individually.

See the [User Guide](docs/USER-GUIDE.md) for a walkthrough with every screen.

## Project layout

```
payslip-app/                 Flutter app (Android)
├── lib/
│   ├── core/
│   │   ├── payroll.dart         Calculation engine (mirrors the Excel formulas)
│   │   ├── rates.dart           EPF / SOCSO / EIS table lookup
│   │   ├── payslip_pdf.dart     PDF generation
│   │   ├── pdf_security.dart    PDF standard security handler (RC4 128-bit)
│   │   ├── database.dart        SQLite schema and data access
│   │   └── mail.dart            SMTP
│   ├── screens/                 One file per screen
│   ├── services.dart            Business rules (which items are enabled, etc.)
│   ├── theme.dart               Design system
│   └── widgets.dart             Shared widgets
├── assets/                      EPF and SOCSO/EIS rate tables (from the workbook)
└── test/                        32 tests, including engine parity with the desktop app
```

## Testing

```bash
flutter test
```

Covers:

- **Engine parity** — 10 reference vectors taken from the original Python engine
- **PDF** — generation, encryption, and that `Sub-Total` / `Total Deductions`
  are not clipped
- **Data layer** — settings persistence, archive-not-delete, year ranges
- **Business rules** — email templates, config validation, PDF password derivation

## Building

See [docs/BUILD.md](docs/BUILD.md). In short:

```bash
flutter pub get
flutter build apk --release
```

The release build **requires** `android/key.properties`. It deliberately fails
rather than silently falling back to debug signing.

## Known limitations

- **ASCII only in PDFs.** The built-in Helvetica / Times fonts are Type1 +
  WinAnsi, so non-ASCII characters (e.g. Chinese) are silently dropped. The
  current deployment uses Latin names only; supporting CJK would mean embedding
  a TTF, adding roughly 10 MB to the APK.
- **Payslips are generated on-device.** The app works offline except for sending
  email.

## Licence

See [LICENSE](LICENSE).
