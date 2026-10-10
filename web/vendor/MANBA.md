# Tashqi kutubxonalar (DM-01) — serverning o'zidan beriladi

| Fayl | Manba | SHA-256 |
|---|---|---|
| maplibre-gl-csp.js | npm maplibre-gl@4.7.1 (BSD-3-Clause), registry.npmjs.org, integrity sha512-lgL7XpIw… | `55557346a86db282433469a8ca1ff0b4889bfc2809547c809c780171bd4553cf` |
| maplibre-gl-csp-worker.js | npm maplibre-gl@4.7.1 (BSD-3-Clause), registry.npmjs.org, integrity sha512-lgL7XpIw… | `86f6a52cae3b4dfb7141480ec8ed66a8cd6b763cd16d48a2dd7342d245094f98` |
| maplibre-gl.css | npm maplibre-gl@4.7.1 (BSD-3-Clause), registry.npmjs.org, integrity sha512-lgL7XpIw… | `576b085fdd9487a65a19215328c1e086c07ce5bf6da09b666b3806d3d008dae9` |
| maplibre-LICENSE.txt | npm maplibre-gl@4.7.1 (BSD-3-Clause), registry.npmjs.org, integrity sha512-lgL7XpIw… | `ee5fc05a0677eaf69601d2c7db0d9ecd6cc27c3abc1d0733bc9ed34707cf8ef2` |

CSP build ishlatiladi: ishchi (worker) blob: dan emas, /static/vendor/maplibre-gl-csp-worker.js dan yuklanadi —
shuning uchun CSP da `worker-src 'self'` yetarli. Yangilashda: yangi versiya dist/ dan shu 4 fayl, xeshlar shu jadvalda.

3D ko'ruvchi (web/3d.js) kutubxonasiz — o'z WebGL2 kodimiz.

## Noto Sans (shrift) — `NotoSans-Regular.woff2`, `NotoSans-Bold.woff2`, `NotoSans-Italic.woff2`, `NotoSansMono-Regular.woff2`
- Manba: Debian `fonts-noto-core` paketi (`/usr/share/fonts/truetype/noto/`), Google Noto, litsenziya SIL OFL 1.1 —
  `noto-copyright.txt`.
- Qisqartirilgan (fontTools `subset`, woff2): lotin + lotin kengaytmasi (oʻ/gʻ uchun U+02BB), kirill, tinish, ± ° ‰ ≤ ≥ → ■ ● ✓.
- Nega: portal shrifti har kompyuterda bir xil chiqsin (DM-01: tashqi manbasiz; Google Fonts yo'q).
  Yangilash: `python3 -m fontTools.subset <ttf> --unicodes=... --flavor=woff2 --layout-features='*' --no-hinting`.
