#!/usr/bin/env python3
"""
Relé HTTP: recibe webhook de Grafana y reenvía a Telegram.
Corre como servicio Docker aparte.
"""
import http.server
import json
import urllib.request
import os

TELEGRAM_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
    print("ERROR: TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID son obligatorios")
    exit(1)

class RelayHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)
        grafana_payload = json.loads(body)

        # Construir mensaje para Telegram
        alertas = grafana_payload.get("alerts", [])
        firing = [a for a in alertas if a.get("status") == "firing"]

        if firing:
            lines = [f"🚨 {len(firing)} alerta(s):"]
            for a in firing:
                labels = a.get("labels", {})
                job = labels.get("job", "desconocido")
                status = "🔴" if a.get("status") == "firing" else "🟢"
                lines.append(f"{status} {job}")
        else:
            lines = ["🟢 Todos los servicios recuperados"]

        text = "\n".join(lines)

        # Enviar a Telegram
        telegram_url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        payload = json.dumps({
            "chat_id": TELEGRAM_CHAT_ID,
            "text": text,
            "parse_mode": "Markdown"
        }).encode()

        req = urllib.request.Request(telegram_url, data=payload,
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True}).encode())

    def log_message(self, format, *args):
        print(f"[relay] {args[0]} {args[1]} {args[2]}")

if __name__ == "__main__":
    port = int(os.environ.get("RELAY_PORT", 9876))
    server = http.server.HTTPServer(("0.0.0.0", port), RelayHandler)
    print(f"[relay] Escuchando en :{port}")
    server.serve_forever()
