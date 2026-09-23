# User Guide

For the business owner using this app. No technical knowledge assumed.

---

## Contents

1. [Install](#1-install)
2. [First-time setup](#2-first-time-setup)
3. [Add your employees](#3-add-your-employees)
4. [Pay one employee](#4-pay-one-employee)
5. [Generate a whole month and send it](#5-generate-a-whole-month-and-send-it)
6. [Look up past payslips](#6-look-up-past-payslips)
7. [When someone leaves](#7-when-someone-leaves)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Install

1. Copy `PayslipGenerator.apk` to the phone (WhatsApp, USB cable, cloud — any way)
2. Tap the file on the phone
3. Android will say *unknown source*. Follow the prompt into Settings, allow
   installs from that source, then come back and continue
4. **Payslip Generator** appears in your app drawer

> The app calculates payroll offline. It only needs a network connection to
> send email.

---

## 2. First-time setup

There are five tabs along the bottom: **Home / Staff / Payroll / History /
Settings**.

Start with **Settings**, which has four sub-tabs.

### Company

Business name, address, registration number, phone, email.
These print at the top of every payslip.

Tap **Save** at the bottom right. The status on the left changes from
`Unsaved changes` to `All changes saved`.

### Payslip

Three optional earnings items — these correspond to columns **A / B / C** in
your Excel sheet.

```
Item name                    Show    EPF/SOCSO/EIS
──────────────────────────────────────────────────
[Item 3               ]       ☐           ☑
[Item 4               ]       ☐           ☑
[Item 5               ]       ☐           ☑
```

- **Item name** — rename it to whatever you call it, e.g. *Commission*
- **Show** — tick to make it appear on the payroll page and the payslip. All off by default
- **EPF/SOCSO/EIS** — tick if this amount should also be subject to EPF,
  SOCSO and EIS. Untick means the money is still paid, but no contributions
  are deducted on it

> Basic Salary always counts toward contributions, and Unpaid Leave always
> reduces them. Neither needs configuring.

### Rates

Normally leave these alone. Only change them if EPF changes its policy.

### Email

| Field | What to enter |
|---|---|
| SMTP server | `smtp.gmail.com` (Gmail) / `smtp-mail.outlook.com` (Outlook) |
| Port | 587 |
| Encryption | `STARTTLS (587)` |
| Server requires login | leave on |
| Username | your full email address |
| Password | **an app password** — see below |
| From name | what staff see, e.g. *79 Ling's Hair Studio* |
| From address | your email address |

> **You cannot use your normal email password.**
> Gmail and Outlook both require an *app password*.
> In Gmail: *Google Account → Security → 2-Step Verification → App passwords*.
> Without this, sending fails with `Authentication failed`.

Tap **Save and test connection** to check it works before relying on it.

### Payslip PDF password

Pick one rule:

- **Last 6 digits of IC** (recommended) — staff open with the last 6 digits
- Last 4 digits of IC
- Full IC number (digits only)
- No password

The screen shows a live example:

```
🔒 Example — IC 900101-14-0001  →  password 141234
```

Hyphens are **not** counted — digits only. If an employee has no IC on file, or
it is too short, their payslip is sent unencrypted (the batch run tells you how
many that affected).

---

## 3. Add your employees

Tap **Staff** → **Add**.

Two required fields:

- **Employee Name**
- **Basic Salary (RM)**

Fill in **Email** too — without it the app cannot send them anything. The list
flags anyone missing an email with a yellow `no email` chip.

Everything else is optional: IC number, employee ID, job title, department,
EPF/SOCSO/EIS numbers, bank account.

Tap **SAVE** in the top right.

---

## 4. Pay one employee

Tap **Payroll**.

1. Choose **Employee**, **Month** and **Year** at the top
2. Fill in the amounts:

```
Earnings & Deductions
  Basic Salary *        RM 1700.00
  Less: Unpaid Leave    RM
  Income Tax (PCB)      RM 12.00
  Advance to Staff      RM
```

3. The result updates **as you type**:

```
Auto calculation
  Total Salary              1,700.00
  Contribution base         1,700.00
  ─────────────────────────────────
  EPF (Employee)             −187.00
  SOCSO (Employee)            −20.60
  EIS (Employee)               −3.30
  Income Tax (PCB)            −12.00
  ─────────────────────────────────
  Employer EPF                221.00
  Employer SOCSO               28.85
  Employer EIS                  3.30
  ─────────────────────────────────
  NET SALARY              RM 1,477.10
```

> Employer contributions are **not** deducted from the employee's pay. They are
> shown so you know what the business owes.

4. Two buttons at the bottom:

| Button | What it does |
|---|---|
| **Save only** | Stores the record, no PDF |
| **Save & Payslip** | Stores the record **and** opens the PDF |

### The preview screen

```
Payslip_Ahmad_bin_Ali_October_2026.pdf
🔒 The preview below is unprotected so you can read it.
   Ahmad bin Ali gets this file protected with password: 141234
   ┌────────────────────────────────────┐
   │  Email to ahmad@example.com   │
   └────────────────────────────────────┘
   [ Share protected ]  [ Unprotected ]
```

- The banner tells you what staff will need to type. **You** are looking at an
  unencrypted copy, which is why you can always check your own work
- **Email to ...** sends it straight to that employee
- **Share protected** shares the encrypted file (WhatsApp, cloud, anything)
- **Unprotected** shares the open version — rarely needed

---

## 5. Generate a whole month and send it

Go back to **Home** and tap this card:

```
⚡ Generate October 2026 payroll
   All 2 employee(s), then email each payslip          ›
```

The month is **automatically the next one** (September now → October).

The batch screen opens pre-configured:

- Month = October, Year = 2026
- Every employee ticked
- *Also email each payslip* already on
- The button reads `Generate & Send (2)`

Tap it, confirm the count, then **Send**.

> **Anyone already emailed this period is left unticked**, so nobody gets the
> same payslip twice. A row showing `Sent 2026-09-23` was already sent.

### The result list

```
October 2026
2 payslip(s) generated  ·  2 emailed
Tap any row to view, email or share that payslip.
─────────────────────────────────────────────────
📧 Ahmad bin Ali     RM 1,489.10
   Emailed to ahmad@example.com              ›
📧 Priya Ramasamy                 RM 1,926.80
   Emailed to priya@example.com                  ›
─────────────────────────────────────────────────
[ Done ]
```

- Green 📧 means it went out
- Red ⚠ means it failed, with the reason underneath
- **Tap any row** to open that payslip and resend or share it individually

> If someone's email was wrong, fix it in Staff and resend just that one row —
> you do not have to re-run the batch.

---

## 6. Look up past payslips

Tap **History**. Records are grouped by month:

```
October 2026                        2 record(s)
  Ahmad bin Ali  A01   RM 1,489.10  ›
  Priya Ramasamy              A02   RM 1,926.80  ›
September 2026                      1 record(s)
  Ahmad bin Ali  A01   RM 1,607.40  ›
```

**Tap a row** for the full breakdown:

```
Ahmad bin Ali
September 2026  ·  A01
──────────────────────────────
Earnings
  Basic Salary          1,700.00
  Item A                  150.00
  Total Salary          1,850.00
Deductions (employee)
  EPF                    −205.00
  SOCSO                   −21.90
  EIS                      −3.70
  Income Tax (PCB)        −12.00
  NET SALARY            1,607.40
Employer contributions
  EPF 239.00 · SOCSO 30.70 · EIS 3.70
──────────────────────────────
[ View PDF ]   🗑
```

History shows the **stored figures** — they do not change if you later edit your
settings. A payslip already sent to an employee should never silently change.

---

## 7. When someone leaves

Tap **⋮** next to the employee → **Archive**.

- They move to *Archived* and drop out of the payroll list
- **All payroll records are kept.** Wage records are statutory documents
- **Restore** brings them back at any time

To erase someone completely (say you entered them by mistake), choose
**Delete permanently**. You must type `DELETE` to confirm, because this wipes
their history too and cannot be undone.

Tap **Show archived** above the list to see archived staff.

---

## 8. Troubleshooting

**`Authentication failed` when sending**
You used your email login password. Gmail and Outlook require an *app
password* — generate one in the email account's security settings.

**`Connection refused` when sending**
Wrong SMTP host or port. For Gmail: `smtp.gmail.com`, port `587`, encryption
`STARTTLS (587)`.

**An employee cannot open the attachment**
The payslip is encrypted. Tell them to use the **last 6 digits of their IC**
(hyphens excluded). The exact password is shown on the preview screen — you can
send it to them directly.

**A name is missing characters**
The PDF fonts cover Latin characters only. Names containing Chinese would lose
those characters. Supporting CJK means embedding a font — contact the developer.

**I cannot find the year I need**
The list covers a range around the current year, plus any year you already have
records for. Create one record in that year and it will appear.

**Will I lose data if I change phones?**
Yes — data is stored on the device. Ask the developer to export it before you
switch.

**What is Sub-Total?**
Total earnings on the left. Total employee deductions on the right.
Net salary = earnings − deductions.
