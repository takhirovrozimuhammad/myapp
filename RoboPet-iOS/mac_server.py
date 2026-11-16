#!/usr/bin/env python3
"""RoboPet Mac: LAN pairing, local website, optional free Ollama + Whisper voice.

Uses only Python 3 standard library for the website and pairing.
Voice transcription requires optional faster-whisper, and AI needs local Ollama.
The dashboard is restricted to 127.0.0.1 (this Mac).
"""
import importlib.util
import ipaddress
import json
import os
import secrets
import socket
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG_FILE = ROOT / ".robopet_local.json"
PORT = int(os.environ.get("ROBO_PET_PORT", "8765"))
OLLAMA_URL = "http://127.0.0.1:11434"
MAX_AUDIO_BYTES = 4 * 1024 * 1024
LOCK = threading.Lock()
WHISPER_LOCK = threading.Lock()
_whisper = None
_last_seen = 0.0
_requests = 0
_events = []

SYSTEM = (
    "Sen RoboPet, yoqimtoy va aqlli mushukcha robotsan. "
    "O‘zbek lotin tilida, sodda, iliq va tabiiy javob ber. "
    "Javob 1-3 gapdan oshmasin. O‘zing bajarmagan ishni bajardim dema. "
    "Bola va o‘smirlar uchun xavfsiz yordamchi bo‘l."
)

def load_settings():
    try:
        obj = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        if isinstance(obj, dict):
            return obj
    except (OSError, ValueError):
        pass
    return {}

SETTINGS = load_settings()
if not isinstance(SETTINGS.get("pair_code"), str) or len(SETTINGS["pair_code"]) < 8:
    SETTINGS["pair_code"] = secrets.token_urlsafe(9)
SETTINGS.setdefault("model", "qwen2.5:3b")

def save_settings():
    data = json.dumps(SETTINGS, indent=2, ensure_ascii=False)
    temp = CONFIG_FILE.with_suffix(".tmp")
    with open(temp, "w", encoding="utf-8") as file:
        os.chmod(temp, 0o600)
        file.write(data)
    os.replace(temp, CONFIG_FILE)

save_settings()

def record_event(message):
    with LOCK:
        _events.insert(0, {"text": message, "time": time.strftime("%H:%M:%S")})
        del _events[12:]

def mac_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 80))  # UDP connect does not send a packet
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()

def ollama_request(endpoint, data=None, timeout=3):
    request = urllib.request.Request(
        OLLAMA_URL + endpoint,
        data=None if data is None else json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="GET" if data is None else "POST"
    )
    with urllib.request.urlopen(request, timeout=timeout) as resp:
        return json.load(resp)

def installed_models():
    try:
        return [x.get("name", "") for x in ollama_request("/api/tags", timeout=1.5).get("models", [])]
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return []

def chat_with_ollama(text):
    if not text.strip():
        raise ValueError("Savol bo‘sh.")
    with LOCK:
        model = SETTINGS["model"]
    available = installed_models()
    if model not in available:
        if not available:
            raise RuntimeError("Ollama ishlamayapti. Mac’da Ollama'ni oching va model yuklang.")
        raise RuntimeError("Tanlangan AI modeli topilmadi. Saytda boshqa modelni tanlang.")
    result = ollama_request("/api/generate", {
        "model": model,
        "system": SYSTEM,
        "prompt": text[:4000],
        "stream": False,
        "options": {"num_predict": 180, "temperature": 0.65}
    }, timeout=110)
    answer = result.get("response", "").strip()
    if not answer:
        raise RuntimeError("AI javob bermadi.")
    return answer

def transcribe_audio(data):
    global _whisper
    if importlib.util.find_spec("faster_whisper") is None:
        raise RuntimeError("Ovozni matnga aylantirish uchun faster-whisper o‘rnatilmagan. Saytdagi ko‘rsatmaga qarang.")
    with WHISPER_LOCK:
        if _whisper is None:
            from faster_whisper import WhisperModel
            _whisper = WhisperModel("base", device="cpu", compute_type="int8")
        with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as file:
            path = file.name
            file.write(data)
        try:
            segments, _ = _whisper.transcribe(path, language="uz", beam_size=3)
            transcript = " ".join(x.text.strip() for x in segments).strip()
        finally:
            try:
                os.remove(path)
            except OSError:
                pass
    if not transcript:
        raise RuntimeError("Ovoz tushunilmadi. Qaytadan ayting.")
    return transcript

def is_loopback(ip):
    try:
        return ipaddress.ip_address(ip).is_loopback
    except ValueError:
        return False

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_bytes(self, status, data, mime):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, status, obj):
        self.send_bytes(status, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def read_body(self, maximum):
        try:
            n = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            n = 0
        if n <= 0 or n > maximum:
            raise ValueError("So‘rov hajmi noto‘g‘ri.")
        return self.rfile.read(n)

    def localhost_only(self):
        if not is_loopback(self.client_address[0]):
            self.send_json(403, {"error": "Boshqaruv paneli faqat Mac'ning o‘zida ishlaydi."})
            return False
        return True

    def do_GET(self):
        global _last_seen
        if self.path in ("/", "/index.html"):
            if not self.localhost_only():
                return
            html = ROOT / "mac_dashboard.html"
            try:
                content = html.read_bytes()
                self.send_bytes(200, content, "text/html; charset=utf-8")
            except OSError:
                self.send_json(500, {"error": "mac_dashboard.html topilmadi."})
        elif self.path == "/health":
            self.send_json(200, {"online": True, "app": "RoboPet Mac", "version": 4})
        elif self.path == "/api/status":
            if not self.localhost_only():
                return
            models = installed_models()
            with LOCK:
                seen = _last_seen
                count = _requests
                events = list(_events)
                model = SETTINGS["model"]
                code = SETTINGS["pair_code"]
            self.send_json(200, {
                "online": True,
                "mac_address": f"{mac_ip()}:{PORT}",
                "pair_code": code,
                "iphone_connected": bool(seen and time.time() - seen < 30),
                "last_seen_seconds": round(time.time() - seen) if seen else None,
                "requests": count,
                "models": models,
                "model": model,
                "ai_ready": model in models,
                "ollama_running": bool(models),
                "whisper_installed": importlib.util.find_spec("faster_whisper") is not None,
                "events": events
            })
        else:
            self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        global _last_seen, _requests
        if self.path == "/pair":
            try:
                obj = json.loads(self.read_body(1024))
                code = obj.get("code", "")
            except (ValueError, TypeError):
                self.send_json(400, {"ok": False, "error": "Ulanish kodi yuborilmadi."})
                return
            with LOCK:
                authorized = isinstance(code, str) and secrets.compare_digest(code, SETTINGS["pair_code"])
                if authorized:
                    _last_seen = time.time()
            if authorized:
                self.send_json(200, {"ok": True, "name": "RoboPet Mac", "message": "Ulandi"})
                record_event("iPhone bilan ulanish tasdiqlandi")
            else:
                self.send_json(401, {"ok": False, "error": "Ulanish kodi noto‘g‘ri."})
            return

        if self.path == "/voice":
            code = self.headers.get("X-RoboPet-Code", "")
            with LOCK:
                authorized = secrets.compare_digest(code, SETTINGS["pair_code"])
                if authorized:
                    _last_seen = time.time()
            if not authorized:
                self.send_json(401, {"reply": "", "error": "Mac ulanish kodi noto‘g‘ri."})
                return
            if self.headers.get("Content-Type", "").split(";")[0] not in ("audio/mp4", "audio/x-m4a"):
                self.send_json(415, {"reply": "", "error": "Audio formati qo‘llanmaydi."})
                return
            try:
                audio = self.read_body(MAX_AUDIO_BYTES)
                if len(audio) < 100:
                    raise ValueError("Audio juda qisqa.")
                text = transcribe_audio(audio)
                answer = chat_with_ollama(text)
                with LOCK:
                    _requests += 1
                record_event("Ovozli savolga AI javob qaytardi")
                self.send_json(200, {"reply": answer, "error": None})
            except (RuntimeError, ValueError, OSError, urllib.error.URLError) as exc:
                record_event("Ovozli so‘rov ishlamadi")
                self.send_json(503, {"reply": "", "error": str(exc)})
            return

        if not self.localhost_only():
            return
        try:
            obj = json.loads(self.read_body(8192))
        except (ValueError, TypeError):
            self.send_json(400, {"error": "JSON noto‘g‘ri."})
            return

        if self.path == "/api/rotate":
            with LOCK:
                SETTINGS["pair_code"] = secrets.token_urlsafe(9)
                _last_seen = 0
                save_settings()
            record_event("Yangi ulanish kodi yaratildi")
            self.send_json(200, {"ok": True})
        elif self.path == "/api/model":
            model = obj.get("model", "")
            if not isinstance(model, str) or model not in installed_models():
                self.send_json(400, {"error": "Model Ollama'da topilmadi."})
                return
            with LOCK:
                SETTINGS["model"] = model
                save_settings()
            record_event("AI modeli yangilandi")
            self.send_json(200, {"ok": True})
        elif self.path == "/api/chat":
            prompt = obj.get("prompt", "")
            try:
                if not isinstance(prompt, str) or len(prompt) > 2000:
                    raise ValueError("Savol uzunligi 2000 belgidan oshmasin.")
                answer = chat_with_ollama(prompt)
                self.send_json(200, {"answer": answer})
                record_event("Mac panelida AI sinovi bajarildi")
            except (RuntimeError, ValueError, OSError, urllib.error.URLError) as exc:
                self.send_json(503, {"error": str(exc)})
        else:
            self.send_json(404, {"error": "Not found"})

    def log_message(self, fmt, *args):
        # Never log local pairing codes or private audio payloads.
        pass

def main():
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    httpd.daemon_threads = True
    print("\n🐱  RoboPet Mac Dashboard")
    print(f"    Mac sayti:    http://localhost:{PORT}")
    print(f"    iPhone URL:   http://{mac_ip()}:{PORT}")
    print("    Ulanish kodi va qurilma holati saytda ko‘rinadi.")
    print("    Ishlatish uchun Mac va iPhone bir Wi-Fi tarmog‘ida bo‘lsin.\n")
    record_event("RoboPet Mac server ishga tushdi")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer to‘xtadi.")
    finally:
        httpd.server_close()

if __name__ == "__main__":
    main()
