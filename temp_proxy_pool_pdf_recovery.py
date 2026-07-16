#!/usr/bin/env python3
from __future__ import annotations

import concurrent.futures as cf
import csv
import hashlib
import io
import json
import re
import sys
import time
from pathlib import Path

import requests
from pypdf import PdfReader
import urllib3

urllib3.disable_warnings()

OUT = Path("notes_master_math_france_proxy_pool")
OUT.mkdir(parents=True, exist_ok=True)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36"
HEADERS = {
    "User-Agent": UA,
    "Accept": "application/pdf,application/octet-stream,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.7",
}

RECORDS = [
    {
        "num": 1,
        "title": "Cours de probabilités",
        "path": "01 - Proba-stat/01.1 Probabilites M1/01 - Cours de probabilites - Yves Coudene (2015).pdf",
        "urls": [
            "https://perso.lpsm.paris/~coudene/probabilites.pdf",
            "https://www.lpsm.paris/pageperso/coudene/probabilites.pdf",
            "http://www.proba.jussieu.fr/pageperso/coudene/probabilites.pdf",
        ],
        "expected_pages": [107],
        "keywords": ["cours de probabil", "yves coudene"],
    },
    {
        "num": 19,
        "title": "Modélisation et statistique bayésienne computationnelle",
        "path": "01 - Proba-stat/01.5 Bayesien et MCMC/19 - Modelisation et statistique bayesienne computationnelle - Nicolas Bousquet (2026).pdf",
        "urls": [
            "https://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
            "https://www.lpsm.paris/pageperso/bousquet/poly-complet-2026-V1.pdf",
        ],
        "expected_pages": [142],
        "keywords": ["bayes", "bousquet"],
    },
    {
        "num": 33,
        "title": "Contrôle optimal : théorie et applications",
        "path": "02 - Analyse, optimisation et outils/Optimisation et controle/33 - Controle optimal theorie et applications - Emmanuel Trelat.pdf",
        "urls": [
            "https://www.ljll.fr/trelat/enseignement/controlSU/livreopt2.pdf",
            "https://www.ljll.math.upmc.fr/trelat/fichiers/livreopt2.pdf",
            "https://www.ljll.fr/trelat/fichiers/livreopt.pdf",
        ],
        "expected_pages": [270, 263, 250, 246],
        "keywords": ["controle optimal", "emmanuel trelat"],
    },
    {
        "num": 34,
        "title": "Méthodes mathématiques et numériques pour les plasmas",
        "path": "03 - EDP et calcul scientifique/34 - Methodes mathematiques et numeriques pour les plasmas - Bruno Despres (2021).pdf",
        "urls": [
            "https://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf",
            "https://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf",
        ],
        "expected_pages": [61],
        "keywords": ["plasma", "despres"],
    },
    {
        "num": 35,
        "title": "Équations aux dérivées partielles elliptiques",
        "path": "03 - EDP et calcul scientifique/35 - Equations aux derivees partielles elliptiques - Herve Le Dret (2010).pdf",
        "urls": [
            "https://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf",
            "https://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf",
        ],
        "expected_pages": [28],
        "keywords": ["equations aux derivees partielles", "herve le dret"],
    },
]

PROXY_LIST_URLS = [
    "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/all/data.txt",
    "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt",
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt",
    "https://raw.githubusercontent.com/clarketm/proxy-list/master/proxy-list-raw.txt",
    "https://api.proxyscrape.com/v4/free-proxy-list/get?request=display_proxies&protocol=http&timeout=8000&country=all&ssl=all&anonymity=all",
]


def normalize_text(text: str) -> str:
    import unicodedata

    text = unicodedata.normalize("NFKD", text)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = text.lower()
    return re.sub(r"\s+", " ", text)


def fetch_proxy_list() -> list[str]:
    proxies: set[str] = set()
    for endpoint in PROXY_LIST_URLS:
        try:
            response = requests.get(endpoint, headers={"User-Agent": UA}, timeout=30)
            response.raise_for_status()
            for line in response.text.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "://" in line:
                    scheme, rest = line.split("://", 1)
                    if scheme.lower() not in {"http", "https"}:
                        continue
                    candidate = rest.split()[0].strip()
                else:
                    candidate = line.split()[0].strip()
                if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}", candidate):
                    proxies.add(candidate)
        except Exception as exc:
            print(f"Proxy list failed {endpoint}: {type(exc).__name__}: {exc}", flush=True)
    # Proxies récents en premier, plafond pour éviter un balayage excessif.
    return list(proxies)[:900]


def proxy_dict(proxy: str | None) -> dict[str, str] | None:
    if proxy is None:
        return None
    value = f"http://{proxy}"
    return {"http": value, "https": value}


def probe(args: tuple[str, str | None]) -> tuple[bool, str, str | None, str]:
    url, proxy = args
    try:
        with requests.get(
            url,
            headers={**HEADERS, "Range": "bytes=0-65535"},
            proxies=proxy_dict(proxy),
            timeout=(5, 12),
            verify=False,
            allow_redirects=True,
            stream=True,
        ) as response:
            if response.status_code not in (200, 206):
                return False, url, proxy, f"HTTP {response.status_code}"
            chunks = []
            size = 0
            for chunk in response.iter_content(8192):
                if chunk:
                    chunks.append(chunk)
                    size += len(chunk)
                    if size >= 65536:
                        break
            data = b"".join(chunks)
            if b"%PDF-" not in data[:4096]:
                return False, url, proxy, f"not PDF {data[:20]!r}"
            return True, response.url, proxy, "pdf signature"
    except Exception as exc:
        return False, url, proxy, f"{type(exc).__name__}: {exc}"


def download_full(url: str, proxy: str | None) -> bytes:
    with requests.get(
        url,
        headers=HEADERS,
        proxies=proxy_dict(proxy),
        timeout=(10, 180),
        verify=False,
        allow_redirects=True,
        stream=True,
    ) as response:
        response.raise_for_status()
        data = bytearray()
        for chunk in response.iter_content(262144):
            if chunk:
                data.extend(chunk)
                if len(data) > 80 * 1024 * 1024:
                    raise ValueError("fichier anormalement volumineux")
        return bytes(data)


def validate_document(data: bytes, record: dict) -> tuple[bytes, int, str]:
    position = data.find(b"%PDF-")
    if position < 0 or position > 4096:
        raise ValueError(f"signature PDF absente: {data[:30]!r}")
    data = data[position:]
    reader = PdfReader(io.BytesIO(data), strict=False)
    pages = len(reader.pages)
    if pages < 1:
        raise ValueError("aucune page")
    if record["expected_pages"] and pages not in record["expected_pages"]:
        raise ValueError(f"nombre de pages inattendu: {pages}")
    extracted = []
    for page in reader.pages[: min(8, pages)]:
        try:
            extracted.append(page.extract_text() or "")
        except Exception:
            pass
    text = normalize_text(" ".join(extracted))
    matches = sum(keyword in text for keyword in record["keywords"])
    if matches == 0:
        raise ValueError(f"aucun mot-clé attendu dans les premières pages: {text[:300]!r}")
    return data, pages, text[:1000]


def recover(record: dict, proxies: list[str]) -> dict:
    errors: list[str] = []
    candidates: list[tuple[str, str | None]] = []
    # Essai direct puis sous-ensemble de relais. Mélanger l'ordre pour répartir la charge.
    for url in record["urls"]:
        candidates.append((url, None))
        candidates.extend((url, proxy) for proxy in proxies)

    successful_probes: list[tuple[str, str | None]] = []
    with cf.ThreadPoolExecutor(max_workers=80) as executor:
        futures = {executor.submit(probe, candidate): candidate for candidate in candidates}
        for future in cf.as_completed(futures):
            ok, final_url, proxy, detail = future.result()
            if ok:
                successful_probes.append((final_url, proxy))
                if len(successful_probes) >= 12:
                    for pending in futures:
                        pending.cancel()
                    break
            elif len(errors) < 50:
                errors.append(f"probe {future.result()[1]} via {proxy}: {detail}")

    for final_url, proxy in successful_probes:
        try:
            raw = download_full(final_url, proxy)
            data, pages, text_preview = validate_document(raw, record)
            destination = OUT / record["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            return {
                **record,
                "status": "ok",
                "source_url": final_url,
                "source_kind": "direct" if proxy is None else f"public-http-proxy:{proxy}",
                "pages": pages,
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "proxies_tested": len(proxies),
                "successful_probes": len(successful_probes),
                "text_preview": text_preview,
                "detail": "",
            }
        except Exception as exc:
            errors.append(f"full {final_url} via {proxy}: {type(exc).__name__}: {exc}")

    return {
        **record,
        "status": "error",
        "source_url": "",
        "source_kind": "",
        "pages": 0,
        "bytes": 0,
        "sha256": "",
        "proxies_tested": len(proxies),
        "successful_probes": len(successful_probes),
        "text_preview": "",
        "detail": " | ".join(errors)[-20000:],
    }


proxies = fetch_proxy_list()
print(f"PROXIES={len(proxies)}", flush=True)
results: list[dict] = []
# Un document à la fois afin de ne pas surcharger les relais publics.
for record in RECORDS:
    result = recover(record, proxies)
    results.append(result)
    print(
        f"[{result['num']:02d}] {result['status']} pages={result['pages']} bytes={result['bytes']} "
        f"probes={result['successful_probes']} {result['title']}",
        flush=True,
    )

fields = [
    "num", "title", "path", "urls", "expected_pages", "keywords", "status",
    "source_url", "source_kind", "pages", "bytes", "sha256", "proxies_tested",
    "successful_probes", "text_preview", "detail",
]
rows = []
for result in results:
    row = dict(result)
    row["urls"] = " | ".join(row["urls"])
    row["expected_pages"] = " | ".join(map(str, row["expected_pages"]))
    row["keywords"] = " | ".join(row["keywords"])
    rows.append(row)
with (OUT / "manifest.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
(OUT / "manifest.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
errors = [result for result in results if result["status"] != "ok"]
print(f"SUCCES={len(results)-len(errors)} ECHECS={len(errors)}", flush=True)
sys.exit(1 if errors else 0)
