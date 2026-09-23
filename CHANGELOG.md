# Changelog

All notable changes to this project.

## [1.0.0] — 2026-09-23

First production release. Signed with a release keystore.

### Core

- **Calculation engine** — EPF / SOCSO / EIS via the statutory tables, with
  `VLOOKUP` approximate-match semantics reproduced exactly. Verified against the
  desktop engine on 10 reference vectors, matching to the cent.
- **Payslip PDF** — single-page A4 matching the original Excel template.
- **PDF encryption** — standard security handler (RC4 128-bit) implemented from
  scratch, since the `pdf` package ships only the abstract interface.
  Verified with two independent implementations: Qt's PDF engine and `pypdf`.
  Allows printing, blocks copying and modification.
- **Email** — SMTP with STARTTLS / SSL / none. One message per recipient,
  personalised subject and body, encrypted payslip attached.
- **Storage** — SQLite, schema-compatible with the desktop app.

### Screens

- Home — month KPIs, one-tap batch generation
- Staff — search, archive/restore, missing-email warnings
- Payroll — live calculation panel, net salary highlighted
- History — grouped by month, tap for the full breakdown
- Settings — company / payslip items / rates / email, sticky save bar
- Batch — select a period, generate, then a per-employee result list

### Fixed during development

- **Re-saving an old period could silently erase a stored extra item.** The
  `Show` checkbox hides that field on the Payroll page, and the calculation
  zeroes disabled items. Because the record stores the *computed* values,
  opening an old period and pressing Save wiped a commission that had been
  entered while the item was enabled. `saveRun` now preserves a non-zero stored
  value when the item is currently hidden — the user cannot have edited a field
  they cannot see. Four tests cover this.
- **Release APKs had no `INTERNET` permission.** Flutter's template declares it
  only under `src/debug` and `src/profile`. Without it every email fails on a
  release build.
- **The Settings save button was unreachable.** It sat at the bottom of a long
  scrolling list; scrolling was unreliable once a text field had focus. Moved to
  a fixed bottom bar and split the page into four sub-tabs.
- **Payslip PDFs could not be opened by the sender.** Only the encrypted copy was
  generated, so the owner hit *Password required* on their own payslip. Now two
  copies are produced: an unprotected one for previewing, an encrypted one for
  sending.
- **Shared files were named `document.pdf`.** The `PdfPreview` widget's built-in
  share button hard-codes that name. Replaced with our own share action that
  passes the real filename.
- **`Sub-Total` was clipped to `Sub-`.** The `pdf` package cannot span table
  columns, and the label sat in the narrowest one.
- **Deleting an employee destroyed their payroll history.** Now archived
  instead — wage records are statutory documents. Permanent deletion requires
  typing `DELETE` to confirm.
- **The year dropdown stopped at next year.** Now covers a range around the
  current year, merged with any year that already has records.
- **Generating a payslip did not create a history entry.** Only *Save* did, which
  made it look like the PDF button was broken.
- **`Sub-Total` / totals were unreadable in the batch summary.** Replaced the
  "saved to &lt;path&gt;" dialog with a per-employee result list — an app-private
  path is useless on Android, since no file manager can open it.

### Known limitations

- **PDFs are ASCII-only.** Built-in Helvetica / Times are Type1 + WinAnsi, so
  non-ASCII characters are silently dropped. Supporting CJK would require
  embedding a TTF, adding roughly 10 MB.
- **v2-only APK signature.** Correct for `minSdk >= 24`; the build does not
  produce a v1 (JAR) signature.
