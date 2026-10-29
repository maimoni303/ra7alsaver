# RA7AL Files Downloader

![RA7AL Files Downloader](docs/brand/ra7al_saver_logo.gif)

[![Build](../../actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/maimoni303/ra7alsaver?label=download&display_name=tag)](../../releases/tag/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Android%20%C2%B7%20iPhone%20%C2%B7%20Windows%20%C2%B7%20macOS-black)

حفظ الفيديو والصور والصوت من الروابط، مع مدير ملفات خاص مقفل بالبصمة. **مجاني ومفتوح المصدر**، بدون إعلانات، وبدون حد يومي. يعمل على **أندرويد، آيفون، ويندوز، ماك**، بالعربية والإنجليزية، وبثيم داكن وفاتح.

Save videos, photos and audio from links, with a private, biometric-locked file manager. **Free & open source**, no ads, no daily limits. Android · iPhone · Windows · macOS — Arabic & English, dark & light. [English ↓](#english)

---

## المزايا
- الصق رابطاً أو استخدم «رابط في الحافظة»، واختر **فيديو** أو **صوت MP3** أو **بدون صوت**، والجودة حتى 4K.
- منشورات متعددة الصور/الفيديو: تختار ما تريد حفظه.
- **ملفاتي**: تشغيل، مشاركة، حفظ في الصور، إعادة تسمية، حذف، **قفل بالبصمة/الوجه** (أندرويد، آيفون، ماك).
- **واتساب مباشر** بدون حفظ الرقم.
- الشعار المتحرك RA7AL AL3OMR، ولغتان، وثيمان.

## التحميل والتثبيت
| النظام | الملف | طريقة التثبيت |
|---|---|---|
| أندرويد | `RA7AL-Files-Downloader-Android.apk` | نزّله على الجوال وافتحه، واسمح بـ«التثبيت من مصادر غير معروفة» عند الطلب. |
| ويندوز | `RA7AL-Files-Downloader-Windows.zip` | فك الضغط وشغّل `ra7alsaver.exe`. إذا ظهر SmartScreen: «مزيد من المعلومات» ← «تشغيل على أي حال». |
| ماك | `RA7AL-Files-Downloader-macOS.dmg` | افتح الملف واسحب التطبيق إلى Applications. أول مرة: كليك يمين على التطبيق ← «فتح». |
| آيفون | `RA7AL-Files-Downloader-iPhone-unsigned.ipa` | غير موقّع؛ ثبّته عبر AltStore أو Sideloadly بحساب Apple الخاص بك. |

الروابط: [أحدث إصدار لكل الأنظمة](../../releases/tag/latest) · [أندرويد مباشرة](../../releases/tag/android)

## سيرفر التحميل (cobalt)
التطبيق يتصل بسيرفر [cobalt](https://github.com/imputnet/cobalt) خاص بك، فيبقى التحميل يعمل حتى لو تغيّرت المنصات (يتحدث السيرفر فقط).

### التشغيل على ZimaOS
1. افتح لوحة ZimaOS ← **App Store** ← **Custom Install** (أو أيقونة `+` ← *Install a customized app*).
2. اختر **Import** والصق ملف Docker Compose التالي، مع استبدال `YOUR-SERVER-IP` بعنوان جهازك (مثل `192.168.1.50`):

```yaml
services:
  cobalt:
    image: ghcr.io/imputnet/cobalt:10
    container_name: cobalt
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      API_URL: "http://YOUR-SERVER-IP:9000/"
```
3. اضغط **Install** وانتظر حتى يعمل.
4. للتأكد: افتح `http://YOUR-SERVER-IP:9000` في المتصفح، يجب أن يظهر نص JSON فيه `"cobalt"` ورقم الإصدار.
5. في التطبيق: **الإعدادات** ← عنوان السيرفر `http://YOUR-SERVER-IP:9000` ← **حفظ واختبار**.

> على أي جهاز آخر فيه Docker: احفظ الملف أعلاه باسم `docker-compose.yml` وشغّل `docker compose up -d`.

### التحميل من خارج البيت
عنوان `192.168.x.x` يعمل فقط على شبكة البيت. للاستخدام من أي مكان ثبّت [Tailscale](https://tailscale.com) على السيرفر والجوال، واستخدم عنوان Tailscale للسيرفر (مثل `http://100.x.x.x:9000`). التطبيق يعيد توجيه روابط التحميل تلقائياً إلى العنوان الذي اتصلت به.

### مشاكل شائعة
| الرسالة | الحل |
|---|---|
| تعذّر الوصول إلى السيرفر | تأكد أن الجوال على نفس الشبكة، وأن الحاوية تعمل، وأن المنفذ 9000 مفتوح. |
| العنوان يعمل لكنه ليس سيرفر cobalt | العنوان أو المنفذ خطأ؛ جرّب فتحه في المتصفح. |
| السيرفر يتطلب مفتاح API | أضف المفتاح في الإعدادات، أو أزل إعداد المفاتيح من السيرفر. |
| المحتوى غير متاح في منطقة السيرفر | المنصة تمنع المحتوى في بلد السيرفر. |

## البناء من المصدر
```bash
flutter pub get
bash tool/setup_platforms.sh android   # أو ios / macos / windows
flutter run
```
كل دفع إلى `main` يبني النسخ الأربع تلقائياً عبر GitHub Actions وينشرها في [Releases](../../releases).

## تنبيه
أداة شخصية. احترم حقوق أصحاب المحتوى وشروط المنصات، ولا تُعِد نشر محتوى الآخرين بدون إذنهم. لا يتجاوز التطبيق أي حماية DRM.

---

<a id="english"></a>
## English

### Features
- Paste a link (or use *Link from clipboard*), choose **video**, **MP3 audio** or **muted video**, quality up to 4K.
- Multi-photo/video posts: pick exactly what to save.
- **My files**: play, share, save to Photos, rename, delete, **fingerprint / Face ID lock** (Android, iPhone, macOS).
- **WhatsApp direct chat** without saving the number.
- Animated RA7AL AL3OMR logo, Arabic & English, dark & light themes.

### Install
| Platform | File | How |
|---|---|---|
| Android | `RA7AL-Files-Downloader-Android.apk` | Open it on the phone and allow *Install unknown apps* if asked. |
| Windows | `RA7AL-Files-Downloader-Windows.zip` | Unzip and run `ra7alsaver.exe` (SmartScreen: *More info → Run anyway*). |
| macOS | `RA7AL-Files-Downloader-macOS.dmg` | Drag to Applications; first launch: right-click → *Open*. |
| iPhone | `RA7AL-Files-Downloader-iPhone-unsigned.ipa` | Unsigned — sideload with AltStore or Sideloadly. |

Downloads: [latest release](../../releases/tag/latest) · [Android only](../../releases/tag/android)

### Download server (cobalt)
The app talks to your own [cobalt](https://github.com/imputnet/cobalt) instance, so only the server needs updating when platforms change. Run the Docker Compose file above (ZimaOS: *App Store → Custom Install → Import*), replace `YOUR-SERVER-IP`, then in the app open **Settings**, enter `http://YOUR-SERVER-IP:9000` and tap **Save & test**. For use away from home, reach the server over Tailscale.

### Disclaimer
Personal tool. Respect creators' rights and platform terms; do not re-publish other people's content without permission. The app does not bypass any DRM.

## License
[GPL-3.0](LICENSE)
