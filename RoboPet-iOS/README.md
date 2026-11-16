# RoboPet V4 — iPhone + Mac Control Center 🐱

## Mac web sayti

Bu Mac'da ishlaydigan mahalliy website: **http://localhost:8765**. Sayt internetga joylashtirilmagan; Mac serveri ochiq bo‘lsa ishlaydi.

1. GitHub Actions'dan **RoboPet-Mac-Website** artefaktini yuklab, Mac'dagi `RoboPet-iOS` papkasiga chiqar.
2. Terminalda `cd` bilan shu papkaga o't, keyin:
   ```bash
   bash start_mac.command
   ```
3. Brauzer avtomatik **http://localhost:8765** ochadi.
4. Mac va iPhone **bitta Wi‑Fi** tarmog'ida bo‘lsin. Mac saytida **IP manzil** va **ulanish kodi** ko‘rinadi.
5. iPhone RoboPet ilovasida **3 soniya** bosib tur → tema galereyasi → **Mac ulanishi** → IP manzil va kodni yoz → **Ulanishni tekshirish**.
6. Ulanish muvaffaqiyatli bo'lsa Mac saytida **iPhone ulangan** yozuvi chiqadi. Ilova har 12 soniyada aloqani yangilab turadi.

### Mac web sayti imkoniyatlari

- iPhone online/offline holatini real vaqtda ko‘rsatadi;
- Mac IP manzili va saqlanuvchi, maxfiy pairing code;
- bir bosishda manzil/kodni nusxalash;
- kodni yangilash (eski kod bekor bo‘ladi);
- 5 ta RoboPet theme uchun jonli demo;
- lokal Ollama modellar ro‘yxati va modelni tanlash;
- Mac saytining o‘zida matn bilan AI sinovi;
- audio bilan suhbat uchun Whisper holati va faoliyat jurnali.

Boshqaruv sahifasi faqat Mac'ning o'zida ochiladi. iPhone faqat `/pair`, `/health`, `/voice` so‘rovlarini yuboradi.

## Bepul AI — Ollama

RoboPet uchun pullik API kaliti kerak emas.

1. Ollama'ni yuklab ol: https://ollama.com/download/mac
2. Ollama Mac'da ishga tushsin.
3. Mac Terminal'da:
   ```bash
   ollama pull qwen2.5:3b
   ```
4. Saytdagi AI Brain bo‘limida model paydo bo‘ladi, `Saqlash` tugmasini bos va matnli suhbatni sinab ko‘r.

### iPhone mikrofoni bilan gaplashish (ixtiyoriy keyingi sozlash)

Ovoz bilan ishlashi uchun Mac'da **faster-whisper** nutqni matnga aylantiradi; bu qism Ollama'dan alohida.

```bash
python3 -m pip install faster-whisper
```

Python muhiti o‘rnatilgan bo'lishi kerak; ayrim Mac Python versiyalarida alohida virtual muhit kerak bo'lishi mumkin. Whisper'ning kichik `base` modeli birinchi so‘rovda yuklanadi; **bu yuklash internet talab qiladi**. Keyin offline ishlaydi.

Mac saytidagi `Whisper: Tayyor` statusi o‘rnatilganini bildiradi; transkripsiya sifati va yozish ishlashini real qurilmada tekshirish kerak.

iPhone yuziga bir marta bos → mikrofon yozadi; yana bos → Mac'ga yuboradi; Ollama javob beradi, iPhone mahalliy TTS bilan javobni o‘qiydi. iOS’da o‘zbekcha ovoz mavjud bo‘lmasa, talaffuz noaniq bo‘lishi mumkin.

## Theme galereyasi

- **3 soniya bosish** → iOS Lock Screen'ga o‘xshash galereya
- Chap/o‘ngga surish → Peach, Cream, Lavender, Mint, Midnight (qora)
- **Tanlash** → saqlash
- Oddiy bir marta bosish → yozish va yakunlash

## iOS build

GitHub Actions `RoboPet-unsigned-IPA` faylini yaratadi. Buni iPhone'ga bevosita o‘rnatib bo‘lmaydi — Apple ID orqali imzolash kerak (Xcode/Sideloadly/AltStore). Maxfiy Apple sertifikatlarini repo'ga joylamang.

## Maxfiylik

- Mac sayti faqat localhost'dan ko‘rinadi va kodni ko‘rsatadi.
- iPhone ⇄ Mac aloqa HTTP orqali o‘tadi, shuning uchun faqat ishonchli, shaxsiy Wi‑Fi tarmog‘ida foydalaning.
- Pairing code `.robopet_local.json` faylida saqlanadi va Git'ga joylanmaydi.
- Mac audio yozuvni vaqtincha faylga yozib transkripsiya qiladi, so‘ng o‘chiradi.
- Ollama AI Mac'da mahalliy ishlaydi. Audio, suhbat yoki shaxsiy ma'lumotlarni GitHub'ga yubormang.
- Mac server ishlamaganda iPhone AI ovozli suhbat ishlamaydi, ammo yuzi/temalari ishlaydi.

Hozircha musiqa, xona chiroqlari, Mac'dagi boshqa dasturlarni boshqarish amalga oshirilmagan.
