# คู่มือ

[English](manual.en.md) · [README](../README.md)

## ขั้นตอน

| ขั้น | พิมพ์ | Claude ทำ | คุณตอบ |
|---|---|---|---|
| 0 | `/setup-flow` (ครั้งเดียวต่อ repo) | สร้าง `.claude/issue-flow.json` เช็ก server, label, คำสั่ง test และ token | reviewer, label, คำสั่ง |
| 1 | `/plan-issue 766` | อ่าน issue, comment และโค้ด เขียนแผนไว้ใน `.git/claude-flow/` ไม่แก้อะไร | อนุมัติ / แก้ / ยกเลิก |
| 2 | `/implement` | label In progress, สร้าง branch, Draft MR (GitLab) แล้วเขียนโค้ดและ test ตามแผน | เริ่ม / ยกเลิก |
| 3 | `/submit-review` | รีวิวตัวเอง รัน test commit push แล้วเปิด MR / PR หรือเปลี่ยนเป็นพร้อมรีวิว | ส่งเลย / Draft แล้วยืนยัน |
| 4 | `/fix-review` (ถ้าโดน reject) | อ่าน comment ที่ค้าง กลับเป็น Draft แล้วแก้ทีละข้อ | ยืนยัน |

ถ้าติดตั้งเป็น plugin ชื่อคำสั่งจะขึ้นต้นด้วย `issue-flow:` เช่น `/issue-flow:plan-issue 766`

ตัวเลือก: `/implement 766 setup` เตรียม branch แล้วให้คุณเขียนโค้ดเอง · `/submit-review draft` push แต่ยังไม่ขอรีวิว · `/merge-base` ดึง branch หลักเข้ามาในเครื่อง

## Claude ทำอะไรได้บ้าง

| | |
|---|---|
| อ่าน issue, โค้ด, diff | ไม่ต้องถาม |
| แก้โค้ด, commit, push, label, MR / PR | หลังคุณยืนยันเท่านั้น |
| `--force`, `--no-verify`, merge MR / PR, ส่งข้อความหาคน | ไม่ทำ |

ผลรีวิวและผล test ใช้ได้เฉพาะกับโค้ดชุดนั้น commit แล้วยังใช้ได้ แต่แก้โค้ดเมื่อไหร่ต้องทำใหม่

## กฎคุณภาพของ `/implement`

1. แก้ที่ต้นเหตุ ไม่ใช่อาการ
2. แก้ให้น้อยที่สุดตามแผน
3. ตรวจ input ที่ขอบระบบ
4. ทดสอบที่พฤติกรรม งานบั๊กเขียน test ที่พังก่อน
5. ทำทีละข้อของแผนแล้วรัน test
6. ตรวจกับของจริงก่อนบอกว่าเสร็จ ถ้าทำไม่ได้ต้องบอก
7. อ่าน diff ตัวเองรอบสุดท้าย

ถ้ามี plugin [superpowers](https://github.com/obra/superpowers) Claude จะใช้ skill ด้าน TDD, debug และการตรวจก่อนจบด้วย ถ้าขัดกันให้ยึดกฎข้างบน

## Test

| ภาษา / เครื่องมือ | รู้จาก | รัน test ที่เกี่ยวข้องด้วย |
|---|---|---|
| Maven, Gradle | `pom.xml`, `build.gradle(.kts)` | `-Dtest=…`, `--tests` |
| Node | `package.json` | Vitest, Jest หรือ Mocha เฉพาะไฟล์ที่ตรงกัน |
| Python | `pyproject.toml`, `pytest.ini`, `setup.py`, `requirements.txt` | `pytest` เฉพาะไฟล์ที่ตรงกัน |
| Go | `go.mod` | `go test` เฉพาะ package ที่แก้ |
| .NET | `*.csproj`, `*.sln` | `dotnet test --filter` |
| PHP, Ruby | `composer.json`, `Gemfile` | PHPUnit, RSpec |
| Rust | `Cargo.toml` | `cargo test` (ทั้งหมด) |

ไฟล์ที่แก้จะนับเป็นของโฟลเดอร์ใกล้สุดที่มีไฟล์ build ดังนั้น repo ที่มีหลายภาษาจะได้หลายชุด อยากใช้คำสั่งของทีมเอง ใส่ `tests.related`, `tests.all`, `tests.issue` ใน `issue-flow.json`

## แก้ปัญหา

| อาการ | ทำ |
|---|---|
| `No token for <host>` | รัน `set-token` (ดู README) |
| `401` | token หมดอายุหรือถูกยกเลิก สร้างใหม่แล้วรัน `set-token` ซ้ำ |
| `403` / `404` บน GitHub | token ไม่มีสิทธิ์ใน repo นี้ หรือขาดสิทธิ์ Contents, Issues, Pull requests |
| `422` ตอนเปิด Draft บน GitHub | แพ็กเกจของคุณไม่มี Draft PR สำหรับ repo นี้ ใช้ `/submit-review` โดยไม่ใส่ `draft` |
| `User @x not found` | ใช้ username ไม่ใช่ชื่อที่แสดง |
| `The issue is on … but this repo uses …` | เปิด Claude ใน repo ของ issue นั้น |
| รู้ชนิด server ผิด | ตั้ง `provider` ใน `issue-flow.json` |
