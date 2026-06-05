#!/usr/bin/env python3
"""
Proxy local para javenspanish.com streams.

Añade el Referer requerido por el CDN automáticamente.
Genera un M3U con URLs apuntando a localhost para usar en VLC/Infuse/IINA.

Uso:
    python3 proxy.py [--port 8765] [--json output/javen_videos.json]
    Luego abrir: http://localhost:8765/playlist.m3u
"""

import argparse
import json
import logging
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import quote, urlparse, unquote

import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

CDN_HOST = "jav.stream-delivery.net"
REFERER = "https://javenspanish.com/"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)
HEADERS = {"Referer": REFERER, "User-Agent": USER_AGENT}

PORT = 8765
records: list[dict] = []


# ──────────────────────────────────────────────────────────────
# Generar M3U con URLs localhost
# ──────────────────────────────────────────────────────────────
def build_m3u(port: int) -> str:
    lines = ["#EXTM3U", ""]
    for r in records:
        if not r.get("has_video"):
            continue
        title = r.get("title", "Sin título")
        thumb = r.get("thumbnail", "")
        category = r.get("category", "") or "Sin categoría"
        video_url = r.get("video_url") or r.get("iframe_url", "")
        if not video_url:
            continue

        # Extraer el path del CDN y convertirlo en URL del proxy
        parsed = urlparse(video_url)
        if CDN_HOST in parsed.netloc:
            proxy_url = f"http://localhost:{port}/proxy{parsed.path}"
        else:
            proxy_url = video_url  # otros hosts, pasar directo

        logo_attr = f' tvg-logo="{thumb}"' if thumb else ""
        lines.append(f'#EXTINF:-1{logo_attr} group-title="{category}",{title}')
        lines.append(proxy_url)
        lines.append("")

    return "\n".join(lines)


# ──────────────────────────────────────────────────────────────
# Servidor proxy HTTP
# ──────────────────────────────────────────────────────────────
class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.info(f"[{self.client_address[0]}] {fmt % args}")

    def do_GET(self):
        path = self.path

        # Servir el playlist M3U
        if path == "/playlist.m3u" or path == "/":
            content = build_m3u(PORT).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.apple.mpegurl")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            return

        # Proxy al CDN con Referer
        if path.startswith("/proxy/"):
            cdn_path = path[len("/proxy"):]  # conservar la / inicial
            target = f"https://{CDN_HOST}{cdn_path}"
            try:
                resp = requests.get(
                    target, headers=HEADERS, stream=True, timeout=30, verify=False
                )
                self.send_response(resp.status_code)
                for key in ("Content-Type", "Content-Length", "Accept-Ranges",
                            "Cache-Control", "Last-Modified"):
                    if key in resp.headers:
                        self.send_header(key, resp.headers[key])
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=65536):
                    if chunk:
                        self.wfile.write(chunk)
            except BrokenPipeError:
                pass
            except Exception as e:
                log.warning(f"Proxy error {target}: {e}")
                self.send_response(502)
                self.end_headers()
            return

        self.send_response(404)
        self.end_headers()


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────
def main():
    global PORT, records

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--json", default="output/javen_videos.json")
    args = parser.parse_args()
    PORT = args.port

    json_path = Path(args.json)
    if not json_path.exists():
        print(f"ERROR: No se encontró {json_path}")
        print("Ejecuta primero: python3 scraper_javen.py --output-dir ./output")
        sys.exit(1)

    records = json.load(open(json_path, encoding="utf-8"))
    videos = [r for r in records if r.get("has_video")]
    log.info(f"Cargados {len(videos)} videos desde {json_path}")

    # Suprimir warnings de SSL
    import urllib3
    urllib3.disable_warnings()

    server = HTTPServer(("0.0.0.0", PORT), ProxyHandler)
    log.info(f"")
    log.info(f"  ✅  Proxy corriendo en http://localhost:{PORT}")
    log.info(f"")
    log.info(f"  En VLC:   Archivo → Abrir URL → http://localhost:{PORT}/playlist.m3u")
    log.info(f"  En Infuse: Añadir fuente → URL → http://localhost:{PORT}/playlist.m3u")
    log.info(f"")
    log.info(f"  Ctrl+C para detener")
    log.info(f"")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Proxy detenido.")


if __name__ == "__main__":
    main()
