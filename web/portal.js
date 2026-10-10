"use strict";
/* YEROSTI portal v2 (TALABLAR 17, PD): xarita-birinchi ish maydoni — chap ikonka ustuni (rail), bitta tortma panel
   (Obyektlar / Qatlamlar / Qazish / Tizim), o'ngda inspektor (obyekt yoki liniya tafsiloti, tablar), xarita asboblari
   ustuni, pastda koordinata o'qish va asos chipi. Ma'lumot mantig'i (API) o'zgarmagan. */

const TURLAR = {
  suv:          { nom: "Suv",           rang: "#2563EB" },
  kanalizatsiya:{ nom: "Kanalizatsiya", rang: "#92400E" },
  gaz:          { nom: "Gaz",           rang: "#CA8A04" },
  elektr:       { nom: "Elektr",        rang: "#DC2626" },
  optika:       { nom: "Optika",        rang: "#EA580C" },
  issiqlik:     { nom: "Issiqlik",      rang: "#7C3AED" },
};
const SIFATLAR = { RASMIY: ["nishon-ok", "RASMIY", "RTK FIX, chegarada"], SKAN: ["nishon-ogoh", "SKAN", "RTK tasdig'i kutilmoqda"],
  PAST: ["nishon-xato", "PAST", "rasmiy hujjatga chiqmaydi"] };
const SKAN_NOMLARI = { mesh_usdz: "3D mesh (USDZ)", mesh_obj: "3D mesh (OBJ)",
  nuqta_ply: "Nuqta buluti", foto: "Foto", nmea_jurnal: "NMEA jurnali", muhr_jurnal: "Muhr jurnali", kadrlar: "Kadrlar" };
// T-031: RASMIY yoki RTK bilan tasdiqlangan skan liniyasi — yaxlit; tasdiqsiz SKAN va PAST — punktir
const YAXLIT = ["any", ["==", ["get", "sifat"], "RASMIY"], ["==", ["get", "tasdiq"], "tasdiqlangan"]];
const CHIZIQ_QATLAMLAR = [
  ["tarmoq-chiziq", YAXLIT, false],
  ["tarmoq-chiziq-punktir", ["!", YAXLIT], true],
];
const TASDIQ_NOMI = { tasdiqlangan: ["nishon-ok", "RTK tasdiqlangan"], qisman: ["nishon-ogoh", "qisman tasdiqlangan"],
  farq: ["nishon-xato", "FARQ"], yoq: ["nishon-ogoh", "tasdiq yo'q"], rtk: ["nishon-kul", "RTK o'lchov"] };
const tasdiqNishon = (holat) => { const [k, n] = TASDIQ_NOMI[holat] || ["nishon-kul", holat || "—"]; return `<span class="nishon ${k}">${esc(n)}</span>`; };
const CHIZIQ_IDLAR = CHIZIQ_QATLAMLAR.map((q) => q[0]);
// DM-01: asos xarita uslubi serverdan sozlanadi; bo'sh bo'lsa — plitkasiz rejim: fon + koordinata to'ri (PD-06)
const BOSH_USLUB = { version: 8, sources: {}, layers: [{ id: "fon", type: "background", paint: { "background-color": "#F4F6F9" } }] };
const BOLIMLAR = { obyektlar: "Obyektlar", qatlamlar: "Qatlamlar", qazish: "Qazish zonasi tekshiruvi", tizim: "Tizim" };
const TABLAR = [["umumiy", "Umumiy"], ["liniya", "Liniya"], ["asos", "Asos"], ["hujjat", "Hujjat"], ["loyiha", "Loyiha"], ["ulash", "Ulash"], ["tarix", "Tarix"]];

const el = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g,
  (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
/* ShN-01: qazish orderi «raqam, DD.MM.YYYY» (ShNK 3.01.03-24, 420-band) — server order_matn bilan bir xil */
const orderMatn = (o) => {
  const r = String((o && o.order_raqami) || "").trim();
  let d = String((o && o.order_sana) || "").trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(d)) d = `${d.slice(8, 10)}.${d.slice(5, 7)}.${d.slice(0, 4)}`;
  return r || d ? `${r || "raqam yo'q"}, ${d || "sana yo'q"}` : "";
};
const ikon = (id) => `<svg class="ikon" aria-hidden="true"><use href="#i-${id}"/></svg>`;
/** 1234.5 → "1 234,5" (o'zbekcha: vergul, ingichka bo'shliq). */
const son = (x, k = 1) => {
  if (x == null || isNaN(x)) return "—";
  const [b, q] = Number(x).toFixed(k).split(".");
  return b.replace(/\B(?=(\d{3})+(?!\d))/g, " ") + (q ? "," + q : "");
};
const sm = (m) => (m == null ? "—" : son(m * 100, 1));
/** Server vaqti UTC (ISO) — foydalanuvchiga brauzerning mahalliy vaqtida (Toshkent: UTC+5). */
const sanaMatn = (iso) => {
  const d = iso ? new Date(iso) : null;
  if (!d || isNaN(d)) return "—";
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
};

let men = null;
let xarita = null;
let plitkasiz = false;
let geoKesh = { type: "FeatureCollection", features: [] };
let statKesh = null;
let obyektKesh = [];
const faolTurlar = new Set(Object.keys(TURLAR));
const faolSifatlar = new Set(Object.keys(SIFATLAR));
let orderRejim = false;
let orderNuqtalar = [];
let tanlanganObyekt = null;
let faolTab = "umumiy";
let faolBolim = "obyektlar";
// SY-01…SY-04: xarita asoslari (ortofoto, sun'iy yo'ldosh) va masofa o'lchash
let asoslar = [];
let masofaRejim = false;
let masofaNuqtalar = [];

async function so(yol, metod = "GET", tana = null) {
  const j = { method: metod, headers: { "X-Yerosti": "1" }, credentials: "same-origin" };
  if (tana) { j.headers["Content-Type"] = "application/json"; j.body = JSON.stringify(tana); }
  const javob = await fetch(yol, j);
  const m = await javob.json().catch(() => ({}));
  if (!javob.ok) throw new Error(m.xato || `xato ${javob.status}`);
  return m;
}
const yozuvchi = () => men && (men.rol === "admin" || men.rol === "operator");

/* ---------- kirish ---------- */

async function boshlash() {
  try {
    const m = await so("/api/v1/men");
    kirishMuvaffaqiyat(m.foydalanuvchi);
  } catch {
    el("kirish-qatlam").classList.remove("yashirin");
    el("kirish-login").focus();
  }
}

el("kirish-forma").addEventListener("submit", async (h) => {
  h.preventDefault();
  const xato = el("kirish-xato");
  xato.classList.add("yashirin");
  try {
    const m = await so("/api/v1/kirish", "POST",
      { login: el("kirish-login").value.trim(), parol: el("kirish-parol").value });
    kirishMuvaffaqiyat(m.foydalanuvchi);
  } catch (x) {
    xato.textContent = x.message;
    xato.classList.remove("yashirin");
  }
});

async function chiqish() {
  try { await so("/api/v1/chiqish", "POST", {}); } catch {}
  location.reload();
}
el("chiqish").addEventListener("click", chiqish);
el("hisob-chiqish").addEventListener("click", chiqish);

function kirishMuvaffaqiyat(f) {
  // T1: QR-belgi sahifasidan «tizimga kirish» — kirgach o'sha belgiga qaytadi (faqat /q/<kod> shakli)
  const keyin = new URLSearchParams(location.search).get("keyin");
  if (keyin && /^\/q\/[A-Za-z0-9_-]{8,64}$/.test(keyin)) { location.replace(keyin); return; }
  men = f;
  el("kirish-qatlam").classList.add("yashirin");
  el("ilova").classList.remove("yashirin");
  const ism = f.ism || f.login;
  el("foydalanuvchi-harf").textContent = ism.trim().split(/\s+/).slice(0, 2).map((s) => s[0]).join("").toUpperCase();
  el("foydalanuvchi-rol").textContent = f.rol;
  el("hisob-ism").textContent = ism;
  el("hisob-rol").textContent = `${f.login} · ${f.rol}`;
  el("yangi-obyekt").classList.toggle("yashirin", !yozuvchi());
  el("bosh-yangi-obyekt").classList.toggle("yashirin", !yozuvchi());
  el("dala-qurilmalar").classList.toggle("yashirin", f.rol !== "admin");
  el("bosh-dala").classList.toggle("yashirin", f.rol !== "admin");
  setInterval(() => malumotYangila(false), 60000);
  if (!xarita) xaritaYarat();
}

/* ---------- rail va tortma ---------- */

function railTanla(bolim) {
  const ochiq = el("asosiy").classList.contains("tortma-ochiq");
  if (bolim === faolBolim && ochiq) return tortmaYop();
  faolBolim = bolim;
  for (const b of document.querySelectorAll(".rail-tugma")) b.setAttribute("aria-pressed", String(b.dataset.bolim === bolim));
  for (const s of document.querySelectorAll(".tortma-tana")) s.classList.toggle("yashirin", s.id !== `bolim-${bolim}`);
  el("tortma-sarlavha").textContent = BOLIMLAR[bolim];
  el("asosiy").classList.add("tortma-ochiq");
  orderHolat(bolim === "qazish");
  // qazish rejimida va telefonda (panellar ustma-ust tushadi) inspektor yopiladi
  if (bolim === "qazish" || window.innerWidth < 900) inspektorYop();
  if (bolim === "tizim") tizimMalumot();
}
function tortmaYop() {
  el("asosiy").classList.remove("tortma-ochiq");
  for (const b of document.querySelectorAll(".rail-tugma")) b.setAttribute("aria-pressed", "false");
  orderHolat(false);
}
for (const b of document.querySelectorAll(".rail-tugma")) b.addEventListener("click", () => railTanla(b.dataset.bolim));
el("tortma-yop").addEventListener("click", tortmaYop);

el("hisob-tugma").addEventListener("click", (h) => {
  h.stopPropagation();
  const m = el("hisob-menyu");
  const ochiq = m.classList.toggle("yashirin");
  el("hisob-tugma").setAttribute("aria-expanded", String(!ochiq));
});
document.addEventListener("click", (h) => {
  if (!h.target.closest("#hisob-menyu")) { el("hisob-menyu").classList.add("yashirin"); el("hisob-tugma").setAttribute("aria-expanded", "false"); }
});

function tizimMalumot() {
  const a = asoslar.map((x) => x.nomi).join(", ");
  el("tizim-malumot").innerHTML = `<b>Xarita</b>: ${plitkasiz ? "plitkasiz rejim (faqat tarmoqlar va koordinata to'ri)" : "serverda sozlangan uslub"}` +
    `${a ? ` · asoslar: ${esc(a)}` : " · qo'shimcha asos yo'q"}.<br>Vaqtlar Toshkent (UTC+5) bo'yicha. Sifat qoidasi serverda va iPhone drayverida bir xil.`;
}

/* ---------- xarita ---------- */

async function xaritaYarat() {
  let uslub = "";
  try {
    const sz = await so("/api/v1/xarita-sozlama");
    uslub = sz.uslub || "";
    asoslar = sz.asoslar || [];
  } catch {}
  plitkasiz = !uslub;
  maplibregl.setWorkerUrl("/static/vendor/maplibre-gl-csp-worker.js");
  xarita = new maplibregl.Map({
    container: "xarita",
    style: uslub || BOSH_USLUB,
    center: [67.8422, 40.1158],
    zoom: 13.5,
    attributionControl: { compact: true },
  });
  window._xarita = xarita; // sinov/otladka tutqichi
  // konteyner o'lchami xarita yaratilgandan keyin o'rnashsa, kanvas eski o'lchamda qolib ketardi — kuzatamiz
  new ResizeObserver(() => xarita.resize()).observe(el("xarita"));
  xarita.addControl(new maplibregl.ScaleControl({ unit: "metric" }), "bottom-left");
  xarita.on("load", qatlamlarYarat);
  xarita.on("click", xaritaBosildi);
  xarita.on("mousemove", (h) => {
    koordinataYoz(h.lngLat);
    if (orderRejim || masofaRejim || !xarita.getLayer("tarmoq-chiziq")) return;
    const t = xarita.queryRenderedFeatures(h.point, { layers: CHIZIQ_IDLAR });
    xarita.getCanvas().style.cursor = t.length ? "pointer" : "";
  });
  xarita.on("moveend", torYangila);
  for (const b of document.querySelectorAll("[data-asbob]")) b.addEventListener("click", () => asbob(b.dataset.asbob));
}

function asbob(nomi) {
  if (!xarita) return;
  if (nomi === "yaqin") xarita.zoomIn();
  else if (nomi === "uzoq") xarita.zoomOut();
  else if (nomi === "shimol") xarita.resetNorthPitch();
  else if (nomi === "hammasi") hammasigaUch();
  else if (nomi === "masofa") masofaHolat(!masofaRejim);
  else if (nomi === "asos") {
    const ids = ["sxema", ...asoslar.map((a) => a.id)];
    asosTanla(ids[(ids.indexOf(faolAsos()) + 1) % ids.length]);
  } else if (nomi === "qamrov") {
    const a = asoslar.find((x) => x.id === "ortofoto");
    if (a && a.chegara) xarita.fitBounds([[a.chegara[0], a.chegara[1]], [a.chegara[2], a.chegara[3]]], { padding: 40, duration: 700 });
  }
}

async function qatlamlarYarat() {
  if (plitkasiz) {
    xarita.addSource("tor", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    xarita.addLayer({ id: "tor", type: "line", source: "tor", paint: { "line-color": "#D3DBE6", "line-width": 1 } });
  }
  // SY-03: raster asoslar tarmoq chiziqlari OSTIDA (keyin qo'shiladigan qatlamlar ustida chiziladi)
  for (const a of asoslar) {
    const manba = { type: "raster", tiles: [a.tiles.startsWith("/") ? location.origin + a.tiles : a.tiles], tileSize: 256,
      minzoom: a.min_zoom || 0, maxzoom: a.maks_zoom || 19, attribution: esc(a.atributsiya || "") };
    if (a.chegara) manba.bounds = a.chegara;
    xarita.addSource(`asos-${a.id}`, manba);
    xarita.addLayer({ id: `asos-${a.id}`, type: "raster", source: `asos-${a.id}`, layout: { visibility: "none" },
      paint: { "raster-opacity": 1, "raster-fade-duration": 0 } });
    if (a.chegara) {
      const [g, j, sh, sm2] = a.chegara;
      xarita.addSource(`asos-chegara-${a.id}`, { type: "geojson", data: { type: "Feature", geometry: { type: "Polygon",
        coordinates: [[[g, j], [sh, j], [sh, sm2], [g, sm2], [g, j]]] } } });
      xarita.addLayer({ id: `asos-chegara-${a.id}`, type: "line", source: `asos-chegara-${a.id}`, layout: { visibility: "none" },
        paint: { "line-color": "#1F5BD6", "line-width": 1.5, "line-dasharray": [3, 2], "line-opacity": 0.7 } });
    }
  }
  xarita.addSource("tarmoqlar", { type: "geojson", data: geoKesh });
  const ranglar = ["match", ["get", "turi"]];
  for (const [t, m] of Object.entries(TURLAR)) ranglar.push(t, m.rang);
  ranglar.push("#334155");
  // MapLibre 4 da line-dasharray ma'lumotga bog'liq bo'lolmaydi — RASMIY (yaxlit) va SKAN/PAST (punktir) alohida qatlam
  const kenglik = ["interpolate", ["linear"], ["zoom"], 13, 2, 16, 4.5, 18, 7];
  for (const [id, sifatFiltr, punktir] of CHIZIQ_QATLAMLAR) {
    xarita.addLayer({
      id, type: "line", source: "tarmoqlar", filter: sifatFiltr,
      layout: { "line-cap": punktir ? "butt" : "round", "line-join": "round" },
      paint: { "line-color": ranglar, "line-width": kenglik, "line-opacity": 0.92, ...(punktir ? { "line-dasharray": [2, 1.2] } : {}) },
    });
  }
  if (xarita.getStyle().glyphs) xarita.addLayer({
    id: "tarmoq-yorliq", type: "symbol", source: "tarmoqlar", minzoom: 15.5,
    layout: { "symbol-placement": "line", "text-field": ["get", "chuqurlik_matn"],
      "text-font": ["Noto Sans Regular"], "text-size": 11, "text-offset": [0, -0.9] },
    paint: { "text-color": "#334155", "text-halo-color": "#ffffff", "text-halo-width": 1.6 },
  });
  xarita.addSource("order-chizma", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
  xarita.addLayer({ id: "order-maydon", type: "fill", source: "order-chizma",
    filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": "#B32C26", "fill-opacity": 0.12 } });
  xarita.addLayer({ id: "order-chegara", type: "line", source: "order-chizma",
    filter: ["in", ["geometry-type"], ["literal", ["Polygon", "LineString"]]],
    paint: { "line-color": "#B32C26", "line-width": 2, "line-dasharray": [2, 1.5] } });
  xarita.addLayer({ id: "order-nuqtalar", type: "circle", source: "order-chizma",
    filter: ["==", ["geometry-type"], "Point"],
    paint: { "circle-radius": 5, "circle-color": "#B32C26", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } });
  xarita.addSource("masofa", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
  xarita.addLayer({ id: "masofa-chiziq", type: "line", source: "masofa", filter: ["==", ["geometry-type"], "LineString"],
    paint: { "line-color": "#FFD60A", "line-width": 3, "line-dasharray": [2, 1] } });
  xarita.addLayer({ id: "masofa-nuqta", type: "circle", source: "masofa", filter: ["==", ["geometry-type"], "Point"],
    paint: { "circle-radius": 5, "circle-color": "#FFD60A", "circle-stroke-color": "#0B1620", "circle-stroke-width": 2 } });
  asosBoshqaruvYarat();
  torYangila();
  await malumotYangila(true);
}

/* PD-06: plitkasiz rejimda koordinata to'ri — bo'sh kulrang maydon o'rniga masshtabga mos geografik to'r. */
function torYangila() {
  if (!xarita || !plitkasiz || !xarita.getSource("tor")) return;
  const b = xarita.getBounds(), z = xarita.getZoom();
  const mpp = 156543.03 * Math.cos(xarita.getCenter().lat * Math.PI / 180) / 2 ** z; // metr / piksel
  const qadam = [5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0.0005, 0.0002, 0.0001, 0.00005]
    .find((q) => q * 110574 / mpp <= 140) || 0.00005;
  const f = [];
  const g = Math.floor(b.getWest() / qadam) * qadam, sh = Math.ceil(b.getEast() / qadam) * qadam;
  const j = Math.floor(b.getSouth() / qadam) * qadam, sm2 = Math.ceil(b.getNorth() / qadam) * qadam;
  for (let x = g, i = 0; x <= sh && i < 120; x += qadam, i++) f.push([[x, j], [x, sm2]]);
  for (let y = j, i = 0; y <= sm2 && i < 120; y += qadam, i++) f.push([[g, y], [sh, y]]);
  xarita.getSource("tor").setData({ type: "Feature", geometry: { type: "MultiLineString", coordinates: f } });
}

/* ---------- SY: xarita asoslari, masofa, koordinata o'qish ---------- */

function asosBoshqaruvYarat() {
  const tugma = (id, nom) => `<button type="button" data-asos="${id}" aria-pressed="false">${esc(nom)}</button>`;
  el("asos-tanlov").innerHTML = tugma("sxema", "Sxema") +
    asoslar.map((a) => tugma(a.id, a.id === "ortofoto" ? "Ortofoto" : "Sun'iy yo'ldosh")).join("");
  for (const b of document.querySelectorAll("[data-asos]")) b.addEventListener("click", () => asosTanla(b.dataset.asos));
  el("asos-shaffof").addEventListener("input", (h) => {
    const id = faolAsos();
    if (id !== "sxema") xarita.setPaintProperty(`asos-${id}`, "raster-opacity", Number(h.target.value));
  });
  document.querySelector("[data-asbob='asos']").classList.toggle("yashirin", !asoslar.length);
  let saqlangan = "sxema";
  try { saqlangan = localStorage.getItem("yerosti_asos") || "sxema"; } catch {}
  asosTanla(asoslar.some((a) => a.id === saqlangan) ? saqlangan : "sxema");
}

function faolAsos() {
  const b = document.querySelector("[data-asos][aria-pressed='true']");
  return b ? b.dataset.asos : "sxema";
}

/** SY-03: tanlangan asos, manbasi va e'lon qilingan aniqligi doim ko'rinadi (pastki chip) — surat siljishi o'lchov xatosi emas. */
function asosTanla(id) {
  for (const a of asoslar) {
    xarita.setLayoutProperty(`asos-${a.id}`, "visibility", a.id === id ? "visible" : "none");
    if (xarita.getLayer(`asos-chegara-${a.id}`)) xarita.setLayoutProperty(`asos-chegara-${a.id}`, "visibility", a.id === id ? "visible" : "none");
  }
  for (const b of document.querySelectorAll("[data-asos]")) b.setAttribute("aria-pressed", String(b.dataset.asos === id));
  const a = asoslar.find((x) => x.id === id);
  el("asos-shaffof-q").classList.toggle("yashirin", !a);
  el("asos-izoh").classList.toggle("yashirin", !a);
  el("asos-chip").classList.toggle("yashirin", !a);
  document.querySelector("[data-asbob='qamrov']").classList.toggle("yashirin", !(a && a.id === "ortofoto" && a.chegara));
  if (a) {
    xarita.setPaintProperty(`asos-${a.id}`, "raster-opacity", Number(el("asos-shaffof").value));
    const aniq = a.aniqlik_m != null ? `±${String(a.aniqlik_m).replace(".", ",")} m` : "aniqligi e'lon qilinmagan";
    el("asos-izoh").innerHTML = `<b>${esc(a.nomi)}</b> · ${aniq}. Surat faqat kontekst va qo'pol xatoni ko'rish uchun: o'lchov 2 sm, ` +
      `u suratga moslanmaydi.${a.atributsiya ? `<br><span class="matn3">${esc(a.atributsiya)}</span>` : ""}`;
    el("asos-chip").innerHTML = `${ikon("asos")}<b>${esc(a.nomi)}</b><span>${aniq}</span><span class="matn2">· o'lchov suratga moslanmaydi</span>`;
    el("asos-chip").title = "Surat siljishi o'lchov xatosi emas: tarmoqlar RTK bo'yicha chizilgan (2 sm).";
  }
  try { localStorage.setItem("yerosti_asos", id); } catch {}
}

function masofaHolat(yoq) {
  masofaRejim = yoq;
  if (yoq && orderRejim) tortmaYop();
  document.querySelector("[data-asbob='masofa']").setAttribute("aria-pressed", String(yoq));
  if (xarita) xarita.getCanvas().style.cursor = yoq ? "crosshair" : "";
  const n = el("masofa-natija");
  if (yoq) { n.innerHTML = `${ikon("masofa")}<span>Xaritada ikki nuqtani bosing</span>`; n.classList.remove("yashirin"); }
  else { masofaNuqtalar = []; masofaChiz(); n.classList.add("yashirin"); }
}

/** SY-04: ikki nuqta orasidagi gorizontal masofa va azimut (WGS84 egrilik radiuslari bilan, qisqa masofada mm aniq). */
function masofaHisob(a, b) {
  const R = 6378137, f = 1 / 298.257223563, e2 = f * (2 - f), fi = (a[1] + b[1]) / 2 * Math.PI / 180;
  const w = 1 - e2 * Math.sin(fi) ** 2, N = R / Math.sqrt(w), M = R * (1 - e2) / w ** 1.5;
  const dx = (b[0] - a[0]) * Math.PI / 180 * N * Math.cos(fi), dy = (b[1] - a[1]) * Math.PI / 180 * M;
  return { d: Math.hypot(dx, dy), az: (Math.atan2(dx, dy) * 180 / Math.PI + 360) % 360 };
}

function masofaNuqta(ll) {
  if (masofaNuqtalar.length >= 2) masofaNuqtalar = [];
  masofaNuqtalar.push([ll.lng, ll.lat]);
  masofaChiz();
  const n = el("masofa-natija");
  if (masofaNuqtalar.length === 2) {
    const { d, az } = masofaHisob(...masofaNuqtalar);
    n.innerHTML = `${ikon("masofa")}<b>${son(d, 2)} m</b><span>azimut ${son(az, 1)}°</span><span class="matn2">· yangi o'lchov uchun yana bosing</span>`;
  } else n.innerHTML = `${ikon("masofa")}<span>Ikkinchi nuqtani bosing</span>`;
}

function masofaChiz() {
  if (!xarita || !xarita.getSource("masofa")) return;
  const f = masofaNuqtalar.map((c) => ({ type: "Feature", geometry: { type: "Point", coordinates: c } }));
  if (masofaNuqtalar.length === 2) f.push({ type: "Feature", geometry: { type: "LineString", coordinates: masofaNuqtalar } });
  xarita.getSource("masofa").setData({ type: "FeatureCollection", features: f });
}

/* PD-07: kursor koordinatasi — WGS84 va UTM (Krüger qatori, server/yadro bilan bir xil formula). */
const _F = 1 / 298.257223563, _N = _F / (2 - _F);
const _AA = 6378137 / (1 + _N) * (1 + _N * _N / 4 + _N ** 4 / 64);
const _ALFA = [_N / 2 - 2 * _N ** 2 / 3 + 5 * _N ** 3 / 16, 13 * _N ** 2 / 48 - 3 * _N ** 3 / 5, 61 * _N ** 3 / 240];
function utm(lat, lon) {
  const zona = Math.floor((lon + 180) / 6) + 1, lon0 = zona * 6 - 183;
  const fi = lat * Math.PI / 180, lam = (lon - lon0) * Math.PI / 180, sn = 2 * Math.sqrt(_N) / (1 + _N);
  const t = Math.sinh(Math.atanh(Math.sin(fi)) - sn * Math.atanh(sn * Math.sin(fi)));
  const xi = Math.atan2(t, Math.cos(lam)), eta = Math.atanh(Math.sin(lam) / Math.sqrt(1 + t * t));
  let e = eta, n = xi;
  for (let j = 1; j <= 3; j++) { e += _ALFA[j - 1] * Math.cos(2 * j * xi) * Math.sinh(2 * j * eta); n += _ALFA[j - 1] * Math.sin(2 * j * xi) * Math.cosh(2 * j * eta); }
  return { zona, e: 500000 + 0.9996 * _AA * e, n: 0.9996 * _AA * n + (lat < 0 ? 1e7 : 0) };
}
let koordinataKadr = null;
function koordinataYoz(ll) {
  if (koordinataKadr) return;
  koordinataKadr = requestAnimationFrame(() => {
    koordinataKadr = null;
    const u = utm(ll.lat, ll.lng);
    el("koordinata").innerHTML = `<b>${ll.lat.toFixed(6)}°</b> <b>${ll.lng.toFixed(6)}°</b> · UTM ${u.zona} E <b>${son(u.e, 1)}</b> N <b>${son(u.n, 1)}</b>`;
  });
}

/* ---------- ma'lumot ---------- */

async function malumotYangila(birinchi) {
  const [geo, stat, ob] = await Promise.all([
    so("/api/v1/geojson"), so("/api/v1/statistika"), so("/api/v1/obyektlar"),
  ]);
  geoKesh = geo; statKesh = stat; obyektKesh = ob.obyektlar;
  if (xarita && xarita.getSource("tarmoqlar")) xarita.getSource("tarmoqlar").setData(geo);
  xulosaChiz(stat);
  tarmoqRoyxatChiz(stat);
  sifatRoyxatChiz();
  obyektRoyxatChiz();
  el("bosh-holat").classList.toggle("yashirin", geo.features.length > 0 || obyektKesh.length > 0);
  if (birinchi && geo.features.length) hammasigaUch();
}

function chegara(fs) {
  let b = null;
  for (const f of fs) for (const [lon, lat] of f.geometry.coordinates) {
    if (!b) b = [lon, lat, lon, lat];
    else { b[0] = Math.min(b[0], lon); b[1] = Math.min(b[1], lat); b[2] = Math.max(b[2], lon); b[3] = Math.max(b[3], lat); }
  }
  return b;
}
function hammasigaUch() {
  const b = chegara(geoKesh.features);
  if (b) xarita.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding: 90, duration: 600, maxZoom: 17 });
}
function liniyagaUch(fs) {
  const b = chegara(fs);
  if (b) xarita.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding: { top: 90, bottom: 90, left: 120, right: 120 }, duration: 700, maxZoom: 18 });
}

function xulosaChiz(stat) {
  const km = son(stat.jami_uzunlik_m / 1000, 2);
  el("xulosa").innerHTML =
    `<div><b>${stat.obyekt_soni}</b><span>obyekt</span></div>` +
    `<div><b>${km} km</b><span>tarmoq</span></div>` +
    `<div><b>${stat.skan_soni}</b><span>skan</span></div>`;
  el("tarmoq-km").textContent = `${km} km`;
}

function filtrQollash() {
  if (!xarita || !xarita.getLayer("tarmoq-chiziq")) return;
  const f = ["all", ["in", ["get", "turi"], ["literal", [...faolTurlar]]], ["in", ["get", "sifat"], ["literal", [...faolSifatlar]]]];
  for (const [id, sifatFiltr] of CHIZIQ_QATLAMLAR) xarita.setFilter(id, ["all", sifatFiltr, f]);
  if (xarita.getLayer("tarmoq-yorliq")) xarita.setFilter("tarmoq-yorliq", f);
}

function tarmoqRoyxatChiz(stat) {
  const q = el("tarmoq-royxat");
  q.innerHTML = "";
  for (const [t, m] of Object.entries(TURLAR)) {
    const s = stat.turlar[t] || { uzunlik_m: 0, soni: 0 };
    const qator = document.createElement("label");
    qator.className = "qatlam-qator";
    qator.innerHTML = `<input type="checkbox" ${faolTurlar.has(t) ? "checked" : ""}>` +
      `<span class="rang" style="background:${m.rang}"></span><span>${m.nom}</span>` +
      `<span class="qatlam-km">${son(s.uzunlik_m / 1000, 2)} km</span>`;
    qator.querySelector("input").addEventListener("change", (h) => {
      if (h.target.checked) faolTurlar.add(t); else faolTurlar.delete(t);
      filtrQollash();
    });
    q.appendChild(qator);
  }
}

function sifatRoyxatChiz() {
  const q = el("sifat-royxat");
  q.innerHTML = "";
  for (const [s, [nishon, nom, izoh]] of Object.entries(SIFATLAR)) {
    const n = geoKesh.features.filter((f) => f.properties.sifat === s).length;
    const qator = document.createElement("label");
    qator.className = "qatlam-qator";
    qator.innerHTML = `<input type="checkbox" ${faolSifatlar.has(s) ? "checked" : ""}><span class="nishon ${nishon}">${nom}</span>` +
      `<span class="matn2" style="font-size:var(--f12)">${izoh}</span><span class="qatlam-km">${n}</span>`;
    qator.querySelector("input").addEventListener("change", (h) => {
      if (h.target.checked) faolSifatlar.add(s); else faolSifatlar.delete(s);
      filtrQollash();
    });
    q.appendChild(qator);
  }
}

function obyektStat(id) {
  const fs = geoKesh.features.filter((f) => f.properties.obyekt_id === id);
  const uz = fs.reduce((s, f) => s + f.properties.uzunlik_m, 0);
  const sifat = fs.some((f) => f.properties.sifat === "PAST") ? "PAST" : fs.some((f) => f.properties.sifat === "SKAN") ? "SKAN" : fs.length ? "RASMIY" : null;
  const turlar = [...new Set(fs.map((f) => f.properties.turi))];
  // T-031: hamma SKAN liniyalar RTK bilan tasdiqlangan bo'lsa — obyekt rasmiy darajada
  const tasdiq = fs.length > 0 && fs.every((f) => f.properties.sifat !== "SKAN" || f.properties.tasdiq === "tasdiqlangan");
  return { fs, uz, sifat, turlar, tasdiq };
}

function obyektRoyxatChiz() {
  const q = el("obyekt-royxat");
  const s = el("qidiruv").value.trim().toLowerCase();
  const royxat = s ? obyektKesh.filter((o) => [o.nomi, o.pudratchi, o.order_raqami, o.manzil, o.buyurtmachi].some((x) => (x || "").toLowerCase().includes(s))) : obyektKesh;
  q.innerHTML = "";
  if (!obyektKesh.length) { q.innerHTML = `<div class="royxat-bosh">Hali obyekt yo'q.</div>`; return; }
  if (!royxat.length) { q.innerHTML = `<div class="royxat-bosh">«${esc(s)}» bo'yicha hech narsa topilmadi.</div>`; return; }
  for (const o of royxat.slice(0, 60)) {
    const st = obyektStat(o.id);
    const b = document.createElement("button");
    b.type = "button";
    b.className = "ob-karta";
    b.setAttribute("aria-current", String(tanlanganObyekt === o.id));
    const nishon = st.sifat === "SKAN" && st.tasdiq ? `<span class="nishon nishon-ok">SKAN ✓ RTK</span>`
      : st.sifat ? `<span class="nishon ${SIFATLAR[st.sifat][0]}">${st.sifat}</span>` : `<span class="nishon nishon-kul">${esc(o.holat)}</span>`;
    b.innerHTML = `<span class="ob-nom">${esc(o.nomi)}</span>${nishon}` +
      `<span class="ob-meta">${esc(o.pudratchi || "pudratchi ko'rsatilmagan")} · ${esc(o.order_raqami || "order yo'q")}</span>` +
      `<span class="ob-tarmoq">${st.turlar.map((t) => `<span class="rang" style="background:${(TURLAR[t] || {}).rang || "#334155"}" title="${esc((TURLAR[t] || {}).nom || t)}"></span>`).join("")}` +
      `${st.fs.length ? `${st.fs.length} liniya · ${son(st.uz, 1)} m` : "o'lchov yo'q"}</span>`;
    b.addEventListener("click", () => obyektPanelKorsat(o.id));
    q.appendChild(b);
  }
  if (royxat.length > 60) q.insertAdjacentHTML("beforeend", `<div class="royxat-yana">… yana ${royxat.length - 60} ta — qidiruvni aniqlashtiring</div>`);
}

/* ---------- tanlash ---------- */

function xaritaBosildi(h) {
  if (orderRejim) return orderNuqtaQosh(h.lngLat);
  if (masofaRejim) return masofaNuqta(h.lngLat);
  if (!xarita.getLayer("tarmoq-chiziq")) return;
  const t = xarita.queryRenderedFeatures(h.point, { layers: CHIZIQ_IDLAR });
  if (!t.length) return;
  inspektorLiniya(t[0].properties);
}

function sifatNishon(sifat, rtk) {
  if (sifat === "RASMIY") return `<span class="nishon nishon-ok">RASMIY · RTK FIX</span>`;
  if (sifat === "SKAN") return `<span class="nishon nishon-ogoh">SKAN · RTK tasdig'i kutilmoqda</span>`;
  return `<span class="nishon nishon-xato">PAST ANIQLIK · ${esc(rtk)}</span>`;
}

/* ---------- inspektor ---------- */

function inspektorOch(html) {
  el("inspektor").innerHTML = html;
  el("inspektor").classList.remove("yashirin");
  el("asosiy").classList.add("inspektor-ochiq");
  const y = el("insp-yop");
  if (y) y.addEventListener("click", inspektorYop);
  if (window.innerWidth < 900) tortmaYop();
}
function inspektorYop() {
  el("inspektor").classList.add("yashirin");
  el("asosiy").classList.remove("inspektor-ochiq");
  tanlanganObyekt = null;
  for (const b of document.querySelectorAll(".ob-karta")) b.setAttribute("aria-current", "false");
}
const olchov = (id, qiymat, nom, izoh = "", sinf = "") =>
  `<div class="olchov" id="k-${id}"><b class="${sinf}">${qiymat}</b><span>${nom}</span><small>${izoh}</small></div>`;
function kartaYangila(id, qiymat, izoh, sinf = "") {
  const k = el(`k-${id}`);
  if (!k) return;
  k.querySelector("b").innerHTML = qiymat;
  k.querySelector("b").className = sinf;
  k.querySelector("small").innerHTML = izoh;
}

function inspektorLiniya(p) {
  const m = TURLAR[p.turi] || { nom: p.turi, rang: "#334155" };
  const orqaga = tanlanganObyekt === Number(p.obyekt_id);
  inspektorOch(`<div class="insp-bosh">` +
    `<div class="insp-ustki"><span class="insp-yorliq">${orqaga ? `<button type="button" class="insp-orqaga" id="insp-orqaga">${ikon("orqaga")}Obyekt</button>` : "Liniya"}</span>` +
    `<button type="button" class="ikon-tugma" id="insp-yop" aria-label="Yopish">${ikon("yop")}</button></div>` +
    `<h2 class="insp-nom"><span class="rang" style="background:${m.rang}"></span>${esc(m.nom)}${Number(p.diametr_mm) ? ` Ø${p.diametr_mm}` : ""}</h2>` +
    `<div class="insp-chiplar">${sifatNishon(p.sifat, p.rtk)}${p.sifat === "SKAN" || p.tasdiq === "farq" ? tasdiqNishon(p.tasdiq) : ""}<span class="nishon nishon-kul">v${esc(p.versiya)}</span></div>` +
    `<div class="insp-manzil">${esc(p.obyekt_nomi)}</div>` +
    `<div class="olchovlar">` +
    olchov("l-chuqur", esc(p.chuqurlik_matn || "—"), "chuqurlik", "yer sirtidan quvur ustigacha") +
    olchov("l-uzun", `${son(p.uzunlik_m, 1)} m`, "uzunlik", `${p.nuqta_soni} nuqta`) +
    olchov("l-diam", Number(p.diametr_mm) ? `D${p.diametr_mm}` : "—", "diametr, mm", esc(p.material || "material —")) +
    olchov("l-sana", esc(sanaMatn(p.yaratilgan).slice(0, 10)), "kiritilgan", esc(p.pudratchi || "")) +
    `</div></div>` +
    `<div class="insp-tana"><table class="k-jadval">` +
    `<tr><td>Pudratchi</td><td>${esc(p.pudratchi || "—")}</td></tr>` +
    `<tr><td>Qazish orderi</td><td>${esc(orderMatn(p) || "—")}</td></tr>` +
    `<tr><td>RTK yechimi</td><td>${esc(p.rtk || "—")}</td></tr>` +
    `<tr><td>Sifat izohi</td><td>${SIFATLAR[p.sifat] ? SIFATLAR[p.sifat][2] : "—"}</td></tr>` +
    `<tr><td>RTK tasdig'i (T-031)</td><td>${(TASDIQ_NOMI[p.tasdiq] || ["", p.tasdiq || "—"])[1]}${p.sifat === "SKAN" && p.tasdiq !== "tasdiqlangan" ? " · hujjatga rasmiy kirmaydi" : ""}</td></tr>` +
    `<tr><td>Tarmoq egasi</td><td>${esc(p.egasi || "—")}</td></tr>` +
    `<tr><td>Ishlash holati</td><td>${esc(ISHLASH_NOMI[p.ishlash_holati] || p.ishlash_holati || "—")}${p.ornatilgan_yil ? ` · ${p.ornatilgan_yil} y.` : ""}${p.parametr ? ` · ${esc(p.parametr)}` : ""}</td></tr>` +
    `<tr><td>Sifat darajasi</td><td>PAS 128 / ASCE 38 QL-A: ochib bevosita o'lchangan</td></tr>` +
    (p.izoh ? `<tr><td>Izoh</td><td>${esc(p.izoh)}</td></tr>` : "") +
    `</table>` +
    `<div class="tugmalar-qator" style="padding-top:14px">` +
    `<button type="button" class="tugma-oddiy" id="l-uch">${ikon("xarita")}Xaritada</button>` +
    (orqaga ? "" : `<button type="button" class="tugma-oddiy" id="l-obyekt">Obyektni ochish</button>`) +
    (yozuvchi() && men.rol !== "dala" ? `<button type="button" class="tugma-oddiy" id="l-tahrir">Atributlar</button>` +
      `<button type="button" class="tugma-oddiy" id="l-belgi" title="Quduq, zadvijka yoki burilishga QR plastinka (T1)">QR-belgi</button>` : "") +
    `</div></div>`);
  const th = el("l-tahrir");
  if (th) th.addEventListener("click", () => liniyaTahrirModal(p));
  const lb = el("l-belgi");
  if (lb) lb.addEventListener("click", () => belgiModal(p));
  const f = geoKesh.features.find((x) => x.properties.id === Number(p.id));
  el("l-uch").addEventListener("click", () => { if (f) liniyagaUch([f]); });
  const ob = el("l-obyekt");
  if (ob) ob.addEventListener("click", () => obyektPanelKorsat(Number(p.obyekt_id)));
  const orq = el("insp-orqaga");
  if (orq) orq.addEventListener("click", () => obyektPanelKorsat(Number(p.obyekt_id)));
}

async function obyektPanelKorsat(obyektId) {
  const o = obyektKesh.find((x) => x.id === obyektId);
  if (!o) return;
  tanlanganObyekt = obyektId;
  for (const b of document.querySelectorAll(".ob-karta")) b.setAttribute("aria-current", "false");
  const st = obyektStat(obyektId), liniyalar = st.fs;
  const tahrirTugma = yozuvchi() ? `<button type="button" class="tugma-oddiy" id="o-tahrir" title="Nomi, manzil, buyurtmachi, pudratchi, qazish orderi">Rekvizitlar</button>` : "";
  inspektorOch(`<div class="insp-bosh">` +
    `<div class="insp-ustki"><span class="insp-yorliq">Obyekt</span><button type="button" class="ikon-tugma" id="insp-yop" aria-label="Yopish">${ikon("yop")}</button></div>` +
    `<h2 class="insp-nom">${esc(o.nomi)}</h2>` +
    `<div class="insp-chiplar"><span class="nishon nishon-kul">${esc(o.holat)}</span>` +
    (st.sifat ? `<span class="nishon ${SIFATLAR[st.sifat][0]}">${st.sifat === "RASMIY" ? "barcha liniyalar RASMIY" : st.sifat === "SKAN" ? "SKAN liniyalar bor" : "PAST liniyalar bor"}</span>` : "") +
    `<span class="nishon nishon-kul" id="k-yaroq">hujjat holati …</span></div>` +
    `<div class="insp-manzil">${esc(o.manzil || "manzil ko'rsatilmagan")}</div>` +
    `<div class="olchovlar">` +
    olchov("tarmoq", `${liniyalar.length}`, "liniya", liniyalar.length ? `${son(st.uz, 1)} m · ${st.turlar.map((t) => (TURLAR[t] || {}).nom || t).join(", ")}` : "o'lchov yo'q") +
    olchov("skan", "…", "skan", "") +
    olchov("hujjat", "…", "ijro hujjati", "") +
    olchov("asos", "…", "geodezik asos", "") +
    `</div>` +
    `<div class="tablar" role="tablist">${TABLAR.map(([id, nom]) => `<button type="button" role="tab" data-tab="${id}" aria-selected="${id === faolTab}">${nom}</button>`).join("")}</div>` +
    `</div><div class="insp-tana">` +
    `<div data-tana="umumiy"><table class="k-jadval">` +
    `<tr><td>Buyurtmachi</td><td>${esc(o.buyurtmachi || "—")}</td></tr>` +
    `<tr><td>Pudratchi</td><td>${esc(o.pudratchi || "—")}</td></tr>` +
    `<tr><td>Qazish orderi</td><td>${esc(orderMatn(o) || "—")}</td></tr>` +
    (o.tarmoq_egasi ? `<tr><td>Tarmoq egasi</td><td>${esc(o.tarmoq_egasi)}</td></tr>` : "") +
    `<tr><td>Yaratilgan</td><td>${esc(sanaMatn(o.yaratilgan))}</td></tr>` +
    `<tr><td>Holat</td><td>${esc(o.holat)}</td></tr>` +
    `</table>` +
    (liniyalar.length ? `<div class="tugmalar-qator" style="padding-top:14px">` +
      `<button type="button" class="tugma-oddiy" id="o-xaritada">${ikon("xarita")}Xaritada</button>` +
      `<a class="tugma-oddiy" href="/api/v1/chizma?obyekt_id=${o.id}&format=dxf">DXF ijro chizmasi</a>` +
      `<a class="tugma-oddiy" href="/api/v1/chizma?obyekt_id=${o.id}&format=csv">Koordinata katalogi</a>` +
      `<a class="tugma-oddiy" href="/api/v1/chizma?obyekt_id=${o.id}&format=ifc" title="IFC 4.3: IfcPipeSegment, IfcMapConversion bilan georeferens (BIM)">IFC 4.3 (BIM)</a>` + tahrirTugma + `</div>`
      : (tahrirTugma ? `<div class="tugmalar-qator" style="padding-top:14px">${tahrirTugma}</div>` : "") + `<div class="k-bosh" style="margin-top:10px">Hali o'lchov yo'q — iPhone dala ilovasi orqali yuboriladi. Geodezik asos punktlarini hozirdan kiritish mumkin («Asos»).</div>`) +
    `</div>` +
    `<div data-tana="liniya" class="yashirin"><div class="k-bolim">Liniyalar</div><div class="k-royxat" id="o-liniyalar"></div>` +
    `<div class="k-bosh" id="o-graf"></div>` +
    `<div class="k-bolim">Quvur tasdig'i (T-031): skan o'qi RTK bilan</div><div class="k-royxat" id="o-tasdiq"><div class="k-bosh">Yuklanmoqda…</div></div>` +
    `<div class="k-bolim">QR-belgilar (quduq, zadvijka, burilish)</div><div class="k-royxat" id="o-belgilar"><div class="k-bosh">Yuklanmoqda…</div></div>` +
    `<div class="k-bolim">Skan fayllari</div><div class="k-royxat" id="o-skanlar"><div class="k-bosh">Yuklanmoqda…</div></div>` +
    `<div class="k-bolim">Mustaqil qayta hisob (data markaz)</div><div class="k-royxat" id="o-tahlillar"><div class="k-bosh">Yuklanmoqda…</div></div>` +
    (yozuvchi() && men.rol !== "dala" ? `<div class="tugmalar-qator" style="padding-top:8px"><button type="button" class="tugma-oddiy" id="tashqi-yukla">Tashqi LiDAR skan (LAS/PLY)</button></div>` : "") + `</div>` +
    `<div data-tana="asos" class="yashirin"><div id="o-asos" class="k-royxat"><div class="k-bosh">Yuklanmoqda…</div></div></div>` +
    `<div data-tana="hujjat" class="yashirin"><div id="o-ijro" class="k-royxat"><div class="k-bosh">Yuklanmoqda…</div></div></div>` +
    `<div data-tana="loyiha" class="yashirin"><div id="o-loyiha" class="k-royxat"><div class="k-bosh">Yuklanmoqda…</div></div></div>` +
    `<div data-tana="ulash" class="yashirin"><div id="o-ulash" class="k-royxat"><div class="k-bosh">Yuklanmoqda…</div></div></div>` +
    `<div data-tana="tarix" class="yashirin"><div id="o-tarix"><div class="k-bosh">Yuklanmoqda…</div></div></div>` +
    `</div>`);
  for (const t of el("inspektor").querySelectorAll("[data-tab]")) t.addEventListener("click", () => tabTanla(t.dataset.tab));
  tabTanla(faolTab);
  const lq = el("o-liniyalar");
  if (!liniyalar.length) lq.innerHTML = `<div class="k-bosh">Hali o'lchov yo'q.</div>`;
  for (const f of liniyalar) {
    const p = f.properties, m = TURLAR[p.turi] || { nom: p.turi, rang: "#334155" };
    const q = document.createElement("div");
    q.className = "k-qator";
    q.style.borderLeftColor = m.rang;
    q.innerHTML = `<b>${esc(m.nom)}</b>${Number(p.diametr_mm) ? ` D${p.diametr_mm}` : ""} ${esc(p.chuqurlik_matn || "")}` +
      `<span class="ong">${son(p.uzunlik_m, 0)} m</span><span class="nishon ${SIFATLAR[p.sifat] ? SIFATLAR[p.sifat][0] : "nishon-kul"}">${esc(p.sifat)}</span>` +
      (p.sifat === "SKAN" || p.tasdiq === "farq" ? tasdiqNishon(p.tasdiq) : "");
    q.addEventListener("click", () => { liniyagaUch([f]); inspektorLiniya(p); });
    lq.appendChild(q);
  }
  const xb = el("o-xaritada");
  if (xb) xb.addEventListener("click", () => liniyagaUch(liniyalar));
  const ty = el("tashqi-yukla");
  if (ty) ty.addEventListener("click", () => tashqiModal(o));
  const ot = el("o-tahrir");
  if (ot) ot.addEventListener("click", () => obyektTahrirModal(o));
  grafBolim(o, liniyalar.length);
  belgiBolim(o);
  skanBolim(o);
  tasdiqBolim(o, liniyalar);
  asosBolim(o);
  ijroBolim(o, liniyalar.length);
  loyihaBolim(o);
  ulashBolim(o);
  tarixBolim(o);
  if (liniyalar.length) liniyagaUch(liniyalar);
}

function tabTanla(id) {
  faolTab = id;
  for (const t of el("inspektor").querySelectorAll("[data-tab]")) t.setAttribute("aria-selected", String(t.dataset.tab === id));
  for (const t of el("inspektor").querySelectorAll("[data-tana]")) t.classList.toggle("yashirin", t.dataset.tana !== id);
}

async function skanBolim(o) {
  let skanlar = [], tahlillar = [];
  try { skanlar = (await so(`/api/v1/skanlar?obyekt_id=${o.id}`)).skanlar; } catch {}
  try { tahlillar = (await so(`/api/v1/tahlillar?obyekt_id=${o.id}`)).tahlillar; } catch {}
  if (tanlanganObyekt !== o.id || !el("o-skanlar")) return;
  const tayyor = skanlar.filter((s) => s.holat === "tayyor").length;
  kartaYangila("skan", skanlar.length, skanlar.length ? `${tayyor} tayyor · ${son(skanlar.reduce((s, x) => s + x.hajmi, 0) / 1048576, 1)} MB` : "skan yo'q");
  let h = skanlar.length ? "" : `<div class="k-bosh">Skan yo'q.</div>`;
  for (const s of skanlar) {
    const holat = s.holat === "tayyor" ? `<span class="nishon nishon-ok">tayyor</span>`
      : s.holat === "xato" ? `<span class="nishon nishon-xato">xato</span>`
      : `<span class="nishon nishon-ogoh">${s.qabul_bolaklar}/${s.bolak_soni}</span>`;
    h += `<div class="k-qator k-tahlil"><b>${esc(SKAN_NOMLARI[s.turi] || s.turi)}</b>` +
      (s.rms_sm != null ? ` RMS ${son(s.rms_sm, 1)} sm` : "") +
      `<span class="ong">${son(s.hajmi / 1048576, 1)} MB</span>${holat}</div>`;
  }
  el("o-skanlar").innerHTML = h;
  el("o-tahlillar").innerHTML = tahlillar.length ? tahlillar.map(tahlilQatori).join("")
    : `<div class="k-bosh">Muhrlangan skan tasdiqlangach, server uni telefon bilan bir xil yadroda qayta hisoblaydi.</div>`;
}

/* ---------- 20-bo'lim: tarmoq grafi (KU-03) va liniya atributlari (KU-02) ---------- */

const ISHLASH_NOMI = { loyiha: "loyiha", qurilmoqda: "qurilmoqda", ishlayapti: "ishlayapti", ishlamayapti: "ishlamayapti",
  tark_etilgan: "tark etilgan", olib_tashlangan: "olib tashlangan" };

async function grafBolim(o, soni) {
  const q = el("o-graf");
  if (!q || !soni) { if (q) q.textContent = ""; return; }
  try {
    const g = await so(`/api/v1/obyekt/${o.id}/graf`);
    if (tanlanganObyekt !== o.id || !el("o-graf")) return;
    const x = g.xulosa;
    el("o-graf").innerHTML = `Topologiya (MUDDI tarmoq modeli): <b>${x.tugun}</b> tugun · uchlar ${x.uch} · tutashuv ${x.tutashuv} · ` +
      `tarmoqlanish ${x.tarmoqlanish}` + (x.turli_tarmoq_tutashuvi ? ` · <span class="xato-matn">turli tarmoq tutashuvi ${x.turli_tarmoq_tutashuvi} — tekshiring</span>` : "") +
      ` · sifat darajasi PAS 128 / ASCE 38: QL-A (ochib bevosita o'lchangan)`;
  } catch (x) { el("o-graf").textContent = x.message; }
}

/* ---------- T1: QR-belgilar ---------- */

const BELGI_TURI = { quduq: "Quduq", zadvijka: "Zadvijka", burilish: "Burilish", ulanish: "Ulanish", boshqa: "Belgi" };

async function belgiBolim(o) {
  const quti = el("o-belgilar");
  if (!quti || tanlanganObyekt !== o.id) return;
  let b;
  try { b = (await so(`/api/v1/belgilar?obyekt_id=${o.id}`)).belgilar; } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  if (tanlanganObyekt !== o.id || !el("o-belgilar")) return;
  const amal = b.filter((x) => x.holat === "amal");
  let h = b.length ? "" : `<div class="k-bosh">Belgi yo'q. Liniyani tanlab «QR-belgi» tugmasini bosing: quduq yoki zadvijkaga plastinka.</div>`;
  for (const x of b) {
    h += `<div class="k-qator"><b>${esc(x.raqam)}</b> ${esc(BELGI_TURI[x.tur] || x.tur)} · liniya #${x.liniya_id}` +
      (x.chuqurlik_m != null ? ` · ${son(x.chuqurlik_m, 2)} m` : "") +
      `<span class="ong"><a class="k-havola" href="${esc(x.url)}" target="_blank" rel="noopener">ochish</a></span>` +
      (x.holat === "amal" ? `<span class="nishon nishon-kul">${x.korishlar} marta</span>` : `<span class="nishon nishon-xato">bekor</span>`) +
      (men.rol === "admin" && x.holat === "amal" ? `<div class="k-sabab"><button type="button" class="k-havola tugma-matn" data-belgi-bekor="${x.id}">bekor qilish</button></div>` : "") +
      `</div>`;
  }
  if (yozuvchi() && amal.length) h += `<div class="tugmalar-qator" style="padding-top:6px"><a class="tugma-oddiy" href="/api/v1/belgilar/plastinka.pdf?obyekt_id=${o.id}">Plastinkalar (PDF, A4 da 8 ta)</a></div>`;
  quti.innerHTML = h;
  for (const t of quti.querySelectorAll("[data-belgi-bekor]")) {
    t.addEventListener("click", async () => {
      const sabab = prompt("Bekor qilish sababi (QR skanerlanganda ko'rinadi):");
      if (!sabab) return;
      try { await so(`/api/v1/belgi/${t.dataset.belgiBekor}/bekor`, "POST", { sabab }); belgiBolim(o); } catch (x) { alert(x.message); }
    });
  }
}

function belgiModal(p) {
  const f = geoKesh.features.find((x) => x.properties.id === Number(p.id));
  const k = f ? f.geometry.coordinates : [];
  const R = 6371000, rad = Math.PI / 180;
  let pk = 0;
  const tanlov = k.map((c, i) => {
    if (i) {
      const [a, b] = [k[i - 1], c];
      const dlat = (b[1] - a[1]) * rad, dlon = (b[0] - a[0]) * rad;
      const h = Math.sin(dlat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dlon / 2) ** 2;
      pk += 2 * R * Math.asin(Math.sqrt(h));
    }
    return `<option value="${i}">nuqta ${i + 1} · pikitaj ${son(pk, 1)} m</option>`;
  }).join("");
  modalOch(`Liniya #${p.id}: QR-belgi`, `<form id="belgi-forma" class="forma" autocomplete="off">` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Belgi o'lchangan nuqtada turadi: QR kirishsiz faqat tarmoq turi va egasini, xodimga esa chuqurlik va atrofdagi tarmoqlarni ko'rsatadi.</p>` +
    `<label>Turi<select name="tur">${Object.entries(BELGI_TURI).map(([v, n]) => `<option value="${v}">${n}</option>`).join("")}</select></label>` +
    `<label>Raqami (plastinkada)<input name="raqam" required maxlength="20" placeholder="Q-1"></label>` +
    `<label class="toliq">Nuqta<select name="nuqta">${tanlov}</select></label>` +
    `<label class="toliq">Aloqa (tarmoq egasi navbatchi telefoni)<input name="aloqa" maxlength="60" placeholder="ixtiyoriy"></label>` +
    `<label class="toliq">Izoh<input name="izoh" maxlength="300"></label>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="belgi-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Belgini yaratish</button></div>` +
    `<div id="belgi-xato" class="xato-matn toliq"></div></form>`);
  el("belgi-bekor").addEventListener("click", modalYop);
  el("belgi-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target);
    try {
      await so("/api/v1/belgilar", "POST", { liniya_id: Number(p.id), nuqta: Number(fd.get("nuqta")), tur: fd.get("tur"),
        raqam: String(fd.get("raqam")).trim(), aloqa: String(fd.get("aloqa")).trim(), izoh: String(fd.get("izoh")).trim() });
      modalYop();
      faolTab = "liniya";   // yangi belgi obyekt panelining «Liniya» bo'limidagi ro'yxatda ko'rinadi
      obyektPanelKorsat(Number(p.obyekt_id));
    } catch (x) { el("belgi-xato").textContent = x.message; }
  });
}

function liniyaTahrirModal(p) {
  const tanlov = Object.entries(ISHLASH_NOMI).map(([k, v]) => `<option value="${k}" ${k === (p.ishlash_holati || "ishlayapti") ? "selected" : ""}>${v}</option>`).join("");
  modalOch(`Liniya #${p.id} atributlari`, `<form id="liniya-forma" class="forma" autocomplete="off">` +
    `<label>Material<input name="material" maxlength="100" value="${esc(p.material || "")}"></label>` +
    `<label>Diametr, mm<input name="diametr_mm" type="number" min="0" max="5000" value="${Number(p.diametr_mm) || 0}"></label>` +
    `<label>Tarmoq egasi (operator)<input name="egasi" maxlength="120" value="${esc(p.egasi || "")}" placeholder="masalan: Jizzax Suvsoz"></label>` +
    `<label>Ishlash holati<select name="ishlash_holati">${tanlov}</select></label>` +
    `<label>O'rnatilgan yil<input name="ornatilgan_yil" type="number" min="1900" max="2100" value="${p.ornatilgan_yil || ""}"></label>` +
    `<label>Ish parametri<input name="parametr" maxlength="60" value="${esc(p.parametr || "")}" placeholder="0,6 MPa · 10 kV"></label>` +
    `<label class="toliq">Izoh<input name="izoh" maxlength="500" value="${esc(p.izoh || "")}"></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Geometriya va sifat o'zgarmaydi — faqat tavsif (MUDDI / NUAR atributlari). O'zgarish jurnalga yoziladi.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="liniya-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Saqlash</button></div>` +
    `<div id="liniya-xato" class="xato-matn toliq"></div></form>`);
  el("liniya-bekor").addEventListener("click", modalYop);
  el("liniya-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), t = {};
    for (const [k, v] of fd.entries()) t[k] = String(v).trim();
    try {
      await so(`/api/v1/liniya/${p.id}`, "POST", t);
      modalYop();
      await malumotYangila(false);
      const f = geoKesh.features.find((x) => x.properties.id === Number(p.id));
      if (f) inspektorLiniya(f.properties);
    } catch (x) { el("liniya-xato").textContent = x.message; }
  });
}

/* ---------- 18-bo'lim: quvur tasdig'i (TQ, T-031) ---------- */

async function tasdiqBolim(o, liniyalar) {
  const quti = el("o-tasdiq");
  if (!quti || tanlanganObyekt !== o.id) return;
  let t;
  try { t = await so(`/api/v1/obyekt/${o.id}/tasdiq`); } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  if (tanlanganObyekt !== o.id || !el("o-tasdiq")) return;
  const ch = t.chegaralar || {};
  const skanLin = liniyalar.filter((f) => f.properties.sifat === "SKAN");
  let h = "";
  if (!skanLin.length) h += `<div class="k-bosh">Skan liniyasi yo'q: barcha nuqtalar RTK bilan to'g'ridan-to'g'ri o'lchangan, tasdiq shart emas.</div>`;
  for (const f of skanLin) {
    const p = f.properties, hl = (t.liniyalar || {})[p.id] || { holat: "yoq", soni: 0, otgan: 0, kamchiliklar: [] };
    const rang = hl.holat === "tasdiqlangan" ? "var(--ok)" : hl.holat === "farq" ? "var(--xato)" : "var(--ogoh)";
    h += `<div class="k-qator k-tahlil" style="border-left-color:${rang}"><b>#${p.id} ${esc((TURLAR[p.turi] || {}).nom || p.turi)}</b>` +
      `<span class="ong">${hl.otgan}/${hl.soni} tasdiq${hl.maks_gor != null ? ` · maks ${sm(hl.maks_gor)}/${sm(hl.maks_ver)} sm` : ""}</span>${tasdiqNishon(hl.holat)}` +
      `<div class="k-sabab">${hl.kamchiliklar && hl.kamchiliklar.length ? esc(hl.kamchiliklar.join("; ")) : hl.holat === "tasdiqlangan" ? "Boshi, oxiri, burilishlar tasdiqlangan, oraliq ≤ 50 m: SKAN nuqtalar hujjatga rasmiy kiradi." : ""}` +
      (hl.kerakli && hl.kerakli.length ? `<br>Kerakli joylar: ${hl.kerakli.map((k) => `${esc(k.turi)} ${esc(k.pk)}`).join(", ")}` : "") + `</div></div>`;
  }
  const ts = t.tasdiqlar || [];
  for (const x of ts) {
    h += `<div class="k-qator k-tahlil" style="border-left-color:${x.otdi ? "var(--ok)" : "var(--xato)"}"><b>${esc(x.nomi || "T" + x.id)}</b> ` +
      `${x.liniya_id ? `#${x.liniya_id} ${esc(x.pk || "")}` : "liniyaga bog'lanmagan"} · ${esc((ch.joylar || {})[x.joy] || x.joy)}` +
      `<span class="ong">${x.d_gor == null ? "—" : sm(x.d_gor)} / ${x.d_ver == null ? "—" : sm(x.d_ver)} sm</span>` +
      `<span class="nishon ${x.otdi ? "nishon-ok" : "nishon-xato"}">${x.otdi ? "chegarada" : "tashqarida"}</span>` +
      `<div class="k-sabab">${esc(sanaMatn(x.vaqt))} · σ ${son(x.sigma_h_sm, 1)}/${son(x.sigma_v_sm, 1)} sm · ${esc(x.manba || "rtk")}` +
      (x.sabab ? ` · ${esc(x.sabab)}` : "") +
      (yozuvchi() && men.rol !== "dala" ? ` · <button type="button" class="k-havola tugma-matn" data-tasdiq-bekor="${x.id}">bekor qilish</button>` : "") + `</div></div>`;
  }
  if (!ts.length && skanLin.length) h += `<div class="k-bosh">Tasdiq o'lchovi yo'q. Dalada vexa uchini quvur ustiga qo'yib RTK FIX bilan o'lchang (iPhone ilovasi «Quvur tasdig'i» yoki Emlid Flow, keyin CSV import). Chegara: gorizontal ≤ ${son((ch.gor_m || 0.05) * 100, 0)} sm, vertikal ≤ ${son((ch.ver_m || 0.08) * 100, 0)} sm.</div>`;
  if (yozuvchi() && liniyalar.length) h += `<div class="tugmalar-qator" style="padding-top:6px"><button type="button" class="tugma-oddiy" id="tasdiq-import">RTK tasdiq CSV import</button></div>`;
  quti.innerHTML = h;
  const b = el("tasdiq-import");
  if (b) b.addEventListener("click", () => tasdiqModal(o));
  for (const bt of quti.querySelectorAll("[data-tasdiq-bekor]")) {
    bt.addEventListener("click", async () => {
      if (!confirm("Tasdiq o'lchovi bekor qilinsinmi?")) return;
      try { await so(`/api/v1/obyekt/${o.id}/tasdiq/${bt.dataset.tasdiqBekor}/bekor`, "POST", {}); await malumotYangila(false); obyektPanelKorsat(o.id); }
      catch (x) { alert(x.message); }
    });
  }
}

/* ---------- 19-bo'lim: tashqi LiDAR (LD-02) — LAS/PLY bo'lakli yuklash + tahlil navbati ---------- */

async function sha256hex(buf) {
  const h = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Skan API bilan bo'lakli yuklash (server har bo'lak va butun fayl xeshini tekshiradi). */
async function faylYukla(obyektId, turi, fayl, holat) {
  const buf = await fayl.arrayBuffer();
  const sha = await sha256hex(buf);
  const b = await so("/api/v1/skan/boshla", "POST", { obyekt_id: obyektId, turi, hajmi: buf.byteLength, sha256: sha });
  for (let i = 0; i < b.bolak_soni; i++) {
    const bolak = buf.slice(i * b.bolak_hajmi, Math.min(buf.byteLength, (i + 1) * b.bolak_hajmi));
    const r = await fetch(`/api/v1/skan/${b.skan_id}/bolak/${i}`, { method: "PUT", credentials: "same-origin", body: bolak,
      headers: { "X-Yerosti": "1", "Content-Type": "application/octet-stream", "X-Bolak-SHA256": await sha256hex(bolak) } });
    if (!r.ok) { const m = await r.json().catch(() => ({})); throw new Error(m.xato || `bo'lak ${i}: xato ${r.status}`); }
    if (holat) holat(`${i + 1} / ${b.bolak_soni} bo'lak`);
  }
  const y = await so(`/api/v1/skan/${b.skan_id}/yakunla`, "POST", {});
  if (y.holat !== "tayyor") throw new Error(y.xato || "fayl tekshiruvdan o'tmadi");
  return b.skan_id;
}

function tashqiModal(o) {
  modalOch("Tashqi LiDAR skan (LD-02)", `<p class="matn2" style="margin-bottom:8px">SLAM skaner yoki boshqa qurilmadan georeferensli ` +
    `nuqta buluti: LAS 1.2–1.4 (siqilmagan; LAZ ni avval oching) yoki PLY. Server quvurlarni telefon bilan bir xil yadroda topadi va ` +
    `SKAN liniyalar yaratadi — ular quvur ustidagi RTK tasdig'i (T-031) bilan tekshirilgach rasmiy bo'ladi. Georeferens fayldan olinadi, ` +
    `mustaqil tekshirilmaydi (muhr yo'q). Fayl ≤ 300 MB.</p>` +
    `<form id="tashqi-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">Fayl (.las / .ply) *<input name="fayl" type="file" accept=".las,.ply" required></label>` +
    `<label>Koordinata tizimi<select name="koordinata"><option value="utm">UTM (E, N, H ellipsoid)</option>` +
    `<option value="wgs84">WGS84 (X = lon, Y = lat, H ellipsoid)</option><option value="mahalliy">mahalliy tizim (lokalizatsiya bo'yicha)</option></select></label>` +
    `<label>UTM zonasi<input name="zona" type="number" min="1" max="60" value="42"></label>` +
    `<label>Skaner / manba *<input name="manba" required maxlength="120" placeholder="masalan: CHCNAV RS10, RTK-SLAM"></label>` +
    `<label>E'lon qilingan aniqlik, sm *<input name="aniqlik" type="number" step="0.1" min="0.1" max="50" value="3" required></label>` +
    `<label class="toliq">Tarmoq turi *<select name="tarmoq">${Object.entries(TURLAR).map(([k, v]) => `<option value="${k}">${v.nom}</option>`).join("")}</select></label>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="tashqi-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Yuklash va tahlil</button></div>` +
    `<div id="tashqi-holat" class="matn2 toliq" style="font-size:var(--f12)"></div><div id="tashqi-xato" class="xato-matn toliq"></div></form>`);
  el("tashqi-bekor").addEventListener("click", modalYop);
  el("tashqi-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), f = fd.get("fayl");
    if (!f || !f.size) return;
    const tugma = h.target.querySelector("[type=submit]");
    tugma.disabled = true;
    const holat = el("tashqi-holat");
    try {
      const turi = f.name.toLowerCase().endsWith(".ply") ? "nuqta_ply" : "nuqta_las";
      const sid = await faylYukla(o.id, turi, f, (m) => { holat.textContent = `Yuklanmoqda: ${m}`; });
      holat.textContent = "Tahlil navbatga qo'yilmoqda…";
      await so(`/api/v1/obyekt/${o.id}/tashqi-skan`, "POST", { skan_id: sid, koordinata: fd.get("koordinata"), zona: Number(fd.get("zona")),
        manba: String(fd.get("manba")).trim(), aniqlik_sm: Number(fd.get("aniqlik")), tarmoq_turi: fd.get("tarmoq") });
      modalYop();
      obyektPanelKorsat(o.id);
    } catch (x) { tugma.disabled = false; holat.textContent = ""; el("tashqi-xato").textContent = x.message; }
  });
}

function tasdiqModal(o) {
  modalOch("Quvur tasdig'i: RTK o'lchovlarini import qilish", `<p class="matn2" style="margin-bottom:8px">Vexa uchi quvur USTIDA turganda ` +
    `olingan RTK FIX nuqtalari. Emlid Flow «All columns» CSV yoki oddiy shakl: nomi; lat; lon; h_ellipsoid; σH_sm; σV_sm; joy. ` +
    `Tavsif/kodda «oq» bo'lsa — vexa ochiq uchida o'qda. Faqat FIX, σH ≤ 2 sm, σV ≤ 5 sm (T-103). Server har nuqtani eng yaqin ` +
    `liniyaga bog'lab skan o'qidan og'ishini hisoblaydi.</p>` +
    `<form id="tasdiq-forma" class="forma"><label class="toliq">CSV fayl<input name="fayl" type="file" accept=".csv,.txt"></label>` +
    `<label class="toliq">yoki matn<textarea name="csv" rows="4" class="mono-maydon" placeholder="nomi;lat;lon;h;σH_sm;σV_sm;joy"></textarea></label>` +
    `<label>Standart joy<select name="joy"><option value="usti">quvur usti</option><option value="oq">quvur o'qi (ochiq uchi)</option></select></label>` +
    `<div class="forma-tugmalar toliq"><button type="submit" class="tugma-asosiy">Import</button></div>` +
    `<div id="tasdiq-xato" class="xato-matn toliq"></div></form>`);
  el("tasdiq-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), f = fd.get("fayl");
    const csv = f && f.size ? await f.text() : String(fd.get("csv") || "");
    if (!csv.trim()) return;
    try {
      const m = await so(`/api/v1/obyekt/${o.id}/tasdiq`, "POST", { csv, joy: fd.get("joy") });
      modalYop();
      await malumotYangila(false);
      obyektPanelKorsat(o.id);
      if (m.xatolar.length) alert(`Qabul qilindi: ${m.idlar.length}. Rad etildi:\n${m.xatolar.join("\n")}`);
    } catch (x) { el("tasdiq-xato").textContent = x.message; }
  });
}

/* ---------- 14-bo'lim: ijro hujjati, loyiha, ulashish, tarix ---------- */

async function ijroBolim(o, liniyaSoni) {
  const quti = el("o-ijro");
  if (!quti || tanlanganObyekt !== o.id) return;
  let hujjatlar = [];
  try { hujjatlar = (await so(`/api/v1/ijro-hujjatlar?obyekt_id=${o.id}`)).hujjatlar; }
  catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  // ShN-05: yaroqlilik belgisi va karta faqat ijro s'yomkasi hujjatlaridan; dalolatnomalar alohida turda
  const amal = hujjatlar.filter((d) => d.holat === "amal" && (d.tur || "ijro") === "ijro");   // muvofiqlik va dalolatnoma alohida
  const oxirgi = amal[0] && amal[0].xulosa ? amal[0].xulosa : null;
  const yaroq = el("k-yaroq");
  if (yaroq) {
    if (!amal.length) { yaroq.textContent = "ijro hujjati yo'q"; yaroq.className = "nishon nishon-kul"; }
    else if (oxirgi && oxirgi.yaroqli === true) { yaroq.textContent = "topshirishga yaroqli"; yaroq.className = "nishon nishon-ok"; }
    else if (oxirgi && oxirgi.yaroqli === false) { yaroq.textContent = "hujjat topshirishga yaroqsiz"; yaroq.className = "nishon nishon-xato"; }
    else { yaroq.textContent = `${amal.length} hujjat amalda`; yaroq.className = "nishon nishon-kul"; }
  }
  kartaYangila("hujjat", amal.length, amal.length ? `oxirgisi ${esc(sanaMatn(amal[0].yaratilgan).slice(0, 10))}` + (oxirgi && oxirgi.tizim ? ` · ${esc(oxirgi.tizim)}` : "") : "hali yasalmagan",
    oxirgi ? (oxirgi.yaroqli === true ? "ok" : oxirgi.yaroqli === false ? "xato" : "") : "");
  let h = "";
  if (!hujjatlar.length) h += `<div class="k-bosh">Hujjat hali yo'q. Reja, koordinatalar katalogi, har liniyaga bo'ylama profil va sifat varag'i bitta A3 PDF da; har varaqda QR bilan tekshiriladi.</div>`;
  for (const d of hujjatlar) {
    const x = d.xulosa || {};
    const nishon = d.holat === "amal" ? `<span class="nishon nishon-ok">amalda</span>` : `<span class="nishon nishon-xato">bekor</span>`;
    if (d.tur === "muvofiqlik") {
      h += `<div class="k-qator k-tahlil"><b>${esc(d.raqam)}</b> loyiha–ijro muvofiqligi` +
        `<span class="ong"><a class="k-havola" href="/api/v1/ijro-hujjat/${d.id}.pdf">${ikon("pdf")}PDF</a></span>${nishon}` +
        `<div class="k-sabab">${esc(x.sana || sanaMatn(d.yaratilgan))} · ${d.varaqlar} varaq · ` +
        (x.tashqari ? `<span class="nishon nishon-xato">me'yordan tashqari: ${x.tashqari}</span>` : `<span class="nishon nishon-ok">me'yordan tashqari yo'q</span>`) +
        (x.noaniq ? ` · noaniq ${x.noaniq}` : "") + (x.qurilmagan_m ? ` · qurilmagan ${son(x.qurilmagan_m, 1)} m` : "") +
        (men.rol === "admin" && d.holat === "amal" ? ` · <button type="button" class="k-havola tugma-matn" data-hujjat-bekor="${d.id}">bekor qilish</button>` : "") +
        `</div></div>`;
      continue;
    }
    if (d.tur === "yopiq") {
      h += `<div class="k-qator k-tahlil"><b>${esc(d.raqam)}</b> yopiq ishlar dalolatnomasi` +
        `<span class="ong"><a class="k-havola" href="/api/v1/ijro-hujjat/${d.id}.pdf">${ikon("pdf")}PDF</a></span>${nishon}` +
        `<div class="k-sabab">${esc(x.sana || sanaMatn(d.yaratilgan))} · ${d.varaqlar} varaq · ${x.liniyalar || 0} liniya, ${son(x.uzunlik_m, 1)} m · ` +
        `muhr ${x.muhrlar || 0}, rasm ${x.rasmlar || 0} · ` +
        (x.toliq ? `<span class="nishon nishon-ok">dalil to'liq</span>` : `<span class="nishon nishon-xato">dalil to'liq emas: ${x.kamchiliklar_soni || 0}</span>`) +
        (d.holat === "bekor" ? ` · bekor: ${esc(d.bekor_sabab)}` : "") +
        (men.rol === "admin" && d.holat === "amal" ? ` · <button type="button" class="k-havola tugma-matn" data-hujjat-bekor="${d.id}">bekor qilish</button>` : "") +
        `</div></div>`;
      continue;
    }
    h += `<div class="k-qator k-tahlil"><b>${esc(d.raqam)}</b>` +
      `<span class="ong"><a class="k-havola" href="/api/v1/ijro-hujjat/${d.id}.pdf">${ikon("pdf")}PDF</a></span>${nishon}` +
      (d.holat === "bekor" ? `<div class="k-sabab">${esc(sanaMatn(d.yaratilgan))} · ${d.varaqlar} varaq · bekor: ${esc(d.bekor_sabab)}</div>`
        : `<div class="k-sabab">${esc(sanaMatn(d.yaratilgan))} · ${d.varaqlar} varaq · ${esc((x.tarmoqlar || []).join(", "))} · RASMIY ${x.nuqtalar?.RASMIY ?? 0}, SKAN ${x.nuqtalar?.SKAN ?? 0}, PAST ${x.nuqtalar?.PAST ?? 0}` +
          (x.yaroqli === true ? ` · <span class="nishon nishon-ok">yaroqli</span>` : x.yaroqli === false ? ` · <span class="nishon nishon-xato">yaroqsiz</span>` : "") +
          (men.rol === "admin" ? ` · <button type="button" class="k-havola tugma-matn" data-hujjat-bekor="${d.id}">bekor qilish</button>` : "") + `</div>`) +
      `</div>`;
  }
  if (yozuvchi() && liniyaSoni) h += `<div class="tugmalar-qator" style="padding-top:8px"><button type="button" class="tugma-asosiy" id="ijro-yarat">Ijro hujjatini yaratish</button>` +
    `<button type="button" class="tugma-oddiy" id="yopiq-yarat" title="ShNQ 3.01.01-22, 6-ilova: navbatdagi ishlardan (ko'mishdan) oldin">Yopiq ishlar dalolatnomasi</button></div>`;
  quti.innerHTML = h;
  const yb = el("yopiq-yarat");
  if (yb) yb.addEventListener("click", () => yopiqModal(o, liniyaSoni));
  const b = el("ijro-yarat");
  if (b) b.addEventListener("click", async () => {
    b.disabled = true;
    b.textContent = "Yasalmoqda…";
    try {
      const m = await so("/api/v1/ijro-hujjat", "POST", { obyekt_id: o.id });
      await ijroBolim(o, liniyaSoni);
      const yangi = el("o-ijro").querySelector(`a[href="/api/v1/ijro-hujjat/${m.id}.pdf"]`);
      if (yangi) yangi.closest(".k-qator").classList.add("k-yangi");
    } catch (x) { b.disabled = false; b.textContent = "Ijro hujjatini yaratish"; alert(x.message); }
  });
  for (const t of quti.querySelectorAll("[data-hujjat-bekor]")) {
    t.addEventListener("click", async () => {
      const sabab = prompt("Bekor qilish sababi (QR sahifasida ko'rinadi):");
      if (!sabab || !sabab.trim()) return;
      try { await so(`/api/v1/ijro-hujjat/${t.dataset.hujjatBekor}/bekor`, "POST", { sabab: sabab.trim() }); ijroBolim(o, liniyaSoni); }
      catch (x) { alert(x.message); }
    });
  }
}

/* ---------- 15-bo'lim: geodezik asos va lokalizatsiya (LK) ---------- */

async function asosBolim(o) {
  const quti = el("o-asos");
  if (!quti || tanlanganObyekt !== o.id) return;
  let a;
  try { a = await so(`/api/v1/obyekt/${o.id}/geodezik-asos`); } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  const l = a.lokalizatsiya, n = l && l.natija;
  const kal = a.olchovlar.filter((x) => x.maqsad === "kalibrlash").length, tek = a.olchovlar.length - kal;
  kartaYangila("asos", n ? (n.yaroqli ? "yaroqli" : "yaroqsiz") : (a.punktlar.length ? "hisoblanmagan" : "yo'q"),
    `${a.punktlar.length} punkt · ${a.olchovlar.length} o'lchov`, n ? (n.yaroqli ? "ok" : "xato") : "");
  let h = "";
  if (n) {
    const ok = n.yaroqli;
    const yomonTek = a.tekshiruvlar.filter((t) => !t.otdi).length;
    h += `<div class="k-qator k-tahlil" style="border-left-color:${ok ? "var(--ok)" : "var(--xato)"}">` +
      `<b>${esc(l.tizim_nomi)}</b>` +
      `<span class="ong">${sm(n.maks_gor)} / ${sm(n.maks_ver)} sm</span>` +
      `<span class="nishon ${ok ? "nishon-ok" : "nishon-xato"}">${ok ? "yaroqli" : "yaroqsiz"}</span>` +
      `<div class="k-sabab">${n.n_gor} punkt · eng katta qoldiq gorizontal / vertikal. ${n.xatolar.map(esc).join("; ")}` +
      `${n.ogohlantirishlar.length ? " Ogohlantirish: " + n.ogohlantirishlar.map(esc).join("; ") : ""}` +
      ` Tekshiruvlar: ${a.tekshiruvlar.length}${yomonTek ? `, o'tmagan ${yomonTek}` : ""}. ` +
      `<button type="button" class="k-havola tugma-matn" id="asos-batafsil">batafsil</button></div></div>`;
  } else {
    h += `<div class="k-bosh">Lokalizatsiya yo'q: hujjat WGS84 / UTM va ellipsoid balandligida, shahar uni qabul qilmaydi. ` +
      `Obyektni o'rab turgan kamida 4 ta koordinatasi va Boltiq balandligi ma'lum punktni RTK bilan o'lchang (har biri ≥ 30 s FIX).</div>`;
  }
  h += `<div class="k-bosh">Punktlar: ${a.punktlar.length} · o'lchovlar: kalibrlash ${kal}, tekshiruv ${tek}</div>`;
  if (yozuvchi()) h += `<div class="tugmalar-qator" style="padding-top:6px">` +
    `<button type="button" class="tugma-oddiy" id="asos-punkt">Punktlar</button>` +
    `<button type="button" class="tugma-oddiy" id="asos-olchov">O'lchovlar</button>` +
    `<button type="button" class="tugma-asosiy" id="asos-hisob"${kal ? "" : " disabled"}>Hisoblash</button></div>`;
  quti.innerHTML = h;
  const b = (id, f) => { const e = el(id); if (e) e.addEventListener("click", f); };
  b("asos-batafsil", () => asosBatafsil(o, a));
  b("asos-punkt", () => punktModal(o, a));
  b("asos-olchov", () => olchovModal(o, a));
  b("asos-hisob", () => hisobModal(o, a));
}

/** Geodezik asos o'zgarsa hujjat holati ham o'zgaradi — butun inspektor qayta chiziladi (tab saqlanadi). */
function asosQaytaChiz(o) { obyektPanelKorsat(o.id); }

function punktModal(o, a) {
  const qator = a.punktlar.map((p) => `<tr><td>${esc(p.nomi)}</td><td>${p.x == null ? "—" : son(p.x, 3)}</td><td>${p.y == null ? "—" : son(p.y, 3)}</td>` +
    `<td>${p.h == null ? "—" : son(p.h, 3)}</td><td>${esc(p.sinf || "")}${p.manba ? ` · ${esc(p.manba)}` : ""}</td>` +
    `<td><button type="button" class="tugma-xavf" data-pbekor="${p.id}">Olib tashlash</button></td></tr>`).join("");
  modalOch("Geodezik asos punktlari", `<p class="matn2" style="margin-bottom:10px">Shahar geodezik tarmog'i yoki qurilish razbivka asosi punktlari katalogidan. ` +
    `Har qatorda: nomi; X (shimol); Y (sharq); H (Boltiq); sinf; manba. O'nlik vergul ham bo'ladi. Faqat balandligi ma'lum reper uchun X va Y bo'sh qoldiriladi.</p>` +
    `<form id="punkt-forma" class="forma"><label class="toliq">CSV<textarea name="csv" rows="4" class="mono-maydon" required placeholder="nomi;X;Y;H;sinf;manba&#10;Pp-112;5123,456;54321,789;401,234;4-sinf;shahar tarmog'i"></textarea></label>` +
    `<div class="forma-tugmalar toliq"><button type="submit" class="tugma-asosiy">Qo'shish</button></div>` +
    `<div id="punkt-xato" class="xato-matn toliq"></div></form>` +
    (qator ? `<table class="jadval" style="margin-top:14px"><thead><tr><th>Punkt</th><th>X</th><th>Y</th><th>H</th><th>Sinf</th><th></th></tr></thead><tbody>${qator}</tbody></table>` : ""));
  el("punkt-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    try {
      const m = await so(`/api/v1/obyekt/${o.id}/nazorat-punkt`, "POST", { csv: new FormData(h.target).get("csv") });
      modalYop(); asosQaytaChiz(o);
      if (m.xatolar.length) alert(`Qo'shildi: ${m.qoshildi}. Xatolar:\n${m.xatolar.join("\n")}`);
    } catch (x) { el("punkt-xato").textContent = x.message; }
  });
  for (const t of el("modal").querySelectorAll("[data-pbekor]")) t.addEventListener("click", async () => {
    if (!confirm("Punkt olib tashlansinmi? Lokalizatsiyani qayta hisoblash kerak bo'ladi.")) return;
    try { await so(`/api/v1/obyekt/${o.id}/nazorat-punkt/${t.dataset.pbekor}/bekor`, "POST", {}); modalYop(); asosQaytaChiz(o); }
    catch (x) { alert(x.message); }
  });
}

function olchovModal(o, a) {
  const qator = a.olchovlar.map((x) => `<tr><td>${esc(x.punkt_nomi)}</td><td>${x.maqsad === "tekshiruv" ? "tekshiruv" : "kalibrlash"}</td>` +
    `<td>${esc(sanaMatn(x.vaqt))}</td><td>${x.sigma_h_sm == null ? "—" : son(x.sigma_h_sm, 1)}</td>` +
    `<td>${esc(x.manba)}</td><td><button type="button" class="tugma-xavf" data-obekor="${x.id}">Bekor</button></td></tr>`).join("");
  modalOch("Nazorat o'lchovlari", `<p class="matn2" style="margin-bottom:8px">iPhone ilovasi o'lchovlarni o'zi yuboradi. ` +
    `Emlid Flow bilan o'lchangan bo'lsa, loyihani «All columns» CSV qilib eksport qiling va shu yerga tashlang: punkt nomlari ` +
    `katalogdagidek bo'lsin. Faqat FIX qabul qilinadi. Tavsifida «tekshiruv» yozilgan nuqta tekshiruv o'lchovi bo'ladi.</p>` +
    `<form id="olchov-forma" class="forma"><label class="toliq">CSV fayl<input name="fayl" type="file" accept=".csv,.txt"></label>` +
    `<label class="toliq">yoki matn<textarea name="csv" rows="4" class="mono-maydon" placeholder="nomi;lat;lon;h_ellipsoid;σH_sm;σV_sm;maqsad"></textarea></label>` +
    `<label>Standart maqsad<select name="maqsad"><option value="kalibrlash">kalibrlash</option><option value="tekshiruv">tekshiruv</option></select></label>` +
    `<div class="forma-tugmalar toliq"><button type="submit" class="tugma-asosiy">Import</button></div>` +
    `<div id="olchov-xato" class="xato-matn toliq"></div></form>` +
    (qator ? `<table class="jadval" style="margin-top:14px"><thead><tr><th>Punkt</th><th>Maqsad</th><th>Vaqt</th><th>σH, sm</th><th>Manba</th><th></th></tr></thead><tbody>${qator}</tbody></table>` : ""));
  el("olchov-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), f = fd.get("fayl");
    const csv = f && f.size ? await f.text() : String(fd.get("csv") || "");
    if (!csv.trim()) return;
    try {
      const m = await so(`/api/v1/obyekt/${o.id}/nazorat-olchov`, "POST", { csv, maqsad: fd.get("maqsad") });
      modalYop(); asosQaytaChiz(o);
      if (m.xatolar.length) alert(`Qabul qilindi: ${m.idlar.length}. Rad etildi:\n${m.xatolar.join("\n")}`);
    } catch (x) { el("olchov-xato").textContent = x.message; }
  });
  for (const t of el("modal").querySelectorAll("[data-obekor]")) t.addEventListener("click", async () => {
    if (!confirm("O'lchov bekor qilinsinmi (masalan, punkt buzilgan)?")) return;
    try { await so(`/api/v1/obyekt/${o.id}/nazorat-olchov/${t.dataset.obekor}/bekor`, "POST", {}); modalYop(); asosQaytaChiz(o); }
    catch (x) { alert(x.message); }
  });
}

function hisobModal(o, a) {
  const oldingi = a.lokalizatsiya ? a.lokalizatsiya.tizim_nomi : "";
  modalOch("Lokalizatsiyani hisoblash", `<form id="hisob-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">Mahalliy tizim nomi *<input name="nomi" required maxlength="80" value="${esc(oldingi)}" ` +
    `placeholder="masalan: Jizzax sh. mahalliy tizimi"></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Gorizontal: mahalliy Transvers Merkator va 4 parametrli ` +
    `Helmert; balandlik: ≥ 4 punktda qiya tekislik. Chegara: ≥ ${a.chegaralar.min_punkt} punkt, qoldiq ≤ ${sm(a.chegaralar.qoldiq_gor_m)} / ` +
    `${sm(a.chegaralar.qoldiq_ver_m)} sm. Natija bilan hujjat mahalliy X, Y va Boltiq H da yasaladi.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="hisob-bekor">Bekor</button>` +
    `<button type="submit" class="tugma-asosiy">Hisoblash</button></div><div id="hisob-xato" class="xato-matn toliq"></div></form>`);
  el("hisob-bekor").addEventListener("click", modalYop);
  el("hisob-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    try {
      await so(`/api/v1/obyekt/${o.id}/lokalizatsiya`, "POST", { tizim_nomi: String(new FormData(h.target).get("nomi")).trim() });
      const yangi = await so(`/api/v1/obyekt/${o.id}/geodezik-asos`);
      asosQaytaChiz(o);
      asosBatafsil(o, yangi);
    } catch (x) { el("hisob-xato").textContent = x.message; }
  });
}

function asosBatafsil(o, a) {
  const l = a.lokalizatsiya, n = l.natija, loo = Object.fromEntries(n.loo.map((r) => [r.nomi, r]));
  const ch = a.chegaralar;
  const qator = n.qoldiqlar.map((r) => {
    const yomon = (r.gor != null && r.gor > ch.qoldiq_gor_m) || (r.ver != null && Math.abs(r.ver) > ch.qoldiq_ver_m);
    return `<tr class="${yomon ? "qator-xavf" : ""}"><td>${esc(r.nomi)}</td><td>${sm(r.gor)}</td><td>${sm(r.ver)}</td>` +
      `<td>${sm(loo[r.nomi] && loo[r.nomi].gor)}</td><td>${sm(loo[r.nomi] && loo[r.nomi].ver)}</td></tr>`;
  }).join("");
  const tek = a.tekshiruvlar.map((t) => `<tr class="${t.otdi ? "" : "qator-xavf"}"><td>${esc(t.nomi)}</td><td>${esc(sanaMatn(t.vaqt))}</td>` +
    `<td>${sm(t.gor)}</td><td>${sm(t.ver)}</td><td>${t.otdi ? "o'tdi" : "O'TMADI"}</td></tr>`).join("");
  modalOch(`Lokalizatsiya: ${esc(l.tizim_nomi)}`,
    `<div class="${n.yaroqli ? "natija-toza" : "natija-ogoh"}">${n.yaroqli ? "Chegaradan o'tdi" : "Chegaradan o'tmadi: " + n.xatolar.map(esc).join("; ")}</div>` +
    (n.ogohlantirishlar.length ? `<div class="natija-ogoh">${n.ogohlantirishlar.map(esc).join("<br>")}</div>` : "") +
    `<p class="matn2" style="margin:10px 0">Masshtab ${n.masshtab_ppm == null ? "—" : son(n.masshtab_ppm, 1)} ppm · burilish ` +
    `${n.burilish_grad == null ? "—" : n.burilish_grad.toFixed(5)}° · balandlik: ${esc(n.parametrlar.v ? n.parametrlar.v.model : "—")}, ` +
    `qiyalik ${n.qiyalik_ppm == null ? "—" : son(n.qiyalik_ppm, 1)} ppm. LOO — punkt hisobdan chiqarilganda bashorat xatosi.</p>` +
    `<table class="jadval"><thead><tr><th>Punkt</th><th>Qoldiq gor., sm</th><th>Qoldiq vert., sm</th><th>LOO gor., sm</th><th>LOO vert., sm</th></tr></thead><tbody>${qator}</tbody></table>` +
    (tek ? `<div class="k-bolim">Tekshiruv o'lchovlari</div><table class="jadval"><thead><tr><th>Punkt</th><th>Vaqt</th><th>Gor., sm</th><th>Vert., sm</th><th>Natija</th></tr></thead><tbody>${tek}</tbody></table>` : ""));
}

const Z_TURI = { usti: "quvur usti", oq: "quvur o'qi", tubi: "quvur tubi (tashqi)" };

async function loyihaBolim(o) {
  const quti = el("o-loyiha");
  if (!quti || tanlanganObyekt !== o.id) return;
  let m;
  try { m = await so(`/api/v1/obyekt/${o.id}/loyiha`); } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  const l = m.loyiha;
  let h = l ? `<div class="k-qator k-tahlil" style="border-left-color:#C026D3"><b>${esc(l.fayl_nomi)}</b> ${esc(sanaMatn(l.yaratilgan))}` +
    `<span class="ong">${l.chiziqlar.length} chiziq</span><div class="k-sabab">Belgi: ${esc(Z_TURI[l.z_turi] || l.z_turi)}, ` +
    `${l.z_tizimi === "ellipsoid" ? "WGS84 ellipsoid" : "Boltiq tizimi (profil chizig'i chizilmaydi)"}` +
    (m.tarix.length > 1 ? ` · oldingi versiyalar: ${m.tarix.length - 1}` : "") + `</div></div>`
    : `<div class="k-bosh">Loyiha yuklanmagan. DXF (LINE, POLYLINE, LWPOLYLINE) WGS84 / UTM da bo'lsa, hujjatda va 3D da loyihadan og'ish hisoblanadi.</div>`;
  let topo = [];
  try { topo = (await so(`/api/v1/obyekt/${o.id}/topo`)).tarix.filter((t) => t.holat === "amal"); } catch {}
  h += topo.length ? `<div class="k-bosh">Topoplan (reja foni): ${esc(topo[0].fayl_nomi)}, ${topo[0].chiziq_soni} chiziq, ${topo[0].matn_soni} matn</div>`
    : `<div class="k-bosh">Topoplan yo'q: ГОСТ Р 51872 6.2 ijro chizmasini 1:500 topografik plan ustida talab qiladi.</div>`;
  // T3: loyiha–ijro muvofiqligi (me'yor va o'lchov noaniqligi bilan)
  let mv = null;
  if (l) { try { mv = await so(`/api/v1/obyekt/${o.id}/muvofiqlik`); } catch {} }
  if (mv) {
    const j = mv.jami;
    h += `<div class="k-bolim">Loyiha–ijro muvofiqligi</div><div class="k-qator k-tahlil">` +
      (j.tashqari ? `<span class="nishon nishon-xato">me'yordan tashqari: ${j.tashqari}</span> ` : `<span class="nishon nishon-ok">me'yordan tashqari yo'q</span> `) +
      (j.noaniq ? `<span class="nishon nishon-ogoh">noaniq: ${j.noaniq}</span> ` : "") +
      (j.qurilmagan_m ? `<span class="nishon nishon-xato">qurilmagan ${son(j.qurilmagan_m, 1)} m</span> ` : "") +
      (j.loyihadan_tashqari_oraliq ? `<span class="nishon nishon-ogoh">loyihadan tashqari: ${j.loyihadan_tashqari_oraliq}</span>` : "") +
      `<div class="k-sabab">${mv.liniyalar.map((x) => `#${x.id} ${esc(x.rejim || "me'yor yo'q")}: rejada maks ${x.maks_g_m != null ? son(x.maks_g_m * 100, 1) + " sm" : "—"}` +
        (x.ruxsat_g_m ? ` (ruxsat ±${son(x.ruxsat_g_m * 100, 0)} sm)` : "")).join(" · ")}</div>` +
      `<div class="k-sabab">${esc(mv.qoida)}. Manba: SNiP 3.05.04-85*, 3.6-band.</div></div>`;
  }
  if (yozuvchi()) h += `<div class="tugmalar-qator" style="padding-top:6px"><button type="button" class="tugma-oddiy" id="loyiha-yukla">${l ? "Yangi versiya yuklash" : "Loyiha DXF yuklash"}</button>` +
    `<button type="button" class="tugma-oddiy" id="topo-yukla">Topoplan DXF</button>` +
    (mv ? `<button type="button" class="tugma-oddiy" id="muv-hisobot" title="Inspeksiyaga tayyor ro'yxat, QR bilan ro'yxatdan o'tadi">Muvofiqlik hisoboti (PDF)</button>` : "") + `</div>`;
  quti.innerHTML = h;
  const mb = el("muv-hisobot");
  if (mb) mb.addEventListener("click", async () => {
    mb.disabled = true; mb.textContent = "Tuzilmoqda…";
    try {
      const r = await so("/api/v1/muvofiqlik-hisobot", "POST", { obyekt_id: o.id });
      const a = document.createElement("a");   // PDF yuklab olinadi (attachment) — bo'sh oyna ochilmasin
      a.href = `/api/v1/ijro-hujjat/${r.id}.pdf`;
      a.download = `${r.raqam}.pdf`;
      document.body.appendChild(a); a.click(); a.remove();
      ijroBolim(o, obyektStat(o.id).fs.length);
    } catch (x) { alert(x.message); }
    mb.disabled = false; mb.textContent = "Muvofiqlik hisoboti (PDF)";
  });
  const b = el("loyiha-yukla");
  if (b) b.addEventListener("click", () => loyihaModal(o));
  const tb = el("topo-yukla");
  if (tb) tb.addEventListener("click", () => topoModal(o));
}

function loyihaModal(o) {
  modalOch("Loyiha DXF yuklash", `<form id="loyiha-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">DXF fayl (ASCII, ≤ 10 MB) *<input name="fayl" type="file" accept=".dxf" required></label>` +
    `<label>Loyiha balandligi nimani bildiradi<select name="z_turi"><option value="usti">quvur usti</option><option value="oq">quvur o'qi</option><option value="tubi">quvur tubi (tashqi)</option></select></label>` +
    `<label>Balandlik tizimi<select name="z_tizimi"><option value="boltiq">Boltiq (normal)</option><option value="ellipsoid">WGS84 ellipsoid</option></select></label>` +
    `<label class="toliq">Koordinata tizimi<select name="koordinata"><option value="mahalliy">mahalliy tizim (lokalizatsiya bo'yicha)</option>` +
    `<option value="utm">WGS84 / UTM</option></select></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Shahar loyihasi odatda mahalliy tizim va Boltiq balandligida keladi: obyekt lokalizatsiya qilingan bo'lsa shunday yuklang, gorizontal va vertikal og'ish hisoblanadi. Lokalizatsiyasiz faqat UTM qabul qilinadi.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="loyiha-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Yuklash</button></div>` +
    `<div id="loyiha-xato" class="xato-matn toliq"></div></form>`);
  el("loyiha-bekor").addEventListener("click", modalYop);
  el("loyiha-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), f = fd.get("fayl");
    if (!f || !f.size) return;
    const tugma = h.target.querySelector("[type=submit]");
    tugma.disabled = true;
    try {
      const q = new URLSearchParams({ fayl: f.name, z_turi: fd.get("z_turi"), z_tizimi: fd.get("z_tizimi"), koordinata: fd.get("koordinata") });
      const r = await fetch(`/api/v1/obyekt/${o.id}/loyiha?${q}`, { method: "POST", credentials: "same-origin",
        headers: { "X-Yerosti": "1", "Content-Type": "application/dxf" }, body: f });
      const m = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(m.xato || `xato ${r.status}`);
      modalYop();
      loyihaBolim(o);
    } catch (x) { tugma.disabled = false; el("loyiha-xato").textContent = x.message; }
  });
}

function topoModal(o) {
  modalOch("Topografik plan (DXF)", `<form id="topo-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">DXF fayl (ASCII, ≤ 10 MB) *<input name="fayl" type="file" accept=".dxf" required></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Shahar arxividan olingan 1:500 topoplan, mahalliy tizimda. ` +
    `Chiziqlar va matnlar (ko'cha nomi, uy raqami) rejada kulrang fon bo'ladi. Avval obyekt lokalizatsiya qilingan bo'lishi kerak.</p>` +
    `<div class="forma-tugmalar toliq"><button type="submit" class="tugma-asosiy">Yuklash</button></div>` +
    `<div id="topo-xato" class="xato-matn toliq"></div></form>`);
  el("topo-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const f = new FormData(h.target).get("fayl");
    if (!f || !f.size) return;
    try {
      const r = await fetch(`/api/v1/obyekt/${o.id}/topo?${new URLSearchParams({ fayl: f.name })}`, { method: "POST",
        credentials: "same-origin", headers: { "X-Yerosti": "1", "Content-Type": "application/dxf" }, body: f });
      const m = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(m.xato || `xato ${r.status}`);
      modalYop(); loyihaBolim(o);
    } catch (x) { el("topo-xato").textContent = x.message; }
  });
}

const ULASH_HOLAT = { amal: ["nishon-ok", "amalda"], bekor: ["nishon-kul", "bekor"], muddati_tugagan: ["nishon-kul", "muddati tugagan"] };

async function ulashBolim(o) {
  const quti = el("o-ulash");
  if (!quti || tanlanganObyekt !== o.id) return;
  let ul = [];
  try { ul = (await so(`/api/v1/obyekt/${o.id}/ulashlar`)).ulashlar; } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  let h = ul.length ? "" : `<div class="k-bosh">Havola yo'q. Muddatli havola tizimga kirmagan tomonga (hokimlik, ekspertiza, boshqa pudratchi) faqat shu obyektni ko'rsatadi.</div>`;
  for (const u of ul) {
    const [k, n] = ULASH_HOLAT[u.holat] || ["nishon-kul", u.holat];
    h += `<div class="k-qator k-tahlil"><b>${esc(u.nomi)}</b> ${esc(sanaMatn(u.muddati).slice(0, 10))} gacha` +
      `<span class="ong">${u.foydalanish} marta</span><span class="nishon ${k}">${esc(n)}</span>` +
      (u.holat === "amal" && yozuvchi() ? `<div class="k-sabab">Oxirgi ochilish: ${esc(sanaMatn(u.oxirgi))} · <button type="button" class="k-havola tugma-matn" data-ulash-bekor="${u.id}">bekor qilish</button></div>`
        : `<div class="k-sabab">Oxirgi ochilish: ${esc(sanaMatn(u.oxirgi))}</div>`) + `</div>`;
  }
  if (yozuvchi()) h += `<div class="tugmalar-qator" style="padding-top:6px"><button type="button" class="tugma-oddiy" id="ulash-yarat">Havola yaratish</button></div>`;
  quti.innerHTML = h;
  const b = el("ulash-yarat");
  if (b) b.addEventListener("click", () => ulashModal(o));
  for (const t of quti.querySelectorAll("[data-ulash-bekor]")) {
    t.addEventListener("click", async () => {
      if (!confirm("Havola bekor qilinsinmi? U darhol ishlamay qoladi.")) return;
      try { await so(`/api/v1/ulash/${t.dataset.ulashBekor}/bekor`, "POST", {}); ulashBolim(o); } catch (x) { alert(x.message); }
    });
  }
}

function ulashModal(o) {
  modalOch("Muddatli ulashish havolasi", `<form id="ulash-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">Kimga *<input name="nomi" required maxlength="120" placeholder="masalan: Jizzax shahar hokimligi, qurilish bo'limi"></label>` +
    `<label>Muddat, kun (1…365)<input name="kun" type="number" min="1" max="365" value="30" required></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Havola egasi faqat shu obyektni ko'radi: hujjat PDF, DXF, CSV va 3D, o'qish uchun. Har ochilish sanaladi, istalgan payt bekor qilinadi.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="ulash-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Yaratish</button></div>` +
    `<div id="ulash-xato" class="xato-matn toliq"></div></form>`);
  el("ulash-bekor").addEventListener("click", modalYop);
  el("ulash-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target);
    try {
      const m = await so(`/api/v1/obyekt/${o.id}/ulash`, "POST", { nomi: String(fd.get("nomi")).trim(), kun: Number(fd.get("kun")) });
      modalOch("Havola yaratildi", `<div class="token-quti"><b>Havola faqat shu yerda bir marta ko'rinadi.</b> Nusxa olib, egasiga yuboring.` +
        `<div class="token-qiymat" id="ulash-qiymat">${esc(m.url)}</div><button type="button" class="tugma-oddiy" id="ulash-nusxa">Nusxa olish</button></div>` +
        `<p class="matn2" style="margin-top:10px">Amal qiladi: ${esc(sanaMatn(m.muddati))} gacha.</p>`);
      el("ulash-nusxa").addEventListener("click", async (e) => {
        try { await navigator.clipboard.writeText(m.url); e.target.textContent = "Nusxa olindi"; } catch { e.target.textContent = "Qo'lda nusxa oling"; }
      });
      ulashBolim(o);
    } catch (x) { el("ulash-xato").textContent = x.message; }
  });
}

const TARIX_TUR = { obyekt: "Obyekt", liniya: "Liniya", skan: "Skan", muhr: "Muhr", tahlil: "Qayta hisob", hujjat: "Hujjat",
  loyiha: "Loyiha", ulash: "Ulashish", izoh: "3D izoh" };

async function tarixBolim(o) {
  const quti = el("o-tarix");
  if (!quti || tanlanganObyekt !== o.id) return;
  let t = [];
  try { t = (await so(`/api/v1/obyekt/${o.id}/tarix`)).tarix; } catch (x) { quti.innerHTML = `<div class="k-bosh">${esc(x.message)}</div>`; return; }
  if (!el("o-tarix")) return;
  let h = `<ol class="tarix">`;
  for (const x of t) {
    const xavf = x.holat === "bekor" || x.holat === "BUZILGAN" || x.holat === "FARQ" || x.holat === "XATO";
    h += `<li class="${xavf ? "tarix-xavf" : ""}"><time>${esc(sanaMatn(x.vaqt))}</time><span class="nishon nishon-kul">${esc(TARIX_TUR[x.tur] || x.tur)}</span>` +
      `<div>${esc(x.matn)}${x.kim ? `<small>${esc(x.kim)}</small>` : ""}</div></li>`;
  }
  el("o-tarix").innerHTML = t.length ? h + `</ol>` : `<div class="k-bosh">Tarix bo'sh.</div>`;
}

function tahlilQatori(t) {
  const smm = (m) => son(m * 100, 1) + " sm";
  const nishon = t.holat !== "tayyor"
    ? (t.holat === "xato" ? `<span class="nishon nishon-xato">xato</span>` : `<span class="nishon nishon-kul">${esc(t.holat)}</span>`)
    : t.xulosa === "MOS" ? `<span class="nishon nishon-ok">MOS</span>`
    : t.xulosa === "TASHQI" ? `<span class="nishon nishon-ogoh">tashqi · tasdiq kutilmoqda</span>`
    : t.xulosa === "OZGARISH" ? `<span class="nishon nishon-ogoh">O'ZGARISH</span>`
    : t.xulosa === "OZGARMAGAN" ? `<span class="nishon nishon-ok">o'zgarmagan</span>`
    : t.xulosa === "FARQ" ? `<span class="nishon nishon-ogoh">FARQ</span>` : `<span class="nishon nishon-xato">${esc(t.xulosa)}</span>`;
  let izoh = "";
  if (t.holat === "tayyor") {
    const q = [];
    if (t.oq_farqi_maks_m != null) q.push(`quvur o'qi farqi ${smm(t.oq_farqi_maks_m)}`);
    if (t.georef_siljish_m != null) q.push(`georeferens farqi ${smm(t.georef_siljish_m)}`);
    q.push(`${t.quvur_soni} quvur`);
    // DS-04/05/06: xom yozuvli skan
    if (t.ply_nomi === "zich.ply") q.push(`zich rangli bulut${t.chuqurlik_kadrlar ? ` (${t.chuqurlik_kadrlar} chuqurlik kadri)` : ""}`);
    if (t.kechikish_ms != null) q.push(`RTK kechikishi ${son(t.kechikish_ms, 0)} ms${t.kechikish_ishonchli ? "" : " (taxminiy)"}`);
    if (t.bolaklar != null) q.push(`bo'lakli georeferens: ${t.bolaklar} bo'lak${t.past_bolaklar ? `, PAST ${t.past_bolaklar}` : ""}` +
      (t.maks_tuzatish_m != null ? `, ARKit suzishi ≤ ${smm(t.maks_tuzatish_m)} tuzatildi` : ""));
    izoh = q.join(" · ");
    if (t.sabablar && t.sabablar.length) izoh += `<div class="k-sabab">${t.sabablar.map(esc).join("<br>")}</div>`;
    if (t.ogohlantirishlar && t.ogohlantirishlar.length) izoh += `<div class="k-sabab">Ogohlantirish: ${t.ogohlantirishlar.map(esc).join("<br>")}</div>`;
  } else if (t.xato) izoh = `<div class="k-sabab">${esc(t.xato)}</div>`;
  const kor = t.korinish ? `<a class="k-havola" href="/3d?tahlil=${t.id}" target="_blank" rel="noopener">3D ko'rish</a>` : "";
  const nom = t.tur === "tashqi" ? `Tashqi LiDAR: ${esc(t.manba_nomi || "skaner")}` : t.tur === "farq" ? `O'zgarish M3C2: #${t.farq_a_id} ↔ #${t.farq_b_id}` : `Muhr #${t.muhr_id}`;
  if (t.tur === "farq" && t.farq) {
    const f = t.farq;
    izoh = `${f.baholangan} yadro nuqta · ahamiyatli ${f.ahamiyatli} (${Math.round((f.ahamiyatli_ulush || 0) * 100)} %) · o'rtacha ${sm(f.ortacha_m)} sm · maks ${sm(f.maks_abs_m)} sm · LoD95 ${sm(f.lod95_ortacha_m)} sm` +
      (f.dog_soni ? ` · eng katta dog' ${son(f.dog_maydon_m2, 2)} m², ${f.dog_ortacha_m > 0 ? "+" : "−"}${sm(Math.abs(f.dog_ortacha_m))} sm` : "");
  }
  if (t.tur === "tashqi" && t.holat === "tayyor" && t.liniya_idlar && t.liniya_idlar.length) izoh += ` · ${t.liniya_idlar.length} liniya yaratildi (SKAN)`;
  return `<div class="k-qator k-tahlil"><b>${nom}</b> ${izoh}<span class="ong">${kor}</span>${nishon}</div>`;
}

/* ---------- qidiruv va klaviatura ---------- */

let qidiruvTaymer = null;
el("qidiruv").addEventListener("input", () => { clearTimeout(qidiruvTaymer); qidiruvTaymer = setTimeout(obyektRoyxatChiz, 120); });
document.addEventListener("keydown", (h) => {
  if ((h.ctrlKey || h.metaKey) && h.key.toLowerCase() === "k") {
    h.preventDefault();
    if (faolBolim !== "obyektlar" || !el("asosiy").classList.contains("tortma-ochiq")) railTanla("obyektlar");
    el("qidiruv").focus(); el("qidiruv").select();
  }
  if (h.key === "Escape") {
    if (!el("modal-fon").classList.contains("yashirin")) return modalYop();
    if (masofaRejim) return masofaHolat(false);
    if (!el("inspektor").classList.contains("yashirin")) return inspektorYop();
    if (orderRejim) tortmaYop();
  }
});

/* ---------- modal ---------- */

function modalOch(sarlavha, tanaHtml) {
  el("modal").innerHTML = `<button class="yopish" type="button" id="modal-yop" aria-label="Yopish">×</button>` +
    `<div class="modal-sarlavha">${sarlavha}</div><div class="modal-tana">${tanaHtml}</div>`;
  el("modal-yop").addEventListener("click", modalYop);
  el("modal-fon").classList.remove("yashirin");
  const b = el("modal").querySelector("input");
  if (b) b.focus();
}
function modalYop() { el("modal-fon").classList.add("yashirin"); }
el("modal-fon").addEventListener("click", (h) => { if (h.target === el("modal-fon")) modalYop(); });

function obyektTahrirModal(o) {
  const q = (nom, yorliq, uz, qosh = "") => `<label${qosh}>${yorliq}<input name="${nom}" maxlength="${uz}" value="${esc(o[nom] || "")}"></label>`;
  modalOch(`Obyekt #${o.id} rekvizitlari`, `<form id="obyekt-tahrir" class="forma" autocomplete="off">` +
    `<label class="toliq">Obyekt nomi *<input name="nomi" required maxlength="200" value="${esc(o.nomi || "")}"></label>` +
    q("manzil", "Manzil", 300, ` class="toliq"`) + q("buyurtmachi", "Buyurtmachi", 200) + q("pudratchi", "Pudratchi", 200) +
    q("order_raqami", "Qazish orderi raqami", 64) +
    `<label>Qazish orderi sanasi<input name="order_sana" type="date" min="2000-01-01" max="2100-12-31" value="${esc(o.order_sana || "")}"></label>` +
    q("tarmoq_egasi", "Tarmoq egasi (operator)", 120, ` class="toliq"`) +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Geometriya, skan va muhr o'zgarmaydi. Allaqachon chiqarilgan hujjat o'zgarmaydi — yangi rekvizit keyingi hujjatda chiqadi. O'zgarish jurnalga yoziladi.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="obyekt-tahrir-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Saqlash</button></div>` +
    `<div id="obyekt-tahrir-xato" class="xato-matn toliq"></div></form>`);
  el("obyekt-tahrir-bekor").addEventListener("click", modalYop);
  el("obyekt-tahrir").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), t = {};
    for (const [k, v] of fd.entries()) t[k] = String(v).trim();
    try {
      await so(`/api/v1/obyekt/${o.id}`, "POST", t);
      modalYop();
      await malumotYangila(false);
      obyektPanelKorsat(o.id);
    } catch (x) { el("obyekt-tahrir-xato").textContent = x.message; }
  });
}

/* ShN-05: yopiq ishlar dalolatnomasi (ShNQ 3.01.01-22, 28-band, 6-ilova). Xulosa va imzolar — komissiyaniki. */
function yopiqModal(o, liniyaSoni) {
  const lin = obyektStat(o.id).fs.map((f) => f.properties);
  const bugun = new Date(Date.now() + 5 * 3600e3).toISOString().slice(0, 10);
  const vakil = (rol, nom) => `<label>${nom}: F.I.O.<input name="${rol}_fio" maxlength="120"></label>` +
    `<label>Lavozimi<input name="${rol}_lavozim" maxlength="120"></label>`;
  modalOch("Yopiq ishlar dalolatnomasi", `<form id="yopiq-forma" class="forma" autocomplete="off">` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">ShNQ 3.01.01-22, 6-ilova shakli. Dalolatnoma navbatdagi ishlar (ko'mish) boshlanishidan oldin tuziladi. ` +
    `Bo'sh qolgan maydon PDF da qo'lda to'ldirish uchun chiziq bo'lib chiqadi; o'lchov dalillari (RTK, skan, muhr, rasm) ilovaga avtomatik qo'shiladi.</p>` +
    `<label>Dalolatnoma sanasi<input name="sana" type="date" value="${bugun}" min="2000-01-01" max="2100-12-31"></label>` +
    `<label>Loyihadan chetga chiqish<select name="chetga_chiqish"><option value="">komissiya qo'lda belgilaydi</option>` +
    `<option value="yoq">yo'l qo'yilmagan</option><option value="bor">yo'l qo'yilgan</option></select></label>` +
    `<label class="toliq">Bajarilgan ishlar nomi<textarea name="ishlar_nomi" maxlength="500" rows="2" placeholder="bo'sh qolsa — o'lchangan liniyalardan"></textarea></label>` +
    vakil("pudratchi", "Qurilish-montaj tashkiloti vakili") + vakil("buyurtmachi", "Buyurtmachi vakili") + vakil("loyiha", "Loyiha tashkiloti vakili") +
    `<label class="toliq">Loyiha (loyihalash tashkiloti, chizmalar raqami va sanasi)<input name="loyiha_hujjati" maxlength="500"></label>` +
    `<label class="toliq">Materiallar va sertifikatlar<textarea name="materiallar" maxlength="1000" rows="2" placeholder="bo'sh qolsa — liniyalar materiali va uzunligi"></textarea></label>` +
    `<label class="toliq">Chetga chiqish izohi (chizmalar nomeri va sanasi)<input name="chetga_chiqish_izoh" maxlength="500"></label>` +
    `<label>Ishlarning boshlanish sanasi<input name="boshlanish" type="date" min="2000-01-01" max="2100-12-31"></label>` +
    `<label>Ishlarning tugash sanasi<input name="tugash" type="date" min="2000-01-01" max="2100-12-31"></label>` +
    `<label class="toliq">Xulosa (komissiya)<textarea name="xulosa" maxlength="1500" rows="3" placeholder="bo'sh qolsa — qo'lda yoziladi"></textarea></label>` +
    `<label class="toliq">Keyin bajarish mumkin bo'lgan ishlar<input name="keyingi_ishlar" maxlength="500" placeholder="transheyani qayta ko'mish (tuproq bilan to'ldirish va zichlash)"></label>` +
    `<fieldset class="toliq yopiq-liniyalar"><legend>Ko'rikka taqdim etilgan liniyalar</legend>` +
    lin.map((p) => `<label class="bayroq"><input type="checkbox" name="liniya" value="${p.id}" checked> #${p.id} ${esc((TURLAR[p.turi] || {}).nom || p.turi)} Ø${p.diametr_mm}${p.material ? " " + esc(p.material) : ""} · ${son(p.uzunlik_m, 1)} m</label>`).join("") +
    `</fieldset>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="yopiq-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Dalolatnomani tuzish</button></div>` +
    `<div id="yopiq-xato" class="xato-matn toliq"></div></form>`);
  el("yopiq-bekor").addEventListener("click", modalYop);
  el("yopiq-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), q = (k) => String(fd.get(k) || "").trim();
    const idlar = fd.getAll("liniya").map(Number);
    if (!idlar.length) { el("yopiq-xato").textContent = "Kamida bitta liniya tanlang."; return; }
    const t = { obyekt_id: o.id, sana: q("sana"), chetga_chiqish: q("chetga_chiqish"), ishlar_nomi: q("ishlar_nomi"),
      loyiha_hujjati: q("loyiha_hujjati"), materiallar: q("materiallar"), chetga_chiqish_izoh: q("chetga_chiqish_izoh"),
      boshlanish: q("boshlanish"), tugash: q("tugash"), xulosa: q("xulosa"), keyingi_ishlar: q("keyingi_ishlar"),
      liniya_idlar: idlar.length === lin.length ? null : idlar,
      vakillar: Object.fromEntries(["pudratchi", "buyurtmachi", "loyiha"].map((r) => [r, { fio: q(`${r}_fio`), lavozim: q(`${r}_lavozim`) }])) };
    const tugma = h.target.querySelector("button[type=submit]");
    tugma.disabled = true; tugma.textContent = "Tuzilmoqda…";
    try {
      const m = await so("/api/v1/yopiq-dalolatnoma", "POST", t);
      modalYop();
      await ijroBolim(o, liniyaSoni);
      const yangi = el("o-ijro").querySelector(`a[href="/api/v1/ijro-hujjat/${m.id}.pdf"]`);
      if (yangi) yangi.closest(".k-qator").classList.add("k-yangi");
    } catch (x) { tugma.disabled = false; tugma.textContent = "Dalolatnomani tuzish"; el("yopiq-xato").textContent = x.message; }
  });
}

function yangiObyektModal() {
  modalOch("Yangi obyekt", `<form id="obyekt-forma" class="forma" autocomplete="off">` +
    `<label class="toliq">Obyekt nomi *<input name="nomi" required maxlength="200" placeholder="masalan: 5-mavze suv ta'minoti tarmog'i"></label>` +
    `<label class="toliq">Manzil<input name="manzil" maxlength="300"></label>` +
    `<label>Buyurtmachi<input name="buyurtmachi" maxlength="200"></label>` +
    `<label>Pudratchi<input name="pudratchi" maxlength="200"></label>` +
    `<label>Qazish orderi raqami<input name="order_raqami" maxlength="64"></label>` +
    `<label>Qazish orderi sanasi<input name="order_sana" type="date" min="2000-01-01" max="2100-12-31"></label>` +
    `<p class="matn2 toliq" style="font-size:var(--f12)">Order raqami va sanasi ijro hujjatida shart (ShNK 3.01.03-24, 420-band): bo'lmasa hujjat «yaroqsiz» chiqadi. Keyin «Rekvizitlar» orqali kiritish mumkin.</p>` +
    `<div class="forma-tugmalar toliq"><button type="button" class="tugma-oddiy" id="obyekt-bekor">Bekor</button><button type="submit" class="tugma-asosiy">Yaratish</button></div>` +
    `<div id="obyekt-xato" class="xato-matn toliq"></div></form>`);
  el("obyekt-bekor").addEventListener("click", modalYop);
  el("obyekt-forma").addEventListener("submit", async (h) => {
    h.preventDefault();
    const fd = new FormData(h.target), t = {};
    for (const [k, v] of fd.entries()) t[k] = String(v).trim();
    try {
      const m = await so("/api/v1/obyektlar", "POST", t);
      modalYop();
      await malumotYangila(false);
      obyektPanelKorsat(m.id);
    } catch (x) { el("obyekt-xato").textContent = x.message; }
  });
}
el("yangi-obyekt").addEventListener("click", yangiObyektModal);
el("bosh-yangi-obyekt").addEventListener("click", yangiObyektModal);

async function dalaQurilmalarModal(yangiToken) {
  let tokenlar = [];
  try { tokenlar = (await so("/api/v1/dala-tokenlar")).tokenlar; } catch (x) { return modalOch("Dala qurilmalari", `<div class="xato-matn">${esc(x.message)}</div>`); }
  let h = "";
  if (yangiToken) {
    h += `<div class="token-quti"><b>Token faqat shu yerda bir marta ko'rinadi.</b> iPhone dala ilovasiga kiriting va yopib qo'ying.` +
      `<div class="token-qiymat" id="token-qiymat">${esc(yangiToken)}</div><button type="button" class="tugma-oddiy" id="token-nusxa">Nusxa olish</button></div>`;
  }
  h += `<form id="token-forma" class="forma" autocomplete="off">` +
    `<label>Qurilma nomi *<input name="nomi" required maxlength="80" placeholder="masalan: Brigada-1 iPhone"></label>` +
    `<label>Model / seriya<input name="qurilma" maxlength="120" placeholder="iPhone 17 Pro Max"></label>` +
    `<div class="forma-tugmalar toliq" style="margin-top:4px"><button type="submit" class="tugma-asosiy">Token yaratish</button></div>` +
    `<div id="token-xato" class="xato-matn toliq"></div></form>`;
  h += `<table class="jadval" style="margin-top:16px"><thead><tr><th>Qurilma</th><th>Model</th><th>Holat</th><th>Oxirgi ulanish</th><th></th></tr></thead><tbody>`;
  if (!tokenlar.length) h += `<tr><td colspan="5" class="matn2">Hali qurilma yo'q</td></tr>`;
  for (const t of tokenlar) {
    h += `<tr><td>${esc(t.nomi)}</td><td>${esc(t.qurilma || "—")}</td>` +
      `<td>${t.faol ? `<span class="nishon nishon-ok">faol</span>` : `<span class="nishon nishon-kul">bekor</span>`}</td>` +
      `<td>${esc(t.oxirgi_ishlatilgan ? sanaMatn(t.oxirgi_ishlatilgan) : "—")}</td>` +
      `<td>${t.faol ? `<button type="button" class="tugma-xavf" data-bekor="${t.id}">Bekor</button>` : ""}</td></tr>`;
  }
  h += `</tbody></table>`;
  modalOch("Dala qurilmalari (iPhone tokenlari)", h);
  const nusxa = el("token-nusxa");
  if (nusxa) nusxa.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(yangiToken); nusxa.textContent = "Nusxa olindi"; } catch { nusxa.textContent = "Qo'lda nusxa oling"; }
  });
  el("token-forma").addEventListener("submit", async (h2) => {
    h2.preventDefault();
    const fd = new FormData(h2.target);
    try {
      const m = await so("/api/v1/dala-tokenlar", "POST", { nomi: String(fd.get("nomi")).trim(), qurilma: String(fd.get("qurilma")).trim() });
      dalaQurilmalarModal(m.token);
    } catch (x) { el("token-xato").textContent = x.message; }
  });
  for (const t of el("modal").querySelectorAll("[data-bekor]")) {
    t.addEventListener("click", async () => {
      if (!confirm("Token bekor qilinsinmi? Qurilma boshqa yuklay olmaydi.")) return;
      try { await so(`/api/v1/dala-tokenlar/${t.dataset.bekor}/bekor`, "POST", {}); dalaQurilmalarModal(); }
      catch (x) { alert(x.message); }
    });
  }
}
el("dala-qurilmalar").addEventListener("click", () => dalaQurilmalarModal());
el("bosh-dala").addEventListener("click", () => dalaQurilmalarModal());

el("sifat-qoidasi").addEventListener("click", async () => {
  try {
    const q = await so("/api/v1/sifat-qoidasi");
    modalOch("Sifat qoidasi (T-103)", `<p class="matn2" style="margin-bottom:12px">Nuqta RASMIY bo'lishi uchun to'rt shart bir vaqtda bajarilishi shart. Birortasi yo'q yoki isbotsiz bo'lsa — PAST ANIQLIK, rasmiy chizmaga chiqmaydi.</p>` +
      `<ul class="qoida-royxat"><li>RTK holati<b>FIX</b></li><li>Gorizontal σ<b>≤ ${q.sigma_h_chek_sm} sm</b></li>` +
      `<li>Vertikal σ<b>≤ ${q.sigma_v_chek_sm} sm</b></li><li>Tuzatma yoshi<b>≤ ${q.tuzatma_yoshi_chek_s} s</b></li></ul>` +
      `<p class="matn2" style="margin-top:12px">Bu qoida serverda va iPhone drayverida bir xil. Xaritada PAST liniyalar punktir chiziladi.</p>`);
  } catch (x) { alert(x.message); }
});

/* ---------- qazish zonasi tekshiruvi (tortmaning «Qazish» bo'limi) ---------- */

el("order-tozala").addEventListener("click", orderTozala);
el("order-tekshir").addEventListener("click", orderYubor);
el("order-chop").addEventListener("click", () => window.print());

function orderHolat(yoq) {
  if (orderRejim === yoq) return;
  if (yoq && masofaRejim) masofaHolat(false);
  orderRejim = yoq;
  if (xarita) xarita.getCanvas().style.cursor = yoq ? "crosshair" : "";
  if (!yoq) orderTozala();
}

function orderNuqtaQosh(lngLat) {
  orderNuqtalar.push([lngLat.lat, lngLat.lng]);
  orderChizmaYangila();
  el("order-tekshir").disabled = orderNuqtalar.length < 3;
  el("order-korsatma").textContent = orderNuqtalar.length < 3 ? `${orderNuqtalar.length} nuqta belgilandi — kamida 3 ta kerak.`
    : `${orderNuqtalar.length} nuqta. Yana qo'shish mumkin yoki «Tekshirish»ni bosing.`;
}

function orderTozala() {
  orderNuqtalar = [];
  orderChizmaYangila();
  el("order-tekshir").disabled = true;
  el("order-natija").innerHTML = "";
  el("order-chop").classList.add("yashirin");
  el("order-korsatma").textContent = "Xaritada qazish zonasi burchaklarini bosib belgilang (kamida 3 nuqta), so'ng «Tekshirish»ni bosing. Natija bazadagi tarmoqlar bo'yicha.";
}

function orderChizmaYangila() {
  if (!xarita || !xarita.getSource("order-chizma")) return;
  const f = orderNuqtalar.map(([lat, lon]) => ({ type: "Feature", geometry: { type: "Point", coordinates: [lon, lat] } }));
  if (orderNuqtalar.length >= 3) {
    f.push({ type: "Feature", geometry: { type: "Polygon", coordinates: [[...orderNuqtalar, orderNuqtalar[0]].map(([a, o]) => [o, a])] } });
  } else if (orderNuqtalar.length === 2) {
    f.push({ type: "Feature", geometry: { type: "LineString", coordinates: orderNuqtalar.map(([a, o]) => [o, a]) } });
  }
  xarita.getSource("order-chizma").setData({ type: "FeatureCollection", features: f });
}

async function orderYubor() {
  const quti = el("order-natija");
  quti.innerHTML = `<div class="matn2">Tekshirilmoqda…</div>`;
  try {
    const m = await so("/api/v1/order-tekshir", "POST", { poligon: orderNuqtalar });
    orderNatijaChiz(m.topilgan);
  } catch (x) { quti.innerHTML = `<div class="natija-ogoh">${esc(x.message)}</div>`; }
}

function orderNatijaChiz(topilgan) {
  let h = `<div class="natija-sarlavha">Natija — ${esc(sanaMatn(new Date().toISOString()))}</div>`;
  if (!topilgan.length) {
    h += `<div class="natija-toza">Bu zonada bazada ro'yxatga olingan tarmoq topilmadi.</div>`;
  } else {
    for (const t of topilgan) {
      const m = TURLAR[t.turi] || { nom: t.turi, rang: "#334155" };
      const ch = t.chuqurlik_min == null ? "chuqurlik —"
        : Math.abs(t.chuqurlik_max - t.chuqurlik_min) < 0.15 ? `chuqurlik ${son(t.chuqurlik_min, 1)} m`
        : `chuqurlik ${son(t.chuqurlik_min, 1)}–${son(t.chuqurlik_max, 1)} m`;
      h += `<div class="natija-qator" style="border-left-color:${m.rang}"><b>${esc(m.nom)}</b> — ${t.diametr_mm ? `D${t.diametr_mm} mm · ` : ""}${esc(t.material || "")} · ${ch} ` +
        (t.sifat === "RASMIY" ? `<span class="nishon nishon-ok">RASMIY</span>` : t.sifat === "SKAN" ? `<span class="nishon nishon-ogoh">SKAN</span>` : `<span class="nishon nishon-xato">PAST ANIQLIK</span>`) +
        `<small>${esc(t.obyekt_nomi)} · ${esc(t.pudratchi || "—")}${orderMatn(t) ? ` · order ${esc(orderMatn(t))}` : ""}</small></div>`;
    }
  }
  h += `<div class="natija-ogoh">Diqqat: baza faqat tizimga kiritilgan tarmoqlarni qamraydi. Kiritilmagan (eski) tarmoqlar bo'lishi mumkin — qazishda ehtiyot choralari majburiy.</div>`;
  el("order-natija").innerHTML = h;
  el("order-chop").classList.remove("yashirin");
}

boshlash();
