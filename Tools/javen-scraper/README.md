# Scraper de Videos — javenspanish.com

Genera automáticamente una playlist M3U y tabla CSV con todos los videos públicos de javenspanish.com, compatibles con VLC e Infuse.

## Instalación

```bash
pip install -r requirements.txt
playwright install chromium
```

## Uso

### Básico (todos los posts)
```bash
python3 scraper_javen.py
```

### Con opciones
```bash
# Probar con los primeros 10 posts
python3 scraper_javen.py --limit 10

# Cambiar directorio de salida
python3 scraper_javen.py --output-dir ~/Videos/javen

# Más lento (más respetuoso con el servidor)
python3 scraper_javen.py --concurrency 1 --delay 3

# Retomar scraping interrumpido
python3 scraper_javen.py --resume ./output/progress.json

# Sin resolver URLs con yt-dlp (más rápido, menos URLs directas)
python3 scraper_javen.py --no-resolve
```

## Archivos de salida

| Archivo | Descripción |
|---------|-------------|
| `javen_videos.m3u` | Playlist para VLC e Infuse |
| `javen_videos.csv` | Tabla completa con todos los posts |
| `javen_videos.json` | Datos completos en JSON |
| `progress.json` | Progreso parcial (cada 50 posts) |

## Reproducir en VLC / Infuse / IINA (método recomendado)

El CDN requiere un `Referer` header para servir los streams. Usar el proxy local
que lo añade automáticamente — funciona con cualquier player.

```bash
python3 proxy.py
```

Luego en tu player:
- **VLC**: `Archivo → Abrir URL → http://localhost:8765/playlist.m3u`
- **Infuse**: `Añadir fuente → URL → http://localhost:8765/playlist.m3u`
- **IINA**: Abrir URL → `http://localhost:8765/playlist.m3u`

El proxy corre mientras tienes la terminal abierta. `Ctrl+C` para detenerlo.

### Puerto alternativo
```bash
python3 proxy.py --port 9000
```

## Notas

- El scraper usa un navegador headless (Chromium) para ejecutar el JavaScript del sitio y encontrar los players de video
- Si un video está detrás del paywall, no aparecerá en el M3U (solo en el CSV como referencia)
- El scraper es respetuoso con el servidor: incluye delays y límite de concurrencia
- Si se interrumpe, usar `--resume ./output/progress.json` para continuar donde quedó

## Opciones completas

```
--limit N          Procesar solo los primeros N posts (0 = todos)
--concurrency N    Posts en paralelo (default: 2)
--delay N          Segundos de espera entre requests (default: 1.5)
--output-dir PATH  Directorio donde guardar los archivos (default: ./output)
--no-resolve       No usar yt-dlp para resolver URLs de stream directas
--resume PATH      Retomar desde un archivo progress.json previo
```
