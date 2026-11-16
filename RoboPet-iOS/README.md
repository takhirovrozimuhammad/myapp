# RoboPet V5 — iPhone 12 + Mac Control Center 🐱

RoboPet is a full-screen iPhone companion with an animated kitten face, connected to a free Mac-hosted AI. Builds in GitHub Actions on a macOS runner.

## iPhone V5 — yangi funksiyalar

- **Mikrofon xatosi tuzatildi:** audio yozish uchun yangilangan AVAudioRecorder (native sample rate, `prepareToRecord`, `record`) ishlatiladi. Real iPhone'da qayta sinash kerak.
- **Face following:** iPhone old kamerasi + Apple Vision yordamida yuzning ekrandagi o‘rnini topib, RoboPet ko‘zlarini unga qaratadi. Kamera tasviri telefonni tark etmaydi, saqlanmaydi. Kamera ruxsati birinchi marta so‘raladi; sozlamada o‘chirish mumkin.
- **Mimika:** tinglash, o‘ylash, xursand bo‘lish, uyqusirash va ovoz chiqarib javob berishda yuz ifodalari o‘zgaradi. Gaplashganda og‘iz animatsiya qiladi; bu hozircha haqiqiy viseme lip-sync emas.
- **Soat so‘ralganda:** landscape ekranning yarmida mushukcha, yarmida soat va sana chiqadi. Ob-havo so‘ralganda: iPhone joylashuv ruxsati bilan Open-Meteo API orqali harorat, holat va namlikni ko‘rsatadi; internet talab qiladi.
- **Musiqa so‘ralganda:** "Mac yoki iPhone?" deb tanlatadi. Mac tanlansa Music.app'ga play buyrug‘i boradi (Music kutubxonasi va macOS Automation ruxsati kerak). iPhone tanlansa Music ilovasi ochiladi; qo‘shiqni foydalanuvchi tanlaydi. Mac musiqa rejimida RoboPet og‘zi ritmga o‘xshash sekin harakatlanadi, ammo musiqa ohangini tahlil qilmaydi va haqiqiy ovozli xirgoyi yo‘q.
- **Theme galereyasi:** ekranni **3 soniya bosib turish** → iPhone Lock Screen uslubida gorizontal galereya. 5 ta tayyor theme: Peach, Cream, Lavender, Mint, Midnight (qora).
- **Custom themes:** "Yangi theme" → nomi, fon, ko‘z, burun va og‘iz ranglarini tanlash → Saqlash. Istagancha yangi theme qo‘shish, yaratganlarini tahrirlash mumkin; ma’lumotlar iPhone'da saqlanadi.
- **Sleep Mode:** theme galereyasidagi `Sleep` → qora fon ustida katta, doimiy yangilanadigan soat. Ekranga bitta tegish bilan RoboPet uyg‘onadi.
- **Ekran o‘chmasligi:** ilova old ekranda (foreground) ishlaganda `UIApplication.shared.isIdleTimerDisabled = true`. Bu telefonning avtomatik uxlab qolishini to‘xtatadi; tizimning qo‘lda bloklash, batareya yoki boshqa cheklovlarini bekor qilmaydi. Uzoq vaqt ochiq qoldirishda quvvat sarfi oshadi va ekran qizishi mumkin. Sleep Mode'da kamera o‘chadi.

## Mac V5

Mac web-sayti: **http://localhost:8765**, iPhone bilan bir Wi-Fi orqali ulanish. Mac serverda IP va pairing code ko‘rsatiladi. Oldingi v4 pairing code saqlanib qolishi uchun eski `.robopet_local.json` faylini yangi Mac server papkasiga ko‘chir (yoki yangi kod bilan iPhone'ni qayta ulang).

### Ishga tushirish

1. Eski `start_mac.command` oynasini `Ctrl+C` bilan to‘xtat (port 8765 band bo‘lmasin).
2. Yangi `RoboPet-Mac-Website` ZIP'ni chiqar.
3. Mac Terminal:
   ```bash
   cd ~/Downloads/RoboPet-iOS
   bash start_mac.command
   ```
   Papka nomi boshqa bo‘lsa, yuqoridagi `cd` yo‘lini o‘sha papkaga mosla.
4. `http://localhost:8765` sahifasidan IP va kodni ol.
5. iPhone RoboPet'da **3 soniya bos → Mac ulanishi → IP + kod → Ulanishni tekshirish**.

### Bepul lokal AI

- Ollama: https://ollama.com/download/mac
- Model: `ollama pull qwen2.5:3b`
- Text chat sinovi: Mac saytining AI Brain bo‘limida.
- Ovozdan matn: `faster-whisper` (**alohida** kerak, `python3 -m pip install faster-whisper` yoki Python virtual environment orqali). Birinchi foydalanishda Whisper `base` modeli yuklanadi.
- iPhone TTS: tizim `AVSpeechSynthesizer`; Uzbek voice iOS'da bo‘lmasa talaffuz mukammal emas.
- Soat, ob-havo va musiqa buyruqlari lokal qoidalar bilan ajratiladi; **ular uchun Ollama kerak emas**, lekin ovozni matnga aylantirish uchun Whisper kerak.

### Xavfsizlik va maxfiylik

- Mac web paneli faqat `localhost` dan ochiladi. iPhone Mac bilan lokal HTTP orqali gaplashadi, shuning uchun faqat **ishonchli Wi-Fi** ishlat.
- Juftlash kodi `.robopet_local.json` faylida, maxfiy kalitlarni GitHub'ga yuklama.
- Old kamera tasvirlari uzatilmaydi yoki saqlanmaydi. Joylashuv faqat ob-havo so‘ralganda va ruxsat berilganda ishlatiladi.
- Internet AI API kaliti shart emas.
- Bu versiya iPhone'da real ishlash bo‘yicha avtomatik build tekshiruvlaridan tashqari sinovdan o‘tkazilmagan. iPhone'da mikrofon, kamera, musiqani real tekshirib boramiz.

## iOS build / IPA

GitHub Actions `RoboPet-unsigned-IPA` yaratadi. iPhone'ga o‘rnatishdan oldin Sideloadly yoki Xcode bilan Apple ID orqali **imzolash** talab qilinadi. 
