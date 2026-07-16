#!/usr/bin/env python3
from __future__ import annotations
import concurrent.futures as cf, csv, hashlib, io, json, re, socket, sys, time, unicodedata
from pathlib import Path
import requests
from pypdf import PdfReader
import urllib3
urllib3.disable_warnings()
OUT=Path('notes_master_math_france_parallel_tor');OUT.mkdir(parents=True,exist_ok=True)
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36'
RECORDS=[
{'num':1,'title':'Cours de probabilités','path':'01 - Proba-stat/01.1 Probabilites M1/01 - Cours de probabilites - Yves Coudene (2015).pdf','urls':['https://perso.lpsm.paris/~coudene/probabilites.pdf','https://www.lpsm.paris/pageperso/coudene/probabilites.pdf','http://www.proba.jussieu.fr/pageperso/coudene/probabilites.pdf'],'expected_pages':[107],'keywords':['cours de probabil','yves coudene']},
{'num':19,'title':'Modélisation et statistique bayésienne computationnelle','path':'01 - Proba-stat/01.5 Bayesien et MCMC/19 - Modelisation et statistique bayesienne computationnelle - Nicolas Bousquet (2026).pdf','urls':['https://perso.lpsm.paris/~bousquet/poly-complet-2026-V1.pdf','https://www.lpsm.paris/pageperso/bousquet/poly-complet-2026-V1.pdf'],'expected_pages':[142],'keywords':['bayes','bousquet']},
{'num':33,'title':'Contrôle optimal : théorie et applications','path':'02 - Analyse, optimisation et outils/Optimisation et controle/33 - Controle optimal theorie et applications - Emmanuel Trelat.pdf','urls':['https://www.ljll.fr/trelat/enseignement/controlSU/livreopt2.pdf','https://www.ljll.math.upmc.fr/trelat/fichiers/livreopt2.pdf','https://www.ljll.fr/~trelat/fichiers/livreopt.pdf'],'expected_pages':[270,263,250,246],'keywords':['controle optimal','emmanuel trelat']},
{'num':34,'title':'Méthodes mathématiques et numériques pour les plasmas','path':'03 - EDP et calcul scientifique/34 - Methodes mathematiques et numeriques pour les plasmas - Bruno Despres (2021).pdf','urls':['https://www.ljll.fr/~despres/BD_fichiers/m2_plasma.pdf','https://www.ljll.fr/despres/BD_fichiers/m2_plasma.pdf','https://www.ljll.math.upmc.fr/despres/BD_fichiers/m2_plasma.pdf'],'expected_pages':[61],'keywords':['plasma','despres']},
{'num':35,'title':'Équations aux dérivées partielles elliptiques','path':'03 - EDP et calcul scientifique/35 - Equations aux derivees partielles elliptiques - Herve Le Dret (2010).pdf','urls':['https://www.ljll.fr/ledret/M2Elliptique/chapitre4.pdf','https://www.ljll.math.upmc.fr/ledret/M2Elliptique/chapitre4.pdf'],'expected_pages':[28],'keywords':['galerkin','le dret']},
]
def norm(t):
 t=unicodedata.normalize('NFKD',t);t=''.join(c for c in t if not unicodedata.combining(c));return re.sub(r'\s+',' ',t.lower())
def newnym(port):
 try:
  with socket.create_connection(('127.0.0.1',port),timeout=5) as s:
   s.sendall(b'AUTHENTICATE\r\n');r=s.recv(1024)
   if r.startswith(b'250'):s.sendall(b'SIGNAL NEWNYM\r\n');s.recv(1024)
 except Exception:pass
def validate(data,rec):
 p=data.find(b'%PDF-')
 if p<0 or p>4096:raise ValueError(f'non PDF {data[:30]!r}')
 data=data[p:];reader=PdfReader(io.BytesIO(data),strict=False);pages=len(reader.pages)
 if pages not in rec['expected_pages']:raise ValueError(f'pages inattendues {pages}')
 text=norm(' '.join((p.extract_text() or '') for p in reader.pages[:min(8,pages)]))
 if not any(k in text for k in rec['keywords']):raise ValueError(f'contenu inattendu {text[:250]!r}')
 return data,pages,text[:1000]
def download(url,port):
 proxy=f'socks5h://127.0.0.1:{port}'
 r=requests.get(url,headers={'User-Agent':UA,'Accept':'application/pdf,*/*;q=0.8'},proxies={'http':proxy,'https':proxy},timeout=(20,100),verify=False,allow_redirects=True,stream=True);r.raise_for_status();b=bytearray()
 for c in r.iter_content(262144):
  if c:b.extend(c)
  if len(b)>80*1024*1024:raise ValueError('trop volumineux')
 return bytes(b),r.url
def recover(i,rec):
 sp=9050+i;cp=9150+i;errs=[]
 for circuit in range(6):
  if circuit:newnym(cp);time.sleep(5)
  for u in rec['urls']:
   try:
    raw,final=download(u,sp);data,pages,preview=validate(raw,rec);d=OUT/rec['path'];d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(data)
    return {**rec,'status':'ok','source_url':final,'source_kind':f'tor-{sp}-{circuit}','actual_pages':pages,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'preview':preview,'detail':''}
   except Exception as e:errs.append(f'{circuit} {u}: {type(e).__name__}: {e}')
 return {**rec,'status':'error','source_url':'','source_kind':f'tor-{sp}','actual_pages':0,'bytes':0,'sha256':'','preview':'','detail':' | '.join(errs)[-20000:]}
results=[]
with cf.ThreadPoolExecutor(max_workers=5) as ex:
 fs={ex.submit(recover,i,r):r for i,r in enumerate(RECORDS)}
 for f in cf.as_completed(fs):
  try:x=f.result()
  except BaseException:
   import traceback;r=fs[f];x={**r,'status':'error','source_url':'','source_kind':'tor','actual_pages':0,'bytes':0,'sha256':'','preview':'','detail':'UNHANDLED '+traceback.format_exc()}
  results.append(x);print(f"[{x['num']:02d}] {x['status']} pages={x['actual_pages']} bytes={x['bytes']} {x['title']}",flush=True)
results.sort(key=lambda x:x['num']);fields=['num','title','path','urls','expected_pages','keywords','status','source_url','source_kind','actual_pages','bytes','sha256','preview','detail'];rows=[]
for x in results:
 y=dict(x);y['urls']=' | '.join(y['urls']);y['expected_pages']=' | '.join(map(str,y['expected_pages']));y['keywords']=' | '.join(y['keywords']);rows.append(y)
with (OUT/'manifest.csv').open('w',encoding='utf-8',newline='') as f:w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
(OUT/'manifest.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
err=[x for x in results if x['status']!='ok'];print(f'SUCCES={len(results)-len(err)} ECHECS={len(err)}');sys.exit(1 if err else 0)
