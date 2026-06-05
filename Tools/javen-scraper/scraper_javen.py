#!/usr/bin/env python3
"""
Scraper para javenspanish.com
Genera playlist M3U y tabla CSV de todos los videos públicos del sitio.

Uso:
    python3 scraper_javen.py [--limit N] [--concurrency N] [--output-dir ./output]

Dependencias:
    pip install playwright requests lxml yt-dlp
    playwright install chromium
"""

import argparse
import asyncio
import csv
import json
import logging
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urljoin, urlparse, quote

import requests
from lxml import etree
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeout

# ──────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────
BASE_URL = "https://javenspanish.com"
SITEMAP_INDEX = f"{BASE_URL}/sitemap.xml"

# Dominios de hosting de video conocidos (para detectar iframes de player)
VIDEO_HOSTING_DOMAINS = [
    # Propios del sitio
    "stream-delivery.net", "jav.stream-delivery.net",
    "vidhidevip.com",
    # Hostings genéricos
    "streamtape.com", "doodstream.com", "dood.watch", "ds2play.com",
    "filemoon.sx", "filemoon.to", "moonplayer.one",
    "mixdrop.ag", "mixdrop.co",
    "streamwish.com", "streamwish.to", "swdyu.com",
    "voe.sx", "voe.network",
    "upstream.to",
    "sibnet.ru",
    "myvi.ru",
    "ok.ru",
    "youtube.com", "youtu.be",
    "vimeo.com",
    "mega.nz",
    "drive.google.com",
]

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────────
# Fase 1: Obtener URLs del sitemap
# ──────────────────────────────────────────────────────────────
def fetch_sitemap_urls() -> list[str]:
    """Parsea el sitemap WordPress y devuelve todas las URLs de posts."""
    log.info(f"Fetching sitemap index: {SITEMAP_INDEX}")
    resp = requests.get(SITEMAP_INDEX, headers={"User-Agent": USER_AGENT}, timeout=30)
    resp.raise_for_status()

    root = etree.fromstring(resp.content)
    ns = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}

    # Encontrar sub-sitemaps de posts
    post_sitemaps = [
        loc.text
        for loc in root.findall(".//sm:loc", ns)
        if "posts-post" in (loc.text or "")
    ]

    all_urls: list[str] = []
    for sitemap_url in post_sitemaps:
        log.info(f"Fetching post sitemap: {sitemap_url}")
        r = requests.get(sitemap_url, headers={"User-Agent": USER_AGENT}, timeout=30)
        r.raise_for_status()
        sub = etree.fromstring(r.content)
        urls = [loc.text for loc in sub.findall(".//sm:loc", ns) if loc.text]
        log.info(f"  → {len(urls)} URLs encontradas")
        all_urls.extend(urls)
        time.sleep(0.5)  # cortesía

    log.info(f"Total URLs de posts: {len(all_urls)}")
    return all_urls


# ──────────────────────────────────────────────────────────────
# Fase 2: Scrape de cada post con Playwright
# ──────────────────────────────────────────────────────────────
def is_video_hosting(url: str) -> bool:
    try:
        host = urlparse(url).netloc.lower()
        return any(domain in host for domain in VIDEO_HOSTING_DOMAINS)
    except Exception:
        return False


def extract_src_param(iframe_url: str) -> str:
    """Extrae el parámetro ?src= de URLs de player tipo jav.stream-delivery.net.

    Ejemplo:
        https://jav.stream-delivery.net/player.html?src=https://.../master.m3u8
        → https://.../master.m3u8
    """
    from urllib.parse import parse_qs
    try:
        parsed = urlparse(iframe_url)
        params = parse_qs(parsed.query)
        src = params.get("src", [None])[0]
        if src and ("m3u8" in src or "mp4" in src):
            return src
    except Exception:
        pass
    return ""


async def scrape_post(page, url: str) -> dict:
    """Visita un post y extrae título, thumbnail, categoría y iframe del player."""
    result = {
        "title": "",
        "post_url": url,
        "iframe_url": "",
        "video_url": "",
        "thumbnail": "",
        "category": "",
        "has_video": False,
        "error": "",
    }

    try:
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        # Esperar un poco para que JS cargue el player
        await asyncio.sleep(2)

        # Título
        title = await page.evaluate("""() => {
            const og = document.querySelector('meta[property="og:title"]');
            if (og) return og.content;
            const h1 = document.querySelector('h1.entry-title, h1.post-title, h1');
            return h1 ? h1.innerText.trim() : document.title;
        }""")
        result["title"] = (title or "").strip()

        # Thumbnail (og:image o primera imagen del post)
        thumb = await page.evaluate("""() => {
            const og = document.querySelector('meta[property="og:image"]');
            if (og && og.content) return og.content;
            const img = document.querySelector('.entry-content img, article img, .post img');
            return img ? img.src : '';
        }""")
        result["thumbnail"] = thumb or ""

        # Categoría: buscar dentro del artículo para evitar capturar el menú global
        category = await page.evaluate("""() => {
            // Intentar encontrar la categoría del post dentro del artículo
            const article = document.querySelector('article, .post, .entry, main');
            if (article) {
                // Buscar links de categoría dentro del artículo pero fuera del contenido embebido
                const catEl = article.querySelector(
                    '.cat-links a, .entry-category a, [rel="category tag"], ' +
                    '.entry-meta a[href*="/category/"], .post-meta a[href*="/category/"]'
                );
                if (catEl) return catEl.innerText.trim();
            }
            return '';
        }""")
        result["category"] = category or ""

        # Buscar iframes que apunten a servicios de video
        iframes = await page.evaluate("""() => {
            return Array.from(document.querySelectorAll('iframe')).map(f => f.src || f.getAttribute('data-src') || '');
        }""")

        for iframe_src in iframes:
            if iframe_src and is_video_hosting(iframe_src):
                result["iframe_url"] = iframe_src

                # El player VIP usa ?src=<m3u8_url> — extraer la URL directa
                direct = extract_src_param(iframe_src)
                if direct:
                    result["video_url"] = direct
                    result["has_video"] = True
                    break

                result["has_video"] = True
                break

        # Buscar tags <video> directos
        if not result["has_video"]:
            video_src = await page.evaluate("""() => {
                const v = document.querySelector('video source, video[src]');
                if (!v) return '';
                return v.src || v.getAttribute('src') || '';
            }""")
            if video_src:
                result["video_url"] = video_src
                result["has_video"] = True

        # Buscar links directos a MP4/M3U8
        if not result["has_video"]:
            direct = await page.evaluate("""() => {
                const links = Array.from(document.querySelectorAll('a[href]'));
                for (const a of links) {
                    const href = a.href || '';
                    if (/\\.mp4|m3u8/i.test(href)) return href;
                }
                return '';
            }""")
            if direct:
                result["video_url"] = direct
                result["has_video"] = True

    except PlaywrightTimeout:
        result["error"] = "timeout"
        log.warning(f"Timeout: {url}")
    except Exception as e:
        result["error"] = str(e)[:100]
        log.warning(f"Error scraping {url}: {e}")

    return result


# ──────────────────────────────────────────────────────────────
# Fase 3: Resolver URL directa de video con yt-dlp
# ──────────────────────────────────────────────────────────────
def resolve_with_ytdlp(iframe_url: str) -> str:
    """Intenta obtener la URL directa del stream usando yt-dlp."""
    if not iframe_url:
        return ""
    try:
        result = subprocess.run(
            ["yt-dlp", "--get-url", "--no-playlist", "-q", iframe_url],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split("\n")[0]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return ""


# ──────────────────────────────────────────────────────────────
# Fase 4: Generar M3U y CSV
# ──────────────────────────────────────────────────────────────
def _encode_url(url: str) -> str:
    """Asegura que la URL esté correctamente encoded (espacios → %20, etc.)."""
    if not url:
        return url
    try:
        parsed = urlparse(url)
        # Re-encode el path preservando los / y los % ya existentes
        encoded_path = quote(parsed.path, safe="/:@!$&'()*+,;=%")
        return parsed._replace(path=encoded_path).geturl()
    except Exception:
        return url.replace(" ", "%20")


def write_m3u(records: list[dict], output_path: str) -> int:
    """Genera archivo M3U compatible con VLC e Infuse."""
    videos = [r for r in records if r.get("video_url") or r.get("iframe_url")]
    if not videos:
        log.warning("No se encontraron videos con URL reproducible para el M3U.")
        return 0

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n\n")
        for r in videos:
            title = r["title"] or r["post_url"]
            category = r.get("category", "") or "Sin categoría"
            thumb = r.get("thumbnail", "")
            video_url = r.get("video_url") or r.get("iframe_url", "")

            # URL-encode espacios y caracteres especiales en la URL del video
            video_url = _encode_url(video_url)

            logo_attr = f' tvg-logo="{thumb}"' if thumb else ""
            f.write(
                f'#EXTINF:-1{logo_attr} group-title="{category}",'
                f'{title}\n'
            )
            f.write(f"{video_url}\n\n")

    log.info(f"M3U escrito: {output_path} ({len(videos)} videos)")
    return len(videos)


def write_csv(records: list[dict], output_path: str):
    """Genera tabla CSV con todos los posts (con y sin video)."""
    fields = ["title", "post_url", "iframe_url", "video_url", "thumbnail", "category", "has_video", "error"]
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    log.info(f"CSV escrito: {output_path} ({len(records)} filas)")


def write_json(records: list[dict], output_path: str):
    """Genera JSON completo para referencia."""
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)
    log.info(f"JSON escrito: {output_path}")


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────
async def run_scraper(
    post_urls: list[str],
    concurrency: int,
    resolve_stream: bool,
    output_dir: Path,
    delay: float,
):
    records: list[dict] = []
    semaphore = asyncio.Semaphore(concurrency)
    total = len(post_urls)

    async def process(browser, url: str, idx: int):
        async with semaphore:
            log.info(f"[{idx}/{total}] Scraping: {url}")
            ctx = await browser.new_context(
                user_agent=USER_AGENT,
                viewport={"width": 1280, "height": 800},
                java_script_enabled=True,
                ignore_https_errors=True,
            )
            page = await ctx.new_page()
            try:
                data = await scrape_post(page, url)
            finally:
                await page.close()
                await ctx.close()

            # Intentar resolver URL con yt-dlp si tenemos iframe pero no video directo
            if resolve_stream and data["has_video"] and data["iframe_url"] and not data["video_url"]:
                log.info(f"  → Resolviendo stream con yt-dlp: {data['iframe_url'][:60]}...")
                direct = resolve_with_ytdlp(data["iframe_url"])
                if direct:
                    data["video_url"] = direct
                    log.info(f"  ✓ Stream resuelto")
                else:
                    # Usar iframe_url como fallback (VLC puede reproducir muchos iframes)
                    data["video_url"] = data["iframe_url"]
                    log.info(f"  → Usando iframe URL como fallback")

            await asyncio.sleep(delay)
            return data

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--ignore-certificate-errors"],
        )
        tasks = [process(browser, url, i + 1) for i, url in enumerate(post_urls)]
        for coro in asyncio.as_completed(tasks):
            result = await coro
            records.append(result)

            # Guardar progreso parcial cada 50 posts
            if len(records) % 50 == 0:
                _save_progress(records, output_dir)

        await browser.close()

    return records


def _save_progress(records, output_dir: Path):
    progress_path = output_dir / "progress.json"
    with open(progress_path, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)
    log.info(f"Progreso guardado: {len(records)} posts procesados → {progress_path}")


def main():
    parser = argparse.ArgumentParser(description="Scraper de javenspanish.com")
    parser.add_argument("--limit", type=int, default=0, help="Límite de posts a procesar (0 = todos)")
    parser.add_argument("--concurrency", type=int, default=2, help="Posts en paralelo (default: 2)")
    parser.add_argument("--delay", type=float, default=1.5, help="Delay entre requests en segundos (default: 1.5)")
    parser.add_argument("--output-dir", type=str, default="./output", help="Directorio de salida")
    parser.add_argument("--no-resolve", action="store_true", help="No usar yt-dlp para resolver URLs directas")
    parser.add_argument("--resume", type=str, default="", help="Ruta a progress.json para retomar scraping")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Retomar desde progreso guardado si se especifica
    already_scraped: set[str] = set()
    existing_records: list[dict] = []
    if args.resume and Path(args.resume).exists():
        with open(args.resume, encoding="utf-8") as f:
            existing_records = json.load(f)
        already_scraped = {r["post_url"] for r in existing_records}
        log.info(f"Retomando: {len(already_scraped)} posts ya procesados")

    # Obtener todas las URLs
    all_urls = fetch_sitemap_urls()
    pending_urls = [u for u in all_urls if u not in already_scraped]

    if args.limit > 0:
        pending_urls = pending_urls[: args.limit]
        log.info(f"Modo limitado: procesando {args.limit} posts")

    log.info(f"Posts pendientes: {len(pending_urls)}")

    if not pending_urls:
        log.info("Nada que procesar. Generando archivos de salida con datos existentes...")
        new_records = []
    else:
        new_records = asyncio.run(
            run_scraper(
                post_urls=pending_urls,
                concurrency=args.concurrency,
                resolve_stream=not args.no_resolve,
                output_dir=output_dir,
                delay=args.delay,
            )
        )

    all_records = existing_records + new_records

    # Estadísticas
    with_video = [r for r in all_records if r.get("has_video")]
    log.info(f"\n{'='*50}")
    log.info(f"Posts totales procesados : {len(all_records)}")
    log.info(f"Con video encontrado     : {len(with_video)}")
    log.info(f"Sin video (paywall/vacío): {len(all_records) - len(with_video)}")
    log.info(f"{'='*50}\n")

    # Guardar resultados
    m3u_path = output_dir / "javen_videos.m3u"
    csv_path = output_dir / "javen_videos.csv"
    json_path = output_dir / "javen_videos.json"

    count = write_m3u(all_records, str(m3u_path))
    write_csv(all_records, str(csv_path))
    write_json(all_records, str(json_path))

    log.info(f"\nArchivos generados en: {output_dir.resolve()}")
    log.info(f"  📺 Playlist M3U  : {m3u_path.name}  ({count} videos)")
    log.info(f"  📋 Tabla CSV     : {csv_path.name}")
    log.info(f"  🗂  JSON completo : {json_path.name}")
    log.info("\nPara usar en VLC: Archivo → Abrir archivo → javen_videos.m3u")
    log.info("Para usar en Infuse: Añadir el .m3u como fuente de red o vía Files")


if __name__ == "__main__":
    main()
