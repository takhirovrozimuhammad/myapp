#!/usr/bin/env python3
"""RoboPet Mac local AI relay. No external Python dependencies.

Audio (AAC/M4A) from the iPhone is sent to Gemini, which interprets
the spoken words and produces a short Uzbek answer. Apple TTS on the
phone then speaks the answer.
"""
import base64
import hmac
import json
import os
import secrets
import socket
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = int(os.environ.get("ROBO_PET_PORT", "8765"))
MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
API_KEY = os.environ.get("GEMINI_API_KEY", "")
PAIR_CODE = os.environ.get("ROBO_PET_CODE") or secrets.token_hex(5)
MAX_AUDIO_BYTES = 4 * 1024 * 1024

SYSTEM = (
    "Siz RoboPet, iPhone ekranidagi juda muloyim va aqlli mushukcha-robotsiz. "
    "Foydalanuvchi audio orqali gapiradi. Gapini tushunib, savoliga javob bering. "
    "Asosan o‘zbek tilida, LOTIN yozuvida, tabiiy, qisqa va sodda gapiring. "
    "Javob odatda 1-3 gapdan oshmasin. Keraksiz markdown, emoji yoki yulduzchalar ishlatmang. "
    "Agar audio tushunarsiz bo‘lsa, qayta so‘rang. Siz real qurilmalarni boshqara olmaysiz, "
    "bajarilmagan ishni bajardim demang."
)

def gemini_reply(audio: bytes) -> str:
    if not API_KEY:
        raise RuntimeError("GEMINI_API_KEY kiritilmagan. Mac'da .env faylini sozlang.")
    payload = {
        "system_instruction": {"parts": [{"text": SYSTEM}]},
        "contents": [
            {"role": "user", "parts": [
                {"text": "Audio yozuvdagi gapni tushun va ovoz bilan aytishga qulay javob yoz."},
                {"inline_data": {
                    "mime_type": "audio/mp4",
                    "data": base64.b64encode(audio).decode("ascii")
                }}
            ]}
        ],
        "generationConfig": {
            "maxOutputTokens": 250,
            "temperature": 0.65
        }
    }
    url = "https://generativelanguage.googleapis.com/v1beta/models/" + MODEL + ":generateContent"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "x-goog-api-key": API_KEY,
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=55) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            message = json.loads(exc.read().decode("utf-8")).get("error", {}).get("message", str(exc))
        except Exception:
            message = str(exc)
        raise RuntimeError("Gemini API: " + str(message)) from exc
    parts = result.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    text = "".join(p.get("text", "") for p in parts).strip()
    if not text:
        raise RuntimeError("Gemini audio uchun javob bermadi; yana urinib ko‘ring.")
    return text

class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, obj):
        raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {
                "online": True,
                "ai_ready": bool(API_KEY),
                "model": MODEL,
            })
        else:
            self.send_json(404, {"reply": "", "error": "Not found"})

    def do_POST(self):
        if self.path != "/voice":
            self.send_json(404, {"reply": "", "error": "Not found"})
            return
        code = self.headers.get("X-RoboPet-Code", "")
        if not hmac.compare_digest(code, PAIR_CODE):
            self.send_json(401, {"reply": "", "error": "Mac ulanish kodi noto‘g‘ri."})
            return
        if self.headers.get("Content-Type", "").split(";")[0] not in ("audio/mp4", "audio/x-m4a"):
            self.send_json(415, {"reply": "", "error": "Audio formati qo‘llanmaydi."})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            size = 0
        if not 100 <= size <= MAX_AUDIO_BYTES:
            self.send_json(413, {"reply": "", "error": "Audio hajmi noto‘g‘ri (maksimum 4 MB)."})
            return
        audio = self.rfile.read(size)
        try:
            answer = gemini_reply(audio)
            self.send_json(200, {"reply": answer, "error": None})
        except Exception as exc:
            # Do not leak API keys or raw audio into console logs.
            self.send_json(502, {"reply": "", "error": str(exc)})

    def log_message(self, fmt, *args):
        # Avoid logging microphone requests or confidential pairing code.
        if self.path == "/health":
            super().log_message(fmt, *args)

def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))
        return s.getsockname()[0]
    except OSError:
        return "Mac_IP"
    finally:
        s.close()

def main():
    print("\n🐱 RoboPet Mac AI server")
    print("Mac IP:          " + local_ip() + ":" + str(PORT))
    print("RoboPet code:    " + PAIR_CODE)
    print("Gemini AI:       " + ("configured" if API_KEY else "API KEY MISSING (.env)"))
    print("iPhone va Mac bir Wi-Fi tarmog‘ida bo‘lishi kerak.\n")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nRoboPet server stopped.")
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
