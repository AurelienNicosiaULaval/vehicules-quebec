#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import csv
import hashlib
import io
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

from playwright.async_api import async_playwright, Response
from pypdf import PdfReader

OUT = Path("notes_master_math_france_googleviewer")
OUT.mkdir(parents=True, exist_ok=True)

RECORDS = [
    (1, "Cours de probabilités", "01 - Proba-stat/01.1 Probabilites M1/01 - Cours de probabilites - Yves Coudene (2015).pdf", "https://perso.lpsm.paris/~coudene/probabilites.pdf"),
    (5, "Probabilités approfondies : martingales et chaînes de Markov", "01 - Proba-stat/01.2 Processus, Markov et martingales/05 - Probabilites approfondies martingales et chaines de Markov - Thomas Duquesne (2012).pdf", "https://perso.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf"),
    (11, "Statistique, Partie 2 : approche bayésienne", "01 - Proba-stat/01.5 Bayesien et MCMC/11 - Statistique, Partie 2 approche bayesienne - Anna Ben-Hamou; Arnaud Guyader.pdf", "https://perso.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf"),
    (15, "Calcul stochastique et processus de diffusion", "01 - Proba-stat/01.3 Calcul stochastique et diffusions/15 - Calcul stochastique et processus de diffusion - Nicolas Fournier.pdf", "https://perso.lpsm.paris/~nfournier/PolyCS.pdf"),
    (19, "Modélisation et statistique bayésienne computationnelle", "01 - Proba-stat/01.5 Bayesien et MCMC/19 - Modelisation et statistique bayesienne computationnelle - Nicolas Bousquet (2026).pdf", "https://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf"),
    (25, "Méthodes de tenseurs pour les problèmes en grande dimension", "03 - EDP et calcul scientifique/25 - Methodes de tenseurs pour les problemes en grande dimension (2024).pdf", "https://www.ljll.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf"),
    (33, "Contrôle optimal : théorie et applications", "02 - Analyse, optimisation et outils/Optimisation et controle/33 - Controle optimal theorie et applications - Emmanuel Trelat.pdf", "https://www.ljll.fr/~trelat/fichiers/livreopt.pdf"),
    (34, "Méthodes mathématiques et numériques pour les plasmas", "03 - EDP et calcul scientifique/34 - Methodes mathematiques et numeriques pour les plasmas - Bruno Despres (2021).pdf", "https://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf"),
    (35, "Équations aux dérivées partielles elliptiques", "03 - EDP et calcul scientifique/35 - Equations aux derivees partielles elliptiques - Herve Le Dret (2010).pdf", "https://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf"),
]


def validate(data: bytes) -> tuple[bytes, int]:
    position = data.find(b"%PDF-")
    if position < 0 or position > 4096:
        raise ValueError(f"signature PDF absente, début={data[:30]!r}")
    data = data[position:]
    pages = len(PdfReader(io.BytesIO(data), strict=False).pages)
    if pages < 1:
        raise ValueError("aucune page PDF")
    return data, pages


async def recover_one(browser, semaphore, record):
    number, title, path, source_url = record
    errors = []
    captured: list[tuple[bytes, str]] = []

    async with semaphore:
        context = await browser.new_context(
            accept_downloads=True,
            locale="fr-FR",
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36",
        )
        page = await context.new_page()

        async def inspect_response(response: Response):
            try:
                headers = await response.all_headers()
                content_type = headers.get("content-type", "").lower()
                candidate_url = response.url.lower()
                if (
                    "application/pdf" in content_type
                    or candidate_url.endswith(".pdf")
                    or "viewerng/download" in candidate_url
                    or "googleusercontent.com" in candidate_url
                ):
                    body = await response.body()
                    try:
                        data, _ = validate(body)
                        captured.append((data, response.url))
                    except Exception:
                        pass
            except Exception:
                pass

        page.on("response", inspect_response)
        viewer_urls = [
            f"https://docs.google.com/gview?embedded=1&url={quote(source_url, safe='')}",
            f"https://docs.google.com/viewerng/viewer?embedded=true&url={quote(source_url, safe='')}",
        ]

        try:
            for viewer_url in viewer_urls:
                try:
                    await page.goto(viewer_url, wait_until="domcontentloaded", timeout=120000)
                    await page.wait_for_timeout(20000)
                    if captured:
                        break

                    html = await page.content()
                    raw_candidates = re.findall(
                        r'https?[^"\'<> ]+(?:googleusercontent\.com|viewerng|\.pdf)[^"\'<> ]*',
                        html,
                        flags=re.I,
                    )
                    for raw in raw_candidates[:30]:
                        candidate = raw.replace("\\u003d", "=").replace("\\u0026", "&").replace("\\/", "/")
                        try:
                            response = await context.request.get(candidate, timeout=60000)
                            body = await response.body()
                            data, _ = validate(body)
                            captured.append((data, candidate))
                            break
                        except Exception:
                            continue
                    if captured:
                        break

                    selectors = [
                        '[aria-label*="Download"]',
                        '[aria-label*="Télécharger"]',
                        'a[download]',
                        '#download',
                        'text=Download',
                        'text=Télécharger',
                    ]
                    for selector in selectors:
                        try:
                            locator = page.locator(selector).first
                            if await locator.count() and await locator.is_visible(timeout=1500):
                                async with page.expect_download(timeout=15000) as download_info:
                                    await locator.click()
                                download = await download_info.value
                                temporary = OUT / f"tmp_{number}.pdf"
                                await download.save_as(str(temporary))
                                body = temporary.read_bytes()
                                temporary.unlink(missing_ok=True)
                                data, _ = validate(body)
                                captured.append((data, download.url))
                                break
                        except Exception:
                            continue
                    if captured:
                        break
                except Exception as exc:
                    errors.append(f"viewer {viewer_url}: {type(exc).__name__}: {exc}")

            if not captured:
                raise RuntimeError("aucun PDF original intercepté")

            data, source = captured[0]
            data, pages = validate(data)
            destination = OUT / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            return {
                "num": number,
                "title": title,
                "path": path,
                "source_url": source_url,
                "status": "ok",
                "retrieved_url": source,
                "source_kind": "google-docs-viewer",
                "pages": pages,
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "detail": "",
            }
        except Exception as exc:
            errors.append(f"final: {type(exc).__name__}: {exc}")
            return {
                "num": number,
                "title": title,
                "path": path,
                "source_url": source_url,
                "status": "error",
                "retrieved_url": "",
                "source_kind": "google-docs-viewer",
                "pages": 0,
                "bytes": 0,
                "sha256": "",
                "detail": " | ".join(errors)[-16000:],
            }
        finally:
            await context.close()


async def main():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        semaphore = asyncio.Semaphore(3)
        results = await asyncio.gather(
            *(recover_one(browser, semaphore, record) for record in RECORDS)
        )
        await browser.close()

    results.sort(key=lambda item: item["num"])
    fields = [
        "num", "title", "path", "source_url", "status", "retrieved_url",
        "source_kind", "pages", "bytes", "sha256", "detail",
    ]
    with (OUT / "manifest.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)
    (OUT / "manifest.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    for result in results:
        print(
            f"[{result['num']:02d}] {result['status']} pages={result['pages']} "
            f"bytes={result['bytes']} {result['title']}",
            flush=True,
        )
    errors = [item for item in results if item["status"] != "ok"]
    print(f"SUCCES={len(results)-len(errors)} ECHECS={len(errors)}", flush=True)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
