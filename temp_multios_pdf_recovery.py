#!/usr/bin/env python3
from __future__ import annotations

import concurrent.futures as cf
import csv
import hashlib
import io
import json
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen

import requests
from pypdf import PdfReader
import urllib3

urllib3.disable_warnings()

OUT = Path(os.environ.get("PDF_OUTPUT_DIR", f"notes_master_math_france_{platform.system().lower()}"))
OUT.mkdir(parents=True, exist_ok=True)
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/605.1.15",
    "Accept": "application/pdf,application/octet-stream,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.7",
}

RECORDS = [
    (1, "Cours de probabilités", "01 - Proba-stat/01.1 Probabilites M1/01 - Cours de probabilites - Yves Coudene (2015).pdf", [
        "https://perso.lpsm.paris/~coudene/probabilites.pdf",
        "http://perso.lpsm.paris/~coudene/probabilites.pdf",
        "https://www.lpsm.paris/~coudene/probabilites.pdf",
        "http://www.proba.jussieu.fr/pageperso/coudene/probabilites.pdf",
    ]),
    (5, "Probabilités approfondies : martingales et chaînes de Markov", "01 - Proba-stat/01.2 Processus, Markov et martingales/05 - Probabilites approfondies martingales et chaines de Markov - Thomas Duquesne (2012).pdf", [
        "https://perso.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
        "http://perso.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
        "https://www.lpsm.paris/~broutinn/teaching/4M011_poly_duquesne.pdf",
    ]),
    (11, "Statistique, Partie 2 : approche bayésienne", "01 - Proba-stat/01.5 Bayesien et MCMC/11 - Statistique, Partie 2 approche bayesienne - Anna Ben-Hamou; Arnaud Guyader.pdf", [
        "https://perso.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
        "http://perso.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
        "https://www.lpsm.paris/~aguyader/files/teaching/M1/PolycopiePartie2.pdf",
    ]),
    (15, "Calcul stochastique et processus de diffusion", "01 - Proba-stat/01.3 Calcul stochastique et diffusions/15 - Calcul stochastique et processus de diffusion - Nicolas Fournier.pdf", [
        "https://perso.lpsm.paris/~nfournier/PolyCS.pdf",
        "http://perso.lpsm.paris/~nfournier/PolyCS.pdf",
        "https://www.lpsm.paris/~nfournier/PolyCS.pdf",
        "http://www.proba.jussieu.fr/pageperso/fournier/PolyCS.pdf",
    ]),
    (19, "Modélisation et statistique bayésienne computationnelle", "01 - Proba-stat/01.5 Bayesien et MCMC/19 - Modelisation et statistique bayesienne computationnelle - Nicolas Bousquet (2026).pdf", [
        "https://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
        "http://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
        "https://www.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf",
    ]),
    (25, "Méthodes de tenseurs pour les problèmes en grande dimension", "03 - EDP et calcul scientifique/25 - Methodes de tenseurs pour les problemes en grande dimension (2024).pdf", [
        "https://www.ljll.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
        "http://www.ljll.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
        "https://www.ljll.math.upmc.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
        "http://www.ljll.math.upmc.fr/MathModel/enseignement/cours/TenseursM2_2024.pdf",
    ]),
    (33, "Contrôle optimal : théorie et applications", "02 - Analyse, optimisation et outils/Optimisation et controle/33 - Controle optimal theorie et applications - Emmanuel Trelat.pdf", [
        "https://www.ljll.fr/~trelat/fichiers/livreopt.pdf",
        "http://www.ljll.fr/~trelat/fichiers/livreopt.pdf",
        "https://www.ljll.math.upmc.fr/~trelat/fichiers/livreopt.pdf",
        "http://www.ljll.math.upmc.fr/~trelat/fichiers/livreopt.pdf",
    ]),
    (34, "Méthodes mathématiques et numériques pour les plasmas", "03 - EDP et calcul scientifique/34 - Methodes mathematiques et numeriques pour les plasmas - Bruno Despres (2021).pdf", [
        "https://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf",
        "http://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf",
        "https://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf",
        "http://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf",
    ]),
    (35, "Équations aux dérivées partielles elliptiques", "03 - EDP et calcul scientifique/35 - Equations aux derivees partielles elliptiques - Herve Le Dret (2010).pdf", [
        "https://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf",
        "http://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf",
        "https://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf",
        "http://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf",
    ]),
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


def method_requests(url: str) -> bytes:
    response = requests.get(url, headers=HEADERS, timeout=(8, 55), verify=False, allow_redirects=True)
    response.raise_for_status()
    return response.content


def method_urllib(url: str) -> bytes:
    request = Request(url, headers=HEADERS)
    with urlopen(request, timeout=55) as response:
        return response.read()


def method_curl(url: str) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as handle:
        temporary = Path(handle.name)
    command = [
        "curl", "-L", "--fail", "--retry", "2", "--retry-all-errors",
        "--connect-timeout", "10", "--max-time", "70",
        "-A", HEADERS["User-Agent"], "-o", str(temporary), url,
    ]
    try:
        process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if process.returncode != 0:
            raise RuntimeError((process.stderr or process.stdout)[-1200:])
        return temporary.read_bytes()
    finally:
        temporary.unlink(missing_ok=True)


def recover(record: tuple) -> dict:
    number, title, path, urls = record
    errors = []
    methods = [("requests", method_requests), ("urllib", method_urllib), ("curl", method_curl)]
    for url in urls:
        for method_name, method in methods:
            try:
                data, pages = validate(method(url))
                return {
                    "num": number,
                    "title": title,
                    "path": path,
                    "urls": urls,
                    "status": "ok",
                    "source_url": url,
                    "source_kind": f"{platform.system()}-{method_name}",
                    "pages": pages,
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "data": data,
                    "detail": "",
                }
            except Exception as exc:
                errors.append(f"{method_name} {url}: {type(exc).__name__}: {exc}")
    return {
        "num": number,
        "title": title,
        "path": path,
        "urls": urls,
        "status": "error",
        "source_url": "",
        "source_kind": platform.system(),
        "pages": 0,
        "bytes": 0,
        "sha256": "",
        "data": b"",
        "detail": " | ".join(errors)[-16000:],
    }


results = []
with cf.ThreadPoolExecutor(max_workers=9) as executor:
    futures = {executor.submit(recover, record): record for record in RECORDS}
    for future in cf.as_completed(futures):
        record = futures[future]
        try:
            result = future.result()
        except BaseException:
            import traceback
            number, title, path, urls = record
            result = {
                "num": number, "title": title, "path": path, "urls": urls,
                "status": "error", "source_url": "", "source_kind": platform.system(),
                "pages": 0, "bytes": 0, "sha256": "", "data": b"",
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
            f"bytes={result['bytes']} kind={result['source_kind']} {result['title']}",
            flush=True,
        )

results.sort(key=lambda item: item["num"])
fields = ["num", "title", "path", "urls", "status", "source_url", "source_kind", "pages", "bytes", "sha256", "detail"]
rows = []
for result in results:
    row = dict(result)
    row["urls"] = " | ".join(row["urls"])
    rows.append(row)
with (OUT / "manifest.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
(OUT / "manifest.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
errors = [item for item in results if item["status"] != "ok"]
print(f"SUCCES={len(results)-len(errors)} ECHECS={len(errors)}", flush=True)
sys.exit(1 if errors else 0)
