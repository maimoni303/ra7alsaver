# RA7AL AL3OMR SAVER

![RA7AL AL3OMR SAVER](docs/brand/ra7al_saver_logo.gif)

حفظ الفيديو والصور والصوت من الروابط، مع مدير ملفات خاص مقفل بالبصمة. **مجاني ومفتوح المصدر**، بدون إعلانات، وبدون حد يومي. يعمل على **أندرويد، آيفون، ويندوز، ماك**، بالعربية والإنجليزية، وبثيم داكن وفاتح.

Save videos, photos and audio from links, with a private, biometric-locked file manager. Free & open source, no ads, no daily limits. Android · iPhone · Windows · macOS — Arabic & English, dark & light.

## المزايا
- الصق رابطاً أو استخدم «رابط في الحافظة»، واختر **فيديو** أو **صوت MP3** أو **بدون صوت**، والجودة حتى 4K.
- منشورات متعددة الصور/الفيديو: تختار ما تريد حفظه.
- **ملفاتي**: تشغيل، مشاركة، حفظ في الصور، إعادة تسمية، حذف، **قفل بالبصمة/الوجه**.
- **واتساب مباشر** بدون حفظ الرقم.
- الشعار المتحرك RA7AL AL3OMR، ولغتان، وثيمان.

## سيرفر التحميل (cobalt)
التطبيق يتصل بسيرفر [cobalt](https://github.com/imputnet/cobalt) خاص بك، فيبقى التحميل يعمل حتى لو تغيّرت المنصات (يتحدث السيرفر فقط).
على ZimaOS أو أي جهاز فيه Docker:

```yaml
services:
  cobalt:
    image: ghcr.io/imputnet/cobalt:10
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      API_URL: "http://YOUR-SERVER-IP:9000/"
```
ثم من الإعدادات في التطبيق: `http://YOUR-SERVER-IP:9000` ← **حفظ واختبار**.

## التحميل
[Releases → latest](../../releases/tag/latest) · أندرويد مباشرة: [android](../../releases/tag/android)

## تنبيه
أداة شخصية. احترم حقوق أصحاب المحتوى وشروط المنصات، ولا تُعِد نشر محتوى الآخرين بدون إذنهم. لا يتجاوز التطبيق أي حماية DRM.

## الترخيص
[GPL-3.0](LICENSE)
