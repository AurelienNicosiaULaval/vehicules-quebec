#!/usr/bin/env python3
from __future__ import annotations

import concurrent.futures as cf
import csv
import hashlib
import io
import json
import sys
from pathlib import Path
from urllib.parse import quote

import requests
from pypdf import PdfReader

OUT = Path("notes_master_math_france_proxy")
OUT.mkdir(parents=True, exist_ok=True)
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36",
    "Accept": "application/pdf,application/octet-stream,*/*;q=0.8",
}

RECORDS = [
    {
        "num": 1,
        "title": "Cours de probabilités",
        "path": "01 - Proba-stat/01.1 Probabilites M1/01 - Cours de probabilites - Yves Coudene (2015).pdf",
        "urls": [
            "https://perso.lpsm.paris/~coudene/probabilites.pdf",
            "http://perso.lpsm.paris/~coudene/probabilites.pdf",
            "https://www.lpsm.paris/~coudene/probabilites.pdf",
            "http://www.proba.jussieu.fr/pageperso/coudene/probabilites.pdf",
        ],
    },
    {
        "num": 5,
        "title": "Probabilités approfondies : martingales et chaînes de Markov",
        "path": "01 - Proba-stat/01.2 Processus, Markov et martingales/05 - Probabilites approfondies martingales et chaines de Markov - Thomas Duquesne (2012).pdf",
        "urls": [
            "https://perso.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
            "http://perso.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
            "https://www.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
        ],
    },
    {
        "num": 11,
        "title": "Statistique, Partie 2 : approche bayésienne",
        "path": "01 - Proba-stat/01.5 Bayesien et MCMC/11 - Statistique, Partie 2 approche bayesienne - Anna Ben-Hamou; Arnaud Guyader.pdf",
        "urls": [
            "https://perso.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
            "http://perso.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
            "https://www.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
        ],
    },
    {
        "num": 15,
        "title": "Calcul stochastique et processus de diffusion",
        "path": "01 - Proba-stat/01.3 Calcul stochastique et diffusions/15 - Calcul stochastique et processus de diffusion - Nicolas Fournier.pdf",
        "urls": [
            "https://perso.lpsm.paris/~nfournier/PolyCS.pdf",
            "http://perso.lpsm.paris/~nfournier/PolyCS.pdf",
            "https://www.lpsm.paris/~nfournier/PolyCS.pdf",
            "http://www.proba.jussieu.fr/pageperso/fournier/PolyCS.pdf",
        ],
    },
    {
        "num": 19,
        "title": "Modélisation et statistique bayésienne computationnelle",
        "path": "01 - Proba-stat/01.5 Bayesien et MCMC/19 - Modelisation et statistique bayesienne computationnelle - Nicolas Bousquet (2026).pdf",
        "urls": [
            "https://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
            "http://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
            "https://www.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
        ],
    },
    {
        "num": 25,
        "title": "Méthodes de tenseurs pour les problèmes en grande dimension",
        "path": "03 - EDP et calcul scientifique/25 - Methodes de tenseurs pour les problemes en grande dimension (2024).pdf",
        "urls": [
            "https://www.ljll.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
            "http://www.ljll.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
            "https://www.ljll.math.upmc.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
            "http://www.ljll.math.upmc.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
        ],
    },
    {
        "num": 33,
        "title": "Contrôle optimal : théorie et applications",
        "path": "02 - Analyse, optimisation et outils/Optimisation et controle/33 - Controle optimal theorie et applications - Emmanuel Trelat.pdf",
        "urls": [
            "https://www.ljll.fr/~trelat/fichiers/livreopt.pdf",
            "http://www.ljll.fr/~trelat/fichiers/livreopt.pdf",
            "https://www.ljll.math.upmc.fr/~trelat/fichiers/livreopt.pdf",
            "http://www.ljll.math.upmc.fr/~trelat/fichiers/livreopt.pdf",
        ],
    },
    {
        "num": 34,
        "title": "Méthodes mathématiques et numériques pour les plasmas",
        "path": "03 - EDP et calcul scientifique/34 - Methodes mathematiques et numeriques pour les plasmas - Bruno Despres (2021).pdf",
        "urls": [
            "https://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf",
            "http://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf",
            "https://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf",
            "http://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf",
        ],
    },
    {
        "num": 35,
        "title": "Équations aux dérivées partielles elliptiques",
        "path": "03 - EDP et calcul scientifique/35 - Equations aux derivees partielles elliptiques - Herve Le Dret (2010).pdf",
        "urls": [
            "https://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf",
            "http://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf",
            "https://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf",
            "http://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf",
        ],
    },
]


def proxy_candidates(url: str) -> list[tuple[str, str]]:
    encoded = quote(url, safe="")
    return [
        ("allorigins", f"https://api.allorigins.win/raw?url={encoded}"),
        ("allorigins-hexlet", f"https://allorigins.hexlet.app/raw?url={encoded}"),
        ("corsproxy-io", f"https://corsproxy.io/?url={encoded}"),
        ("codetabs", f"https://api.codetabs.com/v1/proxy?quest={encoded}"),
        ("isomorphic-git", f"https://cors.isomorphic-git.org/{url}"),
        ("corsproxy-org", f"https://corsproxy.org/?{encoded}"),
        ("corsproxy-org-url", f"https://corsproxy.org/?url={encoded}"),
    ]


def validate(data: bytes) -> tuple[bytes, int]:
    position = data.find(b"%PDF-")
    if position < 0 or position > 4096:
        raise ValueError(f"signature PDF absente; début={data[:30]!r}")
    data = data[position:]
    pages = len(PdfReader(io.BytesIO(data), strict=False).pages)
    if pages < 1:
        raise ValueError("aucune page PDF")
    return data, pages


def fetch(candidate: tuple[str, str, str]) -> tuple[bytes, int, str, str]:
    source_url, proxy_name, proxy_url = candidate
    response = requests.get(
        proxy_url,
        headers=HEADERS,
        timeout=(10, 100),
        allow_redirects=True,
    )
    response.raise_for_status()
    data, pages = validate(response.content)
    return data, pages, source_url, proxy_name


def recover(record: dict) -> dict:
    candidates = [
        (url, proxy_name, proxy_url)
        for url in record["urls"]
        for proxy_name, proxy_url in proxy_candidates(url)
    ]
    errors: list[str] = []

    with cf.ThreadPoolExecutor(max_workers=12) as executor:
        futures = {executor.submit(fetch, candidate): candidate for candidate in candidates}
        for future in cf.as_completed(futures):
            source_url, proxy_name, proxy_url = futures[future]
            try:
                data, pages, source_url, proxy_name = future.result()
                for pending in futures:
                    pending.cancel()
                return {
                    **record,
                    "status": "ok",
                    "data": data,
                    "pages": pages,
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "source_url": source_url,
                    "source_kind": proxy_name,
                    "detail": "",
                }
            except Exception as exc:
                errors.append(
                    f"{proxy_name} {source_url}: {type(exc).__name__}: {exc}"
                )

    return {
        **record,
        "status": "error",
        "data": b"",
        "pages": 0,
        "bytes": 0,
        "sha256": "",
        "source_url": "",
        "source_kind": "",
        "detail": " | ".join(errors)[-18000:],
    }


results: list[dict] = []
with cf.ThreadPoolExecutor(max_workers=5) as executor:
    futures = {executor.submit(recover, record): record for record in RECORDS}
    for future in cf.as_completed(futures):
        record = futures[future]
        try:
            result = future.result()
        except BaseException:
            import traceback

            result = {
                **record,
                "status": "error",
                "data": b"",
                "pages": 0,
                "bytes": 0,
                "sha256": "",
                "source_url": "",
                "source_kind": "",
                "detail": "UNHANDLED " + traceback.format_exc(),
            }

        if result["status"] == "ok":
            destination = OUT / result["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(result.pop("data"))
        else:
            result.pop("data", None)

        results.append(result)
        print(
            f"[{result['num']:02d}] {result['status']} pages={result['pages']} "
            f"bytes={result['bytes']} proxy={result['source_kind']} {result['title']}",
            flush=True,
        )

results.sort(key=lambda item: item["num"])
fields = [
    "num",
    "title",
    "path",
    "urls",
    "status",
    "source_url",
    "source_kind",
    "pages",
    "bytes",
    "sha256",
    "detail",
]
rows = []
for result in results:
    row = dict(result)
    row["urls"] = " | ".join(row["urls"])
    rows.append(row)

with (OUT / "manifest.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

(OUT / "manifest.json").write_text(
    json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
)
errors = [result for result in results if result["status"] != "ok"]
print(f"SUCCES={len(results)-len(errors)} ECHECS={len(errors)}", flush=True)
sys.exit(1 if errors else 0)
