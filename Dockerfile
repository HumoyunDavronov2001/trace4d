# TRACE4D data markaz tasviri (DM-04): HTTP server + qayta hisob ishchisi + zaxira, bitta tasvir.
# Swift yadro CLI (yerosti-tahlil) — telefon bilan BIR XIL kod, rasmiy Swift tasvirida yig'iladi.
# Swift 6.4: mahalliy sinovlar (yadro 137 + 3 atayin skip) shu kompilyatorda o'tadi.
ARG SWIFT_SURUM=6.4
FROM swift:${SWIFT_SURUM}-noble AS yadro
WORKDIR /qurish
COPY Yadro ./Yadro
# -j 2: umumiy serverda yig'ish barcha yadrolarni band qilmasin (boshqa dasturlar sekinlashmasin)
RUN cd Yadro && swift build -c release --product yerosti-tahlil -j 2 \
 && install -D -m 0755 .build/release/yerosti-tahlil /chiqish/yerosti-tahlil

# Ish vaqti: rasmiy Swift runtime (slim) + Ubuntu python3 paketlari — PyPI dan yuklash yo'q.
# reportlab + qrcode + DejaVu: A3 ijro hujjati (IH-01…IH-08), shrift kirill va lotin harflarini qamraydi;
# Pillow — reportlab ning majburiy bog'liqligi va dalolatnomaga muhrlangan JPEG rasm joylash (ShN-05)
FROM swift:${SWIFT_SURUM}-noble-slim AS ish
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-cryptography python3-reportlab python3-qrcode python3-pil \
      fonts-dejavu-core ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /ilova --shell /usr/sbin/nologin yerosti \
 && mkdir -p /malumot/skanlar /zaxira && chown -R yerosti /malumot /zaxira
WORKDIR /ilova
COPY --from=yadro /chiqish/yerosti-tahlil /usr/local/bin/yerosti-tahlil
# barcha server modullari (ro'yxat qo'lda yuritilganda ifc, las, tasdiq tushib qolgan edi — 05.10)
COPY yerosti_*.py zaxira.py ./
COPY web ./web
# yig'ishning o'zida isbot: CLI va python bog'liqliklari ishlaydi
RUN yerosti-tahlil versiya && python3 -c "import cryptography, sqlite3; print('python', sqlite3.sqlite_version, cryptography.__version__)" \
 && python3 -c "import yerosti_ijro as i; i._shrift(); print('ijro hujjati: reportlab, qrcode, DejaVu tayyor')" \
 && python3 -c "import yerosti_server, yerosti_ishchi, zaxira, yerosti_dalolatnoma; from PIL import Image; print('barcha modullar yuklandi')"
ENV YEROSTI_BAZA=/malumot/yerosti.db \
    YEROSTI_SKANLAR=/malumot/skanlar \
    YEROSTI_TAHLIL_CLI=/usr/local/bin/yerosti-tahlil \
    PYTHONUNBUFFERED=1 \
    TZ=Asia/Tashkent

# Sinov bosqichi: Ubuntu paketidagi kutubxonalar (reportlab 4.x, mahalliyda 5.x) bilan ijro hujjati, DXF, IFC, QR va
# lokalizatsiya sinovlari. Faqat yig'ishda ishlaydi — yakuniy tasvirga poppler va OpenCV tushmaydi. Yiqilsa yig'ish to'xtaydi.
FROM ish AS sinov
RUN apt-get update && apt-get install -y --no-install-recommends poppler-utils python3-opencv && rm -rf /var/lib/apt/lists/*
COPY sinov/ijro_sinov.py sinov/lokal_sinov.py sinov/tasdiq_sinov.py sinov/las_sinov.py ./sinov/
RUN python3 sinov/ijro_sinov.py && python3 sinov/lokal_sinov.py && python3 sinov/tasdiq_sinov.py && python3 sinov/las_sinov.py \
 && date > /sinov-otdi

FROM ish
# sinov bosqichi o'tmasa bu qator bajarilmaydi — tasvir yig'ilmaydi
COPY --from=sinov /sinov-otdi /ilova/.sinov-otdi
USER yerosti
VOLUME ["/malumot"]
EXPOSE 8342
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8342/api/v1/salomatlik', timeout=4).status == 200 else 1)"
CMD ["python3", "-u", "yerosti_server.py", "--port", "8342"]
