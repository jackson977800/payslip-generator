# -*- coding: utf-8 -*-
"""独立验证 Flutter 版生成的工资单 PDF。

关键点：不是「文件里有没有 /Encrypt」，而是**用独立实现真的去解密**，
确认无密码/错密码打不开、正确密码能打开，并核对权限位。
"""
import os
import sys

from pypdf import PdfReader
from pypdf.constants import UserAccessPermissions

PLAIN = r"C:\payslip-app\build\pdf_out\plain.pdf"
ENC = r"C:\payslip-app\build\pdf_out\enc.pdf"

ok = True


def check(name, cond, detail=""):
    global ok
    print(("[ OK ] " if cond else "[FAIL] ") + name
          + ("  " + str(detail) if detail else ""))
    if not cond:
        ok = False


for f in (PLAIN, ENC):
    if not os.path.exists(f):
        print("缺少文件:", f)
        sys.exit(1)

print("--- 明文 PDF ---")
r = PdfReader(PLAIN)
check("页数为 1", len(r.pages) == 1, len(r.pages))
check("未加密", not r.is_encrypted)
text = r.pages[0].extract_text() or ""
check("含公司名", "Demo Salon Sdn Bhd" in text)
check("含员工姓名", "Ahmad bin Ali" in text)
check("含 NET SALARY", "NET SALARY" in text)
check("含净工资 1,489.10", "1,489.10" in text)

print()
print("--- 加密 PDF（用户密码 141234）---")
r2 = PdfReader(ENC)
check("标记为已加密", r2.is_encrypted)
check("未解密前读不出内容", r2.pages[0].extract_text() in (None, ""))

wrong = PdfReader(ENC)
res_wrong = wrong.decrypt("000000")
check("错密码解密失败", not res_wrong, res_wrong)

good = PdfReader(ENC)
res_good = good.decrypt("141234")
check("正确密码解密成功", bool(res_good), res_good)
if res_good:
    t = good.pages[0].extract_text() or ""
    check("解密后可读出公司名", "Demo Salon Sdn Bhd" in t)
    check("解密后可读出净工资", "1,489.10" in t)
    perms = good.user_access_permissions
    check("允许打印", bool(perms & UserAccessPermissions.PRINT), perms)
    check("禁止复制内容",
          not bool(perms & UserAccessPermissions.EXTRACT), perms)
    check("禁止修改",
          not bool(perms & UserAccessPermissions.MODIFY), perms)

print()
print("RESULT:", "ALL PASS" if ok else "HAS FAILURES")
sys.exit(0 if ok else 1)
