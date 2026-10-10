"use strict";
/* YEROSTI 3D ko'ruvchi (DM-03) — kutubxonasiz WebGL2.
   Ma'lumot: /api/v1/tahlil/{id} (mustaqil qayta hisob natijasi) + korinish.ply (mahalliy ENU, z yuqori, metr).
   Koordinatalar: mahalliy ENU; server georeferensi bo'lsa — UTM ham ko'rsatiladi (natija.georef.server).
   TL-02: shu obyektning boshqa sanadagi skanlari UTM orqali ustma-ust; TL-03: nuqtaga izoh; IH-07: loyiha DXF qatlami.
   UL-02: /u/<token>/3d dan ochilsa — faqat o'qish, ma'lumot o'sha havola yo'lidan. */

const ULASH = (location.pathname.match(/^\/u\/(YRU\.[A-Za-z0-9_-]+)\/3d$/) || [])[1] || null;
const API = ULASH ? `/u/${ULASH}/api` : "/api/v1";
const SOROV = { credentials: "same-origin", headers: { "X-Yerosti": "1" } };

const el = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g,
  (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const vergul = (x, r) => x.toFixed(r).replace(".", ",");
const sm = (m) => vergul(m * 100, 1) + " sm";
const mtr = (m, r = 2) => vergul(m, r) + " m";
/** 401336,955 → "401 336,955" (xonalar ingichka bo'shliq bilan). */
const katta = (x, r) => { const [b, k] = x.toFixed(r).split("."); return b.replace(/\B(?=(\d{3})+(?!\d))/g, "\u2009") + (k ? "," + k : ""); };
/** Server vaqti UTC (ISO) → brauzerning mahalliy sanasi "03.10.2026". */
const mahalliySana = (iso) => {
  const d = iso ? new Date(iso) : null;
  if (!d || isNaN(d)) return "—";
  return `${String(d.getDate()).padStart(2, "0")}.${String(d.getMonth() + 1).padStart(2, "0")}.${d.getFullYear()}`;
};
const TARMOQ_NOMI = { suv: "Suv", kanalizatsiya: "Kanalizatsiya", gaz: "Gaz", elektr: "Elektr", optika: "Optika", issiqlik: "Issiqlik" };
const FOV = 50 * Math.PI / 180;

/* ---------- vektor va matritsa (ustun bo'yicha, WebGL tartibi) ---------- */
const V = {
  ayir: (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
  qosh: (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
  kop: (a, k) => [a[0] * k, a[1] * k, a[2] * k],
  nuqta: (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  kross: (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  uz: (a) => Math.hypot(a[0], a[1], a[2]),
  birlik: (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; },
};

function perspektiva(fov, nisbat, yaqin, uzoq) {
  const f = 1 / Math.tan(fov / 2), nf = 1 / (yaqin - uzoq);
  return new Float32Array([f / nisbat, 0, 0, 0, 0, f, 0, 0, 0, 0, (uzoq + yaqin) * nf, -1, 0, 0, 2 * uzoq * yaqin * nf, 0]);
}

function qarash(e, c, up) {
  const z = V.birlik(V.ayir(e, c)), x = V.birlik(V.kross(up, z)), y = V.kross(z, x);
  return new Float32Array([x[0], y[0], z[0], 0, x[1], y[1], z[1], 0, x[2], y[2], z[2], 0,
    -V.nuqta(x, e), -V.nuqta(y, e), -V.nuqta(z, e), 1]);
}

function kopaytir(a, b) {
  const o = new Float32Array(16);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
    let s = 0;
    for (let k = 0; k < 4; k++) s += a[k * 4 + j] * b[i * 4 + k];
    o[i * 4 + j] = s;
  }
  return o;
}

/* ---------- holat ---------- */
const H = {
  natija: null, tahlil: null,
  P: null, n: 0, markaz: [0, 0, 0], min: [0, 0, 0], max: [0, 0, 0],
  kamera: { hedef: [0, 0, 0], masofa: 5, yaw: -1.0, pitch: 0.6 },
  mvp: null, mv: null, kozi: [0, 0, 0],
  asbob: "aylan", olchov: [], kesim: null,
  korsat: { bulut: true, server: true, telefon: true, loyiha: true }, rang: 0, olcham: 1.2, edl: true, tanlangan: 0, yaqin: 0.01, uzoq: 100,
  tarmoqRang: [0.145, 0.388, 0.922],
  taqqos: null, loyiha: null, izohlar: [], yozuvchi: false, izohNuqta: null,
};
let gl, canvas, prog = {}, bufer = {}, chizishKerak = true;

/* ---------- shaderlar ---------- */
const PALITRA = `vec3 palitra(float t){
  vec3 c0=vec3(0.153,0.204,0.286),c1=vec3(0.055,0.455,0.565),c2=vec3(0.204,0.827,0.600),c3=vec3(0.984,0.749,0.141),c4=vec3(0.796,0.835,0.882);
  if(t<0.25) return mix(c0,c1,t/0.25); if(t<0.5) return mix(c1,c2,(t-0.25)/0.25);
  if(t<0.75) return mix(c2,c3,(t-0.5)/0.25); return mix(c3,c4,(t-0.75)/0.25);}`;

const SH = {
  nuqta: [`#version 300 es
in vec3 a_p; in vec3 a_c; uniform mat4 u_mvp, u_mv; uniform float u_olcham, u_f, u_maks; uniform vec2 u_z; uniform int u_rang;
out vec3 v_r; ${PALITRA}
void main(){ vec4 m=u_mv*vec4(a_p,1.0); gl_Position=u_mvp*vec4(a_p,1.0);
  gl_PointSize=clamp(u_olcham*u_f/max(-m.z,0.05),1.5,u_maks);
  float t=clamp((a_p.z-u_z.x)/max(u_z.y-u_z.x,1e-3),0.0,1.0);
  v_r = u_rang==0 ? palitra(t) : u_rang==2 ? a_c : vec3(0.62,0.68,0.75); }`,
  `#version 300 es
precision mediump float; in vec3 v_r; out vec4 o;
void main(){ vec2 c=gl_PointCoord*2.0-1.0; float d=dot(c,c); if(d>1.0) discard; o=vec4(v_r*(1.0-0.18*d),1.0); }`],
  sirt: [`#version 300 es
in vec3 a_p; in vec3 a_n; uniform mat4 u_mvp; out vec3 v_n;
void main(){ gl_Position=u_mvp*vec4(a_p,1.0); v_n=a_n; }`,
  `#version 300 es
precision mediump float; in vec3 v_n; uniform vec4 u_rang; uniform vec3 u_yorug; out vec4 o;
void main(){ float l=0.38+0.62*abs(dot(normalize(v_n),u_yorug)); o=vec4(u_rang.rgb*l,u_rang.a); }`],
  // tanlash buferi: har nuqta o'z raqami bilan (id+1 → RGB) — kursor ostidagi KO'RINADIGAN nuqta aniq topiladi
  tanlash: [`#version 300 es
in vec3 a_p; uniform mat4 u_mvp, u_mv; uniform float u_olcham, u_f, u_maks; flat out int v_id;
void main(){ vec4 m=u_mv*vec4(a_p,1.0); gl_Position=u_mvp*vec4(a_p,1.0);
  gl_PointSize=clamp(u_olcham*u_f/max(-m.z,0.05),1.5,u_maks); v_id=gl_VertexID+1; }`,
  `#version 300 es
precision highp float; precision highp int; flat in int v_id; out vec4 o;
void main(){ vec2 c=gl_PointCoord*2.0-1.0; if(dot(c,c)>1.0) discard;
  o=vec4(float(v_id&255),float((v_id>>8)&255),float((v_id>>16)&255),255.0)/255.0; }`],
  // UI-22: EDL (eye-dome lighting) — Potree / CloudCompare usuli: chuqurlik sakrashlari qoraytiriladi
  edl: [`#version 300 es
out vec2 v_uv;
void main(){ vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2)); v_uv = p; gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0); }`,
  `#version 300 es
precision highp float;
uniform sampler2D u_rang; uniform highp sampler2D u_chuq;
uniform vec2 u_px; uniform float u_yaqin, u_uzoq, u_kuch; uniform vec3 u_fon;
in vec2 v_uv; out vec4 o;
float ld(float d){ float z = d * 2.0 - 1.0; return log2((2.0 * u_yaqin * u_uzoq) / (u_uzoq + u_yaqin - z * (u_uzoq - u_yaqin))); }
void main(){
  float d = texture(u_chuq, v_uv).r;
  if (d >= 1.0) { o = vec4(u_fon, 1.0); return; }
  float l = ld(d), s = 0.0;
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.7853982;
    float dn = texture(u_chuq, v_uv + vec2(cos(a), sin(a)) * u_px * 1.5).r;
    if (dn < 1.0) s += max(0.0, l - ld(dn));
  }
  o = vec4(texture(u_rang, v_uv).rgb * exp(-s / 8.0 * 300.0 * u_kuch), 1.0);
}`],
  // KU-04: M3C2 o'zgarish qatlami — ishorali masofa ikki tomonlama shkalada (moviy-yashil − / to'q sariq +), LoD ichidagisi
  // kulrang. Ko'k va qizil EMAS: suv quvuri modeli ko'k, elektr kabeli qizil — "quvur cho'kdi" deb o'qilmasin
  farq: [`#version 300 es
in vec3 a_p; in float a_f; in float a_l; uniform mat4 u_mvp, u_mv; uniform float u_olcham, u_f, u_maks, u_shkala; out vec3 v_r;
void main(){ vec4 m=u_mv*vec4(a_p,1.0); gl_Position=u_mvp*vec4(a_p,1.0);
  gl_PointSize=clamp(u_olcham*u_f/max(-m.z,0.05),2.0,u_maks);
  if (a_f != a_f) { v_r = vec3(0.55,0.58,0.62); return; }
  float t = clamp(a_f/max(u_shkala,1e-4), -1.0, 1.0);
  vec3 r = t < 0.0 ? mix(vec3(0.79,0.81,0.85), vec3(0.05,0.58,0.53), -t) : mix(vec3(0.79,0.81,0.85), vec3(0.92,0.35,0.05), t);
  v_r = abs(a_f) <= a_l ? mix(r, vec3(0.62,0.65,0.70), 0.75) : r; }`,
  `#version 300 es
precision mediump float; in vec3 v_r; out vec4 o;
void main(){ vec2 c=gl_PointCoord*2.0-1.0; float d=dot(c,c); if(d>1.0) discard; o=vec4(v_r*(1.0-0.15*d),1.0); }`],
  chiziq: [`#version 300 es
in vec3 a_p; in float a_s; uniform mat4 u_mvp; out float v_s;
void main(){ gl_Position=u_mvp*vec4(a_p,1.0); v_s=a_s; gl_PointSize=7.0; }`,
  `#version 300 es
precision mediump float; in float v_s; uniform vec4 u_rang; uniform float u_punktir; out vec4 o;
void main(){ if(u_punktir>0.0 && mod(v_s,u_punktir)>u_punktir*0.55) discard; o=u_rang; }`],
};

function dastur(vs, fs) {
  const ol = (tur, m) => {
    const s = gl.createShader(tur);
    gl.shaderSource(s, m); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  };
  const p = gl.createProgram();
  gl.attachShader(p, ol(gl.VERTEX_SHADER, vs)); gl.attachShader(p, ol(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  const u = {}, n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < n; i++) { const a = gl.getActiveUniform(p, i); u[a.name] = gl.getUniformLocation(p, a.name); }
  return { p, u, a: (nom) => gl.getAttribLocation(p, nom) };
}

function vao(pr, qatlamlar, indekslar) {
  const v = gl.createVertexArray();
  gl.bindVertexArray(v);
  for (const [nom, massiv, olcham] of qatlamlar) {
    const joy = pr.a(nom);
    if (joy < 0) continue;
    const b = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, b);
    gl.bufferData(gl.ARRAY_BUFFER, massiv, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(joy);
    // DS-07: rang — Uint8 (0…255 → 0…1 normallangan)
    if (massiv instanceof Uint8Array) gl.vertexAttribPointer(joy, olcham, gl.UNSIGNED_BYTE, true, 0, 0);
    else gl.vertexAttribPointer(joy, olcham, gl.FLOAT, false, 0, 0);
  }
  let soni = qatlamlar[0][1].length / qatlamlar[0][2];
  if (indekslar) {
    const b = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indekslar, gl.STATIC_DRAW);
    soni = indekslar.length;
  }
  gl.bindVertexArray(null);
  return { v, soni, indeksli: !!indekslar };
}

/* ---------- geometriya: naycha (quvur) va chiziq ---------- */
function naycha(P, r, n = 20) {
  const v = [], nr = [], ix = [];
  let N = null;
  for (let i = 0; i < P.length; i++) {
    const oldin = P[Math.max(i - 1, 0)], keyin = P[Math.min(i + 1, P.length - 1)];
    const T = V.birlik(V.ayir(keyin, oldin));
    if (!N) N = V.birlik(V.kross(T, Math.abs(T[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0]));
    N = V.birlik(V.ayir(N, V.kop(T, V.nuqta(N, T))));
    const B = V.kross(T, N);
    for (let k = 0; k < n; k++) {
      const a = 2 * Math.PI * k / n, d = V.qosh(V.kop(N, Math.cos(a)), V.kop(B, Math.sin(a)));
      v.push(...V.qosh(P[i], V.kop(d, r))); nr.push(...d);
    }
  }
  for (let i = 0; i + 1 < P.length; i++) for (let k = 0; k < n; k++) {
    const a = i * n + k, b = i * n + (k + 1) % n, c = (i + 1) * n + k, d = (i + 1) * n + (k + 1) % n;
    ix.push(a, c, b, b, c, d);
  }
  for (const [i, s] of [[0, -1], [P.length - 1, 1]]) {   // qopqoqlar
    const T = V.birlik(V.ayir(P[Math.min(i + 1, P.length - 1)], P[Math.max(i - 1, 0)]));
    const m = v.length / 3;
    v.push(...P[i]); nr.push(...V.kop(T, s));
    for (let k = 0; k < n; k++) ix.push(m, i * n + k, i * n + (k + 1) % n);
  }
  return { v: new Float32Array(v), n: new Float32Array(nr), ix: new Uint32Array(ix) };
}

/** Kamera quvur boshlanishi ortida, quvur bo'ylab 14° qiya qaraydi (tor transheyada devor quvurni to'smasin). */
function boylabYaw(q) {
  const a = q.oq_enu[0], b = q.oq_enu[q.oq_enu.length - 1];
  return Math.atan2(b[1] - a[1], b[0] - a[0]) + Math.PI + 0.25;
}

/** Poliliniyada yoy uzunligi bo'yicha `u` (0…1) ulushdagi nuqta. */
function yoyNuqtasi(P, u) {
  let jami = 0;
  for (let i = 1; i < P.length; i++) jami += V.uz(V.ayir(P[i], P[i - 1]));
  let qoldi = jami * u;
  for (let i = 1; i < P.length; i++) {
    const l = V.uz(V.ayir(P[i], P[i - 1]));
    if (qoldi <= l && l > 0) return V.qosh(P[i - 1], V.kop(V.ayir(P[i], P[i - 1]), qoldi / l));
    qoldi -= l;
  }
  return P[P.length - 1].slice();
}

function chiziqlar(P) {
  const v = [], s = [];
  let yol = 0;
  for (let i = 0; i < P.length; i++) {
    if (i) yol += V.uz(V.ayir(P[i], P[i - 1]));
    v.push(...P[i]); s.push(yol);
  }
  return { v: new Float32Array(v), s: new Float32Array(s) };
}

/* ---------- PLY (o'zimiz yozgan binary little-endian) ---------- */
/** x y z (float) + ixtiyoriy red green blue (uchar, DS-07) va boshqa xossalar (o'lchami bo'yicha o'tkaziladi) → {P, C}. */
function plyOqiToliq(buf) {
  const bayt = new Uint8Array(buf);
  const bosh = new TextDecoder("ascii").decode(bayt.subarray(0, Math.min(4096, bayt.length)));
  const k = bosh.indexOf("end_header\n");
  if (!bosh.startsWith("ply\n") || k < 0) throw new Error("PLY sarlavhasi o'qilmadi");
  const OLCHAM = { char: 1, int8: 1, uchar: 1, uint8: 1, short: 2, int16: 2, ushort: 2, uint16: 2, int: 4, int32: 4, uint: 4,
    uint32: 4, float: 4, float32: 4, double: 8, float64: 8 };
  let n = 0, qadam = 0, siljish = [0, 0, 0];
  const joy = {};
  for (const q of bosh.slice(0, k).split("\n")) {
    const m = q.trim().split(/\s+/);
    if (m[0] === "element" && m[1] === "vertex") n = parseInt(m[2], 10);
    if (m[0] === "property") { joy[m[2]] = qadam; qadam += OLCHAM[m[1]] || 4; }
    if (m[0] === "comment" && m[1] === "boshlangich") siljish = m.slice(2, 5).map(Number);
  }
  const dv = new DataView(buf, k + 11), P = new Float32Array(n * 3);
  if (dv.byteLength < n * qadam) throw new Error("PLY kesilgan");
  const rangli = joy.red != null && joy.green != null && joy.blue != null;
  const C = rangli ? new Uint8Array(n * 3) : null;
  for (let i = 0; i < n; i++) {
    const o = i * qadam;
    P[i * 3] = dv.getFloat32(o + joy.x, true) + siljish[0];
    P[i * 3 + 1] = dv.getFloat32(o + joy.y, true) + siljish[1];
    P[i * 3 + 2] = dv.getFloat32(o + joy.z, true) + siljish[2];
    if (C) { C[i * 3] = dv.getUint8(o + joy.red); C[i * 3 + 1] = dv.getUint8(o + joy.green); C[i * 3 + 2] = dv.getUint8(o + joy.blue); }
  }
  return { P, C };
}
function plyOqi(buf) { return plyOqiToliq(buf).P; }

/** KU-04: farq PLY (x y z farq lod, float32) → {P, farq, lod}. */
function plyOqiFarq(buf) {
  const bayt = new Uint8Array(buf);
  const bosh = new TextDecoder("ascii").decode(bayt.subarray(0, Math.min(4096, bayt.length)));
  const k = bosh.indexOf("end_header\n");
  if (!bosh.startsWith("ply\n") || k < 0) throw new Error("PLY sarlavhasi o'qilmadi");
  let n = 0;
  const nomlar = [];
  for (const q of bosh.slice(0, k).split("\n")) {
    const m = q.trim().split(/\s+/);
    if (m[0] === "element" && m[1] === "vertex") n = parseInt(m[2], 10);
    if (m[0] === "property") nomlar.push(m[2]);
  }
  const iF = nomlar.indexOf("farq"), iL = nomlar.indexOf("lod");
  if (iF < 0 || iL < 0) throw new Error("farq PLY da farq/lod yo'q");
  const dv = new DataView(buf, k + 11), qadam = nomlar.length * 4;
  const P = new Float32Array(n * 3), F = new Float32Array(n), L = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * qadam;
    P[i * 3] = dv.getFloat32(o, true); P[i * 3 + 1] = dv.getFloat32(o + 4, true); P[i * 3 + 2] = dv.getFloat32(o + 8, true);
    F[i] = dv.getFloat32(o + iF * 4, true); L[i] = dv.getFloat32(o + iL * 4, true);
  }
  return { P, farq: F, lod: L };
}

/* ---------- kamera ---------- */
function kozHolati() {
  const k = H.kamera, cp = Math.cos(k.pitch);
  return V.qosh(k.hedef, V.kop([cp * Math.cos(k.yaw), cp * Math.sin(k.yaw), Math.sin(k.pitch)], k.masofa));
}

function matritsalar() {
  const W = canvas.width, Hh = canvas.height;
  H.kozi = kozHolati();
  H.mv = qarash(H.kozi, H.kamera.hedef, [0, 0, 1]);
  H.yaqin = Math.max(H.kamera.masofa / 500, 0.01);
  H.uzoq = H.kamera.masofa * 60 + 50;
  const p = perspektiva(FOV, W / Hh, H.yaqin, H.uzoq);
  H.mvp = kopaytir(p, H.mv);
}

function boshlangichKorinish() {
  const d = V.uz(V.ayir(H.max, H.min)), q = H.natija.quvurlar[0];
  // transheya chuqur va tor: ko'ndalang qaralsa quvur devor ortida qoladi — transheya BO'YLAB, biroz qiya qaraymiz
  H.kamera = { hedef: q ? yoyNuqtasi(q.oq_enu, 0.5) : H.markaz.slice(), masofa: Math.max(d * 0.95, 1.5),
               yaw: q ? boylabYaw(q) : -2.2, pitch: 0.95 };
  chiz();
}

function ekranga(p) {
  const m = H.mvp, x = p[0], y = p[1], z = p[2];
  const w = m[3] * x + m[7] * y + m[11] * z + m[15];
  if (w <= 1e-4) return null;
  const cx = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w, cy = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w;
  return [(cx * 0.5 + 0.5) * canvas.clientWidth, (1 - (cy * 0.5 + 0.5)) * canvas.clientHeight, w];
}

let tanlashFB = null;
function tanlashBuferi(W, Hh) {
  if (tanlashFB && tanlashFB.W === W && tanlashFB.H === Hh) return tanlashFB;
  if (tanlashFB) { gl.deleteFramebuffer(tanlashFB.fb); gl.deleteTexture(tanlashFB.tx); gl.deleteRenderbuffer(tanlashFB.rb); }
  const fb = gl.createFramebuffer(), tx = gl.createTexture(), rb = gl.createRenderbuffer();
  gl.bindTexture(gl.TEXTURE_2D, tx);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, W, Hh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
  gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, W, Hh);
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tx, 0);
  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rb);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  tanlashFB = { fb, tx, rb, W, H: Hh };
  return tanlashFB;
}

/** Kursor ostidagi ko'rinadigan nuqta (GPU tanlash buferi, 8 px radiusda eng yaqini). */
function tanla(mx, my) {
  if (!H.korsat.bulut) return null;
  const W = canvas.width, Hh = canvas.height, dpr = W / canvas.clientWidth, t = tanlashBuferi(W, Hh);
  matritsalar();
  gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
  gl.viewport(0, 0, W, Hh);
  gl.clearColor(0, 0, 0, 0);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  gl.enable(gl.DEPTH_TEST);
  const pr = prog.tanlash;
  gl.useProgram(pr.p);
  gl.uniformMatrix4fv(pr.u.u_mvp, false, H.mvp);
  gl.uniformMatrix4fv(pr.u.u_mv, false, H.mv);
  gl.uniform1f(pr.u.u_olcham, ((H.natija.korinish && H.natija.korinish.voksel_m) || 0.015) * H.olcham);
  gl.uniform1f(pr.u.u_f, Hh / (2 * Math.tan(FOV / 2)));
  gl.uniform1f(pr.u.u_maks, 9 * dpr);
  gl.bindVertexArray(bufer.tanlash.v);
  gl.drawArrays(gl.POINTS, 0, bufer.tanlash.soni);
  gl.bindVertexArray(null);
  const R = Math.round(8 * dpr), cx = Math.round(mx * dpr), cy = Math.round(Hh - my * dpr);
  const x0 = Math.max(cx - R, 0), y0 = Math.max(cy - R, 0), w = Math.min(cx + R, W - 1) - x0 + 1, h = Math.min(cy + R, Hh - 1) - y0 + 1;
  let eng = -1, engD = Infinity;
  if (w > 0 && h > 0) {
    const px = new Uint8Array(w * h * 4);
    gl.readPixels(x0, y0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    for (let yy = 0; yy < h; yy++) for (let xx = 0; xx < w; xx++) {
      const o = (yy * w + xx) * 4, id = px[o] | px[o + 1] << 8 | px[o + 2] << 16;
      if (!id) continue;
      const d = (x0 + xx - cx) ** 2 + (y0 + yy - cy) ** 2;
      if (d < engD) { engD = d; eng = id - 1; }
    }
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  chiz();
  return eng < 0 || eng >= H.n ? null : [H.P[eng * 3], H.P[eng * 3 + 1], H.P[eng * 3 + 2]];
}

function utm(p) {
  const g = H.natija && H.natija.georef && H.natija.georef.server;
  if (!g) return null;
  const a = g.burchak_grad * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  return [c * p[0] - s * p[1] + g.t[0], s * p[0] + c * p[1] + g.t[1], p[2] + g.t[2], g.utm_zona];
}

/* ---------- chizish ---------- */
function chiz() {
  if (chizishKerak) return;
  chizishKerak = true;
  requestAnimationFrame(kadr);
}

function kadr() {
  chizishKerak = false;
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const W = Math.round(canvas.clientWidth * dpr), Hh = Math.round(canvas.clientHeight * dpr);
  if (canvas.width !== W || canvas.height !== Hh) { canvas.width = W; canvas.height = Hh; }
  const fonHex = getComputedStyle(document.documentElement).getPropertyValue("--y-fon").trim() || "#0A0F14";
  const fr = parseInt(fonHex.slice(1), 16), fon = [(fr >> 16 & 255) / 255, (fr >> 8 & 255) / 255, (fr & 255) / 255];
  matritsalar();
  const f = H.edl && H.korsat.bulut ? edlBuferi(W, Hh) : null;
  gl.bindFramebuffer(gl.FRAMEBUFFER, f ? f.fb : null);
  gl.viewport(0, 0, W, Hh);
  gl.clearColor(fon[0], fon[1], fon[2], 1);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  gl.enable(gl.DEPTH_TEST);
  bulutChiz(dpr, Hh);
  quvurlarChiz();
  kesimTekisligi();   // chuqurlik bilan — EDL buferi ichida ham to'g'ri yopiladi
  if (f) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, W, Hh);
    gl.disable(gl.DEPTH_TEST);
    const pr = prog.edl;
    gl.useProgram(pr.p);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, f.rang);
    gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, f.chuq);
    gl.uniform1i(pr.u.u_rang, 0);
    gl.uniform1i(pr.u.u_chuq, 1);
    gl.uniform2f(pr.u.u_px, 1 / W, 1 / Hh);
    gl.uniform1f(pr.u.u_yaqin, H.yaqin);
    gl.uniform1f(pr.u.u_uzoq, H.uzoq);
    gl.uniform1f(pr.u.u_kuch, 1.0);
    gl.uniform3f(pr.u.u_fon, fon[0], fon[1], fon[2]);
    gl.bindVertexArray(null);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.activeTexture(gl.TEXTURE0);
  }
  ustQatlamlar();
  gl.bindVertexArray(null);
  yorliqlar();
}

let edlFB = null;
/** EDL uchun kadr buferi: rang + chuqurlik teksturasi. Qo'llanmasa null — oddiy chizishga qaytiladi. */
function edlBuferi(W, Hh) {
  if (edlFB && edlFB.W === W && edlFB.H === Hh) return edlFB.ok ? edlFB : null;
  if (edlFB) { gl.deleteFramebuffer(edlFB.fb); gl.deleteTexture(edlFB.rang); gl.deleteTexture(edlFB.chuq); }
  const fb = gl.createFramebuffer(), rang = gl.createTexture(), chuq = gl.createTexture();
  const sozla = () => {
    for (const k of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER]) gl.texParameteri(gl.TEXTURE_2D, k, gl.NEAREST);
    for (const k of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, k, gl.CLAMP_TO_EDGE);
  };
  gl.bindTexture(gl.TEXTURE_2D, rang);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, W, Hh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  sozla();
  gl.bindTexture(gl.TEXTURE_2D, chuq);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, W, Hh, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null);
  sozla();
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, rang, 0);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, chuq, 0);
  const ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.bindTexture(gl.TEXTURE_2D, null);
  edlFB = { fb, rang, chuq, W, H: Hh, ok };
  return ok ? edlFB : null;
}

function bulutChiz(dpr, Hh) {
  if (!H.korsat.bulut || !bufer.bulut) return;
  const pr = prog.nuqta;
  gl.useProgram(pr.p);
  gl.uniformMatrix4fv(pr.u.u_mvp, false, H.mvp);
  gl.uniformMatrix4fv(pr.u.u_mv, false, H.mv);
  const voksel = (H.natija.korinish && H.natija.korinish.voksel_m) || 0.015;
  gl.uniform1f(pr.u.u_olcham, voksel * H.olcham);
  gl.uniform1f(pr.u.u_f, Hh / (2 * Math.tan(FOV / 2)));
  gl.uniform1f(pr.u.u_maks, 9 * dpr);
  gl.uniform2f(pr.u.u_z, H.min[2], H.max[2]);
  gl.uniform1i(pr.u.u_rang, H.rang);
  gl.bindVertexArray(bufer.bulut.v);
  gl.drawArrays(gl.POINTS, 0, bufer.bulut.soni);
  if (H.korsat.farq && bufer.farq && H.farq) {
    const pf = prog.farq;
    gl.useProgram(pf.p);
    gl.uniformMatrix4fv(pf.u.u_mvp, false, H.mvp);
    gl.uniformMatrix4fv(pf.u.u_mv, false, H.mv);
    gl.uniform1f(pf.u.u_olcham, Math.max(voksel, 0.05) * H.olcham * 1.3);
    gl.uniform1f(pf.u.u_f, Hh / (2 * Math.tan(FOV / 2)));
    gl.uniform1f(pf.u.u_maks, 14 * dpr);
    gl.uniform1f(pf.u.u_shkala, H.farq.shkala);
    gl.bindVertexArray(bufer.farq.v);
    gl.drawArrays(gl.POINTS, 0, bufer.farq.soni);
  }
}

function quvurlarChiz() {
  if (!H.korsat.server) return;
  const pr = prog.sirt;
  gl.useProgram(pr.p);
  gl.uniformMatrix4fv(pr.u.u_mvp, false, H.mvp);
  gl.uniform3f(pr.u.u_yorug, ...V.birlik(V.ayir(H.kozi, H.kamera.hedef)));
  gl.uniform4f(pr.u.u_rang, ...H.tarmoqRang, 1);
  for (const q of bufer.quvurlar) { gl.bindVertexArray(q.v); gl.drawElements(gl.TRIANGLES, q.soni, gl.UNSIGNED_INT, 0); }
}

/** Kesim tekisligi: yarim shaffof, chuqurlik tekshiruvi bilan. Chuqurlikka YOZADI: aks holda EDL qatlami fon piksellarida
 *  uni fon rangi bilan almashtirib yuboradi (tekislik oxirgi chiziladi — sahnani to'smaydi). */
function kesimTekisligi() {
  if (!bufer.kesim) return;
  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
  const pr = prog.sirt;
  gl.useProgram(pr.p);
  gl.uniformMatrix4fv(pr.u.u_mvp, false, H.mvp);
  gl.uniform3f(pr.u.u_yorug, 0, 0, 1);
  gl.uniform4f(pr.u.u_rang, 0.42, 0.61, 1.0, 0.22);
  gl.bindVertexArray(bufer.kesim.v);
  gl.drawElements(gl.TRIANGLES, bufer.kesim.soni, gl.UNSIGNED_INT, 0);
  gl.disable(gl.BLEND);
}

/** Telefon o'qi va o'lchov chizig'i — asosiy chizishdan keyin, chuqurliksiz (quvur ichidagi o'q ko'rinsin). */
function ustQatlamlar() {
  const cz = prog.chiziq;
  gl.useProgram(cz.p);
  gl.uniformMatrix4fv(cz.u.u_mvp, false, H.mvp);
  gl.disable(gl.DEPTH_TEST);   // telefon o'qi quvur ichida — ustidan ko'rinsin
  if (H.korsat.telefon) {
    gl.uniform4f(cz.u.u_rang, 1, 0.84, 0.04, 1);
    gl.uniform1f(cz.u.u_punktir, 0.08);
    for (const q of bufer.telefon) { gl.bindVertexArray(q.v); gl.drawArrays(gl.LINE_STRIP, 0, q.soni); }
  }
  if (bufer.taqqos && H.taqqos) {   // TL-02: boshqa sanadagi quvur o'qlari
    gl.uniform4f(cz.u.u_rang, 0.13, 0.83, 0.93, 1);
    gl.uniform1f(cz.u.u_punktir, 0.12);
    for (const q of bufer.taqqos) { gl.bindVertexArray(q.v); gl.drawArrays(gl.LINE_STRIP, 0, q.soni); }
  }
  if (bufer.loyiha && H.korsat.loyiha) {   // IH-07: loyiha chiziqlari
    gl.uniform4f(cz.u.u_rang, 0.75, 0.15, 0.83, 1);
    gl.uniform1f(cz.u.u_punktir, 0.3);
    for (const q of bufer.loyiha) { gl.bindVertexArray(q.v); gl.drawArrays(gl.LINE_STRIP, 0, q.soni); }
  }
  if (bufer.olchov) {
    gl.uniform4f(cz.u.u_rang, 1, 1, 1, 1);
    gl.uniform1f(cz.u.u_punktir, 0);
    gl.bindVertexArray(bufer.olchov.v);
    gl.drawArrays(gl.LINE_STRIP, 0, bufer.olchov.soni);
    gl.drawArrays(gl.POINTS, 0, bufer.olchov.soni);
  }
}

/** Ekrandagi yorliqlar (HTML va PNG eksport uchun bitta ro'yxat). */
function yorliqRoyxati() {
  const q = [];
  if (H.korsat.server) H.natija.quvurlar.forEach((p, i) => {
    const s = ekranga(yoyNuqtasi(p.oq_enu, 0.5));
    if (s) q.push({ x: s[0], y: s[1], matn: quvurNomi(p, i) + (p.chuqurlik_m != null ? " · " + mtr(p.chuqurlik_m) : ""), olchov: false });
  });
  H.izohlar.forEach((z, i) => {
    const s = ekranga([z.x, z.y, z.z]);
    if (s) q.push({ x: s[0], y: s[1], matn: `${i + 1}. ${z.matn.length > 42 ? z.matn.slice(0, 41) + "…" : z.matn}`, izoh: true });
  });
  if (H.olchov.length === 2) {
    const [a, b] = H.olchov, s = ekranga(V.kop(V.qosh(a, b), 0.5));
    const g = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (s) q.push({ x: s[0], y: s[1], matn: `${mtr(V.uz(V.ayir(b, a)))} · gor. ${mtr(g)} · Δh ${mtr(b[2] - a[2])}`, olchov: true });
  }
  return q;
}

function yorliqlar() {
  el("yorliqlar").innerHTML = yorliqRoyxati().map((y) =>
    `<div class="yorliq${y.olchov ? " olchov" : ""}${y.izoh ? " izoh" : ""}" style="left:${y.x}px;top:${y.y}px">${esc(y.matn)}</div>`).join("");
}

function quvurNomi(p, i) {
  const t = TARMOQ_NOMI[H.natija.jurnal && H.natija.jurnal.tarmoq] || "Quvur";
  return `${t} ${i + 1} · Ø${Math.round(p.standart_mm || p.diametr_mm)}`;
}

/* ---------- asboblar ---------- */
function olchovQosh(p) {
  if (H.olchov.length >= 2) H.olchov = [];
  H.olchov.push(p);
  const c = chiziqlar(H.olchov);
  bufer.olchov = vao(prog.chiziq, [["a_p", c.v, 3], ["a_s", c.s, 1]]);
  chiz();
}

/** Quvurga tik vertikal kesim: nuqta atrofidagi ±3 sm qatlam, quvur doirasi, qoplama chuqurligi. */
function kesimOch(p) {
  let eng = null;
  H.natija.quvurlar.forEach((q, i) => {
    for (let k = 0; k + 1 < q.oq_enu.length; k++) {
      const a = q.oq_enu[k], d = V.ayir(q.oq_enu[k + 1], a), l2 = V.nuqta(d, d) || 1;
      const u = Math.min(Math.max(V.nuqta(V.ayir(p, a), d) / l2, 0), 1);
      const c = V.qosh(a, V.kop(d, u)), gm = Math.hypot(p[0] - c[0], p[1] - c[1]);
      if (gm < 1.0 && (!eng || gm < eng.m)) eng = { i, q, c, d, m: gm, k, u };
    }
  });
  let n, C;
  if (eng) { n = V.birlik([eng.d[0], eng.d[1], 0]); C = eng.c; }
  else { const f = V.ayir(H.kamera.hedef, H.kozi); n = V.birlik([f[0], f[1], 0]); C = p; }
  const h = [-n[1], n[0], 0];
  H.kesim = { n, h, C, eng };
  // 3D da kesim tekisligi
  const kenglik = 1.6, z0 = H.min[2] - 0.05, z1 = H.max[2] + 0.05;
  const burchak = [[-kenglik, z0], [kenglik, z0], [kenglik, z1], [-kenglik, z1]].map(([u, z]) => [C[0] + h[0] * u, C[1] + h[1] * u, z]);
  const v = new Float32Array(burchak.flat()), nr = new Float32Array([...n, ...n, ...n, ...n]);
  bufer.kesim = vao(prog.sirt, [["a_p", v, 3], ["a_n", nr, 3]], new Uint32Array([0, 1, 2, 0, 2, 3]));
  el("kesim-panel").classList.remove("yashirin");
  kesimChiz();
  chiz();
}

function kesimChiz() {
  const k = H.kesim, cv = el("kesim-chizma"), dpr = Math.min(window.devicePixelRatio || 1, 2);
  cv.width = Math.round(cv.clientWidth * dpr); cv.height = Math.round(cv.clientHeight * dpr);
  const c = cv.getContext("2d"), W = cv.width, Hh = cv.height, P = H.P;
  const qatlam = 0.03, u = [], z = [];
  for (let i = 0; i < H.n; i++) {
    const dx = P[i * 3] - k.C[0], dy = P[i * 3 + 1] - k.C[1];
    if (Math.abs(dx * k.n[0] + dy * k.n[1]) > qatlam) continue;
    const uu = dx * k.h[0] + dy * k.h[1];
    if (Math.abs(uu) > 1.6) continue;
    u.push(uu); z.push(P[i * 3 + 2]);
  }
  const zmin = Math.min(...z, k.C[2] - 0.3) - 0.1, zmax = Math.max(...z, k.C[2] + 0.3) + 0.1;
  const umin = -1.6, umax = 1.6, chet = 34 * dpr;
  const s = Math.min((W - 2 * chet) / (umax - umin), (Hh - 2 * chet) / (zmax - zmin));   // 1:1 masshtab
  const ox = W / 2, oy = Hh / 2 + (zmax + zmin) / 2 * s;
  const X = (uu) => ox + uu * s, Y = (zz) => oy - zz * s;
  const cs = getComputedStyle(document.documentElement), css = { getPropertyValue: (n) => cs.getPropertyValue(n).trim() };
  c.fillStyle = css.getPropertyValue("--y-fon"); c.fillRect(0, 0, W, Hh);
  c.font = `${11 * dpr}px Noto Sans, sans-serif`; c.fillStyle = css.getPropertyValue("--y-matn3");
  c.strokeStyle = css.getPropertyValue("--y-chiziq"); c.lineWidth = dpr;
  const g = H.natija.georef && H.natija.georef.server;
  for (let zz = Math.ceil(zmin / 0.5) * 0.5; zz <= zmax; zz += 0.5) {
    c.beginPath(); c.moveTo(chet, Y(zz)); c.lineTo(W - 6 * dpr, Y(zz)); c.stroke();
    c.fillText(g ? vergul(zz + g.t[2], 2) : vergul(zz, 2), 4 * dpr, Y(zz) - 3 * dpr);
  }
  for (let uu = -1.5; uu <= 1.5; uu += 0.5) { c.beginPath(); c.moveTo(X(uu), chet / 2); c.lineTo(X(uu), Hh - chet / 2); c.stroke(); }
  const t = (zz) => Math.min(Math.max((zz - H.min[2]) / Math.max(H.max[2] - H.min[2], 1e-3), 0), 1);
  const stop = [[39, 52, 73], [14, 116, 144], [52, 211, 153], [251, 191, 36], [203, 213, 225]];
  for (let i = 0; i < u.length; i++) {
    const q = t(z[i]) * 4, j = Math.min(Math.floor(q), 3), f = q - j;
    const r = stop[j].map((v, m) => Math.round(v + (stop[j + 1][m] - v) * f));
    c.fillStyle = `rgb(${r})`;
    c.fillRect(X(u[i]) - 1.2 * dpr, Y(z[i]) - 1.2 * dpr, 2.4 * dpr, 2.4 * dpr);
  }
  let izoh = `±${vergul(qatlam * 100, 0)} sm qatlam · 1:1 masshtab · ${u.length} nuqta`;
  if (k.eng) {
    const q = k.eng.q, r = q.radius_m, rang = css.getPropertyValue(`--y-tarmoq-${H.natija.jurnal.tarmoq}`) || "#2563EB";
    c.lineWidth = 2.5 * dpr; c.strokeStyle = rang; c.fillStyle = rang + "55";
    c.beginPath(); c.arc(X(0), Y(k.C[2]), r * s, 0, 2 * Math.PI); c.fill(); c.stroke();
    yozuv(c, `Ø${Math.round(q.standart_mm || q.diametr_mm)} mm`, X(0) + r * s + 8 * dpr, Y(k.C[2]), "left", css.getPropertyValue("--y-matn"), dpr, css);
    if (q.chuqurlik_m != null) {
      const ust = k.C[2] + r, yer = ust + q.chuqurlik_m, ux = -0.75, sariq = css.getPropertyValue("--y-kamera-float");
      c.setLineDash([6 * dpr, 5 * dpr]); c.strokeStyle = css.getPropertyValue("--y-matn2"); c.lineWidth = 1.5 * dpr;
      c.beginPath(); c.moveTo(chet, Y(yer)); c.lineTo(W - 6 * dpr, Y(yer)); c.stroke();
      c.beginPath(); c.moveTo(X(ux - 0.08), Y(ust)); c.lineTo(X(-r), Y(ust)); c.stroke(); c.setLineDash([]);
      c.strokeStyle = sariq; c.lineWidth = 2 * dpr;
      c.beginPath(); c.moveTo(X(ux), Y(yer)); c.lineTo(X(ux), Y(ust));
      for (const yy of [yer, ust]) { c.moveTo(X(ux) - 6 * dpr, Y(yy)); c.lineTo(X(ux) + 6 * dpr, Y(yy)); }
      c.stroke();
      yozuv(c, `qoplama ${mtr(q.chuqurlik_m)}`, X(ux) - 10 * dpr, (Y(yer) + Y(ust)) / 2, "right", sariq, dpr, css);
      yozuv(c, "yer sirti (yadro hisobi)", X(-1.55), Y(yer) - 12 * dpr, "left", css.getPropertyValue("--y-matn2"), dpr, css);
    }
    const st = k.eng.q.oq_enu.slice(0, k.eng.k + 1).reduce((a, p, i, m) => a + (i ? V.uz(V.ayir(p, m[i - 1])) : 0), 0)
      + V.uz(V.ayir(k.eng.c, k.eng.q.oq_enu[k.eng.k]));
    izoh = `${quvurNomi(q, k.eng.i)} · stansiya ${mtr(st)} · ` + izoh;
  }
  el("kesim-izoh").textContent = izoh + (g ? " · balandlik UTM H" : " · balandlik mahalliy");
}

/** Kesim chizmasida fonli yozuv (nuqtalar ustida ham o'qilsin). */
function yozuv(c, matn, x, y, tomon, rang, dpr, css) {
  c.font = `600 ${12 * dpr}px Noto Sans, sans-serif`;
  const w = c.measureText(matn).width, h = 18 * dpr, x0 = tomon === "right" ? x - w - 12 * dpr : x;
  c.fillStyle = css.getPropertyValue("--y-sirt"); c.globalAlpha = 0.88;
  c.beginPath(); c.roundRect(x0, y - h / 2, w + 12 * dpr, h, 5 * dpr); c.fill(); c.globalAlpha = 1;
  c.fillStyle = rang; c.textBaseline = "middle"; c.fillText(matn, x0 + 6 * dpr, y + 0.5 * dpr); c.textBaseline = "alphabetic";
}

/* ---------- bo'ylama profil (UI-21) — ilova hisoboti bilan bir xil ma'lumot, quvur usti belgilari ---------- */
function quvurUsti(oq, r, s) {
  if (s <= oq[0][0]) return oq[0][1] + r;
  for (let i = 1; i < oq.length; i++) if (oq[i][0] >= s) {
    const a = oq[i - 1], b = oq[i], t = b[0] > a[0] ? (s - a[0]) / (b[0] - a[0]) : 0;
    return a[1] + (b[1] - a[1]) * t + r;
  }
  return oq[oq.length - 1][1] + r;
}

function profilOch(i) {
  H.tanlangan = i;
  el("profil-panel").classList.remove("yashirin");
  el("profil-tugma").classList.add("yoqilgan");
  profilChiz();
}

function profilYop() {
  el("profil-panel").classList.add("yashirin");
  el("profil-tugma").classList.remove("yoqilgan");
}

function profilChiz() {
  const q = H.natija.quvurlar[H.tanlangan];
  const cv = el("profil-chizma"), dpr = Math.min(window.devicePixelRatio || 1, 2);
  cv.width = Math.round(cv.clientWidth * dpr); cv.height = Math.round(cv.clientHeight * dpr);
  const c = cv.getContext("2d"), W = cv.width, Hh = cv.height;
  const cs = getComputedStyle(document.documentElement), tok = (n) => cs.getPropertyValue(n).trim();
  c.fillStyle = tok("--y-fon"); c.fillRect(0, 0, W, Hh);
  if (!q || !q.profil_oq || q.profil_oq.length < 2) {
    el("profil-izoh").textContent = "";
    c.fillStyle = tok("--y-matn2"); c.font = `${13 * dpr}px Noto Sans, sans-serif`;
    c.fillText("Bu tahlilda profil yo'q: admin qayta hisoblatsin (CLI 1.0 dan oldingi natija).", 14 * dpr, 30 * dpr);
    el("profil-jadval").innerHTML = "";
    return;
  }
  const g = H.natija.georef && H.natija.georef.server, d = g ? g.t[2] : 0, r = q.radius_m;
  const oq = q.profil_oq.map(([s, z]) => [s, z + d]), yer = (q.profil_yer || []).map(([s, z]) => [s, z + d]);
  const sMax = Math.max(oq[oq.length - 1][0], ...yer.map((p) => p[0]), 0.5);
  const hlar = [...oq.map((p) => p[1] - r), ...oq.map((p) => p[1] + r), ...yer.map((p) => p[1])];
  const hMin = Math.min(...hlar) - 0.15, hMax = Math.max(...hlar) + 0.15;
  const cl = 52 * dpr, cr = 14 * dpr, ct = 12 * dpr, cb = 30 * dpr;
  const X = (s) => cl + s / sMax * (W - cl - cr), Y = (h) => ct + (hMax - h) / (hMax - hMin) * (Hh - ct - cb);
  c.font = `${11 * dpr}px Noto Sans, sans-serif`; c.lineWidth = dpr; c.strokeStyle = tok("--y-chiziq"); c.fillStyle = tok("--y-matn3");
  const hq = [0.1, 0.25, 0.5, 1, 2].find((v) => (hMax - hMin) / v <= 6) || 5;
  for (let h = Math.ceil(hMin / hq) * hq; h <= hMax; h += hq) {
    c.beginPath(); c.moveTo(cl, Y(h)); c.lineTo(W - cr, Y(h)); c.stroke();
    c.fillText(vergul(h, 2), 4 * dpr, Y(h) + 4 * dpr);
  }
  const sq = [0.5, 1, 2, 5, 10, 20].find((v) => sMax / v <= 10) || 50;
  c.textAlign = "center";
  for (let s = 0; s <= sMax + 1e-9; s += sq) c.fillText(vergul(s, sq < 1 ? 1 : 0), X(s), Hh - 10 * dpr);
  c.textAlign = "left";
  const chiz = (nuqtalar, rang, qalin, punktir) => {
    c.beginPath(); c.setLineDash(punktir ? [6 * dpr, 5 * dpr] : []); c.strokeStyle = rang; c.lineWidth = qalin * dpr;
    nuqtalar.forEach(([s, h], i) => (i ? c.lineTo(X(s), Y(h)) : c.moveTo(X(s), Y(h)))); c.stroke(); c.setLineDash([]);
  };
  const tr = tok(`--y-tarmoq-${H.natija.jurnal && H.natija.jurnal.tarmoq}`) || tok("--y-urgu");
  chiz(yer, tok("--y-skanSifat"), 1.5, true);
  c.globalAlpha = 0.5; chiz(oq.map(([s, h]) => [s, h - r]), tr, 1.5, false); c.globalAlpha = 1;
  chiz(oq.map(([s, h]) => [s, h + r]), tr, 3, false);
  el("profil-izoh").textContent = `${quvurNomi(q, H.tanlangan)} · nishab ${vergul(q.qiyalik_foiz, 2)} % · ` +
    (g ? "H ellipsoid (UTM georeferens)" : "balandlik mahalliy") + " · vertikal masshtab kattalashtirilgan";
  const manba = yer.length ? yer : oq.map(([s]) => [s, null]);
  const qadam = Math.max(1, Math.ceil(manba.length / 14));
  let t = "<b>Stansiya</b><b>Quvur usti</b><b>Yer</b><b>Qoplama</b>";
  for (let i = 0; i < manba.length; i += qadam) {
    const [s, h] = manba[i], u = quvurUsti(oq, r, s);
    t += `<span>${vergul(s, 1)} m</span><span>${vergul(u, 2)}</span><span>${h == null ? "—" : vergul(h, 2)}</span>` +
         `<span>${h == null ? "—" : vergul(h - u, 2)}</span>`;
  }
  el("profil-jadval").innerHTML = t;
}

/* ---------- PNG eksport va to'liq ekran (UI-23) ---------- */
function rasmSaqlash() {
  kadr();   // shu vazifada chizib, bufer tozalanmasidan oldin nusxa olinadi
  const W = canvas.width, Hh = canvas.height, dpr = W / canvas.clientWidth, pastki = Math.round(34 * dpr);
  const cv = document.createElement("canvas");
  cv.width = W; cv.height = Hh + pastki;
  const c = cv.getContext("2d");
  c.drawImage(canvas, 0, 0);
  c.font = `700 ${12 * dpr}px Noto Sans, sans-serif`; c.textBaseline = "middle";
  for (const y of yorliqRoyxati()) {
    const w = c.measureText(y.matn).width + 18 * dpr, h = 22 * dpr, x0 = y.x * dpr - w / 2, y0 = y.y * dpr - h * 1.3;
    c.fillStyle = y.olchov ? "#2F6BEA" : y.izoh ? "#9A5500" : "rgba(10,15,20,.82)";
    c.beginPath(); c.roundRect(x0, y0, w, h, 7 * dpr); c.fill();
    c.fillStyle = "#F2F5F8"; c.fillText(y.matn, x0 + 9 * dpr, y0 + h / 2);
  }
  c.fillStyle = "#0A0F14"; c.fillRect(0, Hh, W, pastki);
  c.fillStyle = "#F2F5F8"; c.font = `${12 * dpr}px Noto Sans, sans-serif`;
  const t = H.tahlil;
  c.fillText(`TRACE4D View · ${t.obyekt_nomi || "obyekt #" + t.obyekt_id} · ${t.tur === "tashqi" ? "tashqi LiDAR: " + (t.manba_nomi || "skaner") : "muhr #" + t.muhr_id} · qayta hisob: ${H.natija.xulosa} · ` +
             new Date().toISOString().slice(0, 10), 12 * dpr, Hh + pastki / 2);
  cv.toBlob((b) => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(b);
    a.download = `trace4d-tahlil-${t.id}.png`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 3000);
  }, "image/png");
}

function toliqEkran() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen().catch(() => {});
}

/* ---------- boshqaruv ---------- */
function boshqaruv() {
  let bosildi = null, oxirgi = null, harakat = 0, ikkiOldingi = null;
  const kursorlar = new Map();
  canvas.addEventListener("contextmenu", (h) => h.preventDefault());
  canvas.addEventListener("pointerdown", (h) => {
    canvas.setPointerCapture(h.pointerId);
    kursorlar.set(h.pointerId, [h.clientX, h.clientY]);
    bosildi = { x: h.clientX, y: h.clientY, surish: h.button === 2 || h.shiftKey };
    oxirgi = [h.clientX, h.clientY]; harakat = 0;
    canvas.classList.add("bosilgan");
  });
  canvas.addEventListener("pointermove", (h) => {
    if (kursorlar.has(h.pointerId)) kursorlar.set(h.pointerId, [h.clientX, h.clientY]);
    if (!bosildi) { oqishYangila(h.clientX, h.clientY); return; }
    if (kursorlar.size === 2) { ikkiBarmoq(); return; }
    const dx = h.clientX - oxirgi[0], dy = h.clientY - oxirgi[1];
    oxirgi = [h.clientX, h.clientY]; harakat += Math.abs(dx) + Math.abs(dy);
    const k = H.kamera;
    if (bosildi.surish) {
      const olcham = k.masofa * 2 * Math.tan(FOV / 2) / canvas.clientHeight;
      const oldinga = V.birlik(V.ayir(k.hedef, H.kozi)), ong = V.birlik(V.kross(oldinga, [0, 0, 1])), yuq = V.kross(ong, oldinga);
      k.hedef = V.qosh(k.hedef, V.qosh(V.kop(ong, -dx * olcham), V.kop(yuq, dy * olcham)));
    } else {
      k.yaw -= dx * 0.006;
      k.pitch = Math.min(Math.max(k.pitch + dy * 0.006, -0.2), 1.555);
    }
    chiz();
  });
  const qoyib = (h) => {
    kursorlar.delete(h.pointerId);
    canvas.classList.remove("bosilgan");
    if (bosildi && harakat < 5 && h.type === "pointerup") {
      const p = tanla(h.clientX, h.clientY);
      if (p && H.asbob === "masofa") olchovQosh(p);
      else if (p && H.asbob === "kesim") kesimOch(p);
      else if (p && H.asbob === "izoh") izohFormaOch(p, h.clientX, h.clientY);
    }
    if (kursorlar.size === 0) bosildi = null;
    ikkiOldingi = null;
  };
  canvas.addEventListener("pointerup", qoyib);
  canvas.addEventListener("pointercancel", qoyib);
  canvas.addEventListener("dblclick", (h) => {
    const p = tanla(h.clientX, h.clientY);
    if (p) { H.kamera.hedef = p; chiz(); }
  });
  canvas.addEventListener("wheel", (h) => {
    h.preventDefault();
    H.kamera.masofa = Math.min(Math.max(H.kamera.masofa * Math.exp(h.deltaY * 0.0012), 0.3), 500);
    chiz();
  }, { passive: false });
  function ikkiBarmoq() {
    const [a, b] = [...kursorlar.values()];
    const d = Math.hypot(a[0] - b[0], a[1] - b[1]);
    if (ikkiOldingi) H.kamera.masofa = Math.min(Math.max(H.kamera.masofa * ikkiOldingi / Math.max(d, 1), 0.3), 500);
    ikkiOldingi = d; harakat += 10;
    chiz();
  }
  window.addEventListener("resize", () => {
    chiz();
    if (H.kesim) kesimChiz();
    if (!el("profil-panel").classList.contains("yashirin")) profilChiz();
  });
  for (const b of document.querySelectorAll("[data-asbob]")) b.addEventListener("click", () => {
    H.asbob = b.dataset.asbob;
    for (const x of document.querySelectorAll("[data-asbob]")) x.classList.toggle("faol", x === b);
    canvas.classList.toggle("nishon-rejim", H.asbob !== "aylan");
    if (H.asbob !== "masofa") { H.olchov = []; bufer.olchov = null; chiz(); }
  });
  el("yuqoridan").addEventListener("click", () => { H.kamera.pitch = 1.555; H.kamera.yaw = -Math.PI / 2; chiz(); });
  el("profil-tugma").addEventListener("click", () => (el("profil-panel").classList.contains("yashirin") ? profilOch(H.tanlangan) : profilYop()));
  el("profil-yop").addEventListener("click", profilYop);
  el("rasm").addEventListener("click", rasmSaqlash);
  el("toliq").addEventListener("click", toliqEkran);
  el("k-edl").addEventListener("change", (h) => { H.edl = h.target.checked; chiz(); });
  // UI-23: klaviatura yorliqlari (maydonga yozilayotganda ishlamaydi)
  window.addEventListener("keydown", (h) => {
    if (h.ctrlKey || h.metaKey || h.altKey || /^(INPUT|SELECT|TEXTAREA)$/.test((h.target && h.target.tagName) || "")) return;
    const k = h.key.toLowerCase();
    const asbob = { 1: "aylan", 2: "masofa", 3: "kesim", 4: H.yozuvchi ? "izoh" : null }[k];
    if (asbob) document.querySelector(`[data-asbob="${asbob}"]`).click();
    else if (k === "p") el("profil-tugma").click();
    else if (k === "e") { const c = el("k-edl"); c.checked = !c.checked; c.dispatchEvent(new Event("change")); }
    else if (k === "t") el("yuqoridan").click();
    else if (k === "r" || k === "0") el("qayta").click();
    else if (k === "f") toliqEkran();
    else if (k === "s") rasmSaqlash();
    else if (k === "escape") { el("kesim-yop").click(); profilYop(); izohFormaYop(); }
    else return;
    h.preventDefault();
  });
  el("qayta").addEventListener("click", boshlangichKorinish);
  el("kesim-yop").addEventListener("click", () => { el("kesim-panel").classList.add("yashirin"); H.kesim = null; bufer.kesim = null; chiz(); });
  el("k-bulut").addEventListener("change", (h) => { H.korsat.bulut = h.target.checked; chiz(); });
  el("k-farq").addEventListener("change", (h) => { H.korsat.farq = h.target.checked; chiz(); });
  el("k-server").addEventListener("change", (h) => { H.korsat.server = h.target.checked; chiz(); });
  el("k-telefon").addEventListener("change", (h) => { H.korsat.telefon = h.target.checked; chiz(); });
  el("k-loyiha").addEventListener("change", (h) => { H.korsat.loyiha = h.target.checked; chiz(); });
  el("izoh-bekor").addEventListener("click", izohFormaYop);
  el("izoh-forma").addEventListener("submit", izohSaqla);
  el("k-rang").addEventListener("change", (h) => {
    H.rang = h.target.value === "bir" ? 1 : h.target.value === "haqiqiy" ? 2 : 0;
    el("shkala").classList.toggle("yashirin", H.rang !== 0);
    chiz();
  });
  el("k-olcham").addEventListener("input", (h) => { H.olcham = Number(h.target.value); chiz(); });
}

let oqishVaqt = 0;
function oqishYangila(x, y) {
  const hozir = performance.now();
  if (hozir - oqishVaqt < 120) return;
  oqishVaqt = hozir;
  const r = canvas.getBoundingClientRect(), p = tanla(x - r.left, y - r.top), o = el("oqish");
  if (!p) { o.classList.add("yashirin"); return; }
  const u = utm(p);
  o.textContent = `mahalliy  x ${vergul(p[0], 3)}  y ${vergul(p[1], 3)}  z ${vergul(p[2], 3)}` +
    (u ? `\nUTM ${u[3]}N    E ${katta(u[0], 3)}  N ${katta(u[1], 3)}  H ${katta(u[2], 3)}` : "\ngeoreferens yo'q — faqat mahalliy ramka");
  o.classList.remove("yashirin");
}

/* ---------- panel ---------- */
function panelChiz(t) {
  const n = t.natija, x = el("xulosa");
  x.textContent = n.xulosa === "MOS" ? "MOS — telefon bilan mos" : n.xulosa === "FARQ" ? "FARQ"
    : n.xulosa === "TASHQI" ? "Tashqi LiDAR — georeferens tekshirilmagan, T-031 tasdig'i kutilmoqda" : n.xulosa;
  x.className = "nishon " + (n.xulosa === "MOS" ? "ok" : (n.xulosa === "FARQ" || n.xulosa === "TASHQI") ? "ogoh" : "xato");
  el("sarlavha").textContent = `${t.obyekt_nomi || "Obyekt #" + t.obyekt_id} · ${t.tur === "tashqi" ? "tashqi LiDAR: " + (t.manba_nomi || "skaner") : "muhr #" + t.muhr_id}`;
  const tarmoq = TARMOQ_NOMI[n.jurnal && n.jurnal.tarmoq] || "tarmoq";
  el("izoh").textContent = `${n.korinish.nuqtalar.toLocaleString("uz")} nuqta · voksel ${vergul(n.korinish.voksel_m * 100, 1)} sm · ${tarmoq} · qayta hisob ${vergul(n.vaqt_s, 2)} s`;
  const taqqos = new Map((n.taqqos || []).filter((q) => q.server).map((q) => [q.server, q]));
  el("quvurlar").innerHTML = n.quvurlar.length ? n.quvurlar.map((q, i) => {
    const tq = taqqos.get(i + 1);
    return `<div class="quvur" data-i="${i}" style="border-left-color:rgb(${H.tarmoqRang.map((v) => Math.round(v * 255))})">` +
      `<b>${esc(quvurNomi(q, i))} mm</b><div class="m">` +
      `<span>Chuqurlik <b>${q.chuqurlik_m != null ? mtr(q.chuqurlik_m) : "—"}</b></span>` +
      `<span>Nishab <b>${vergul(q.qiyalik_foiz, 2)} %</b></span>` +
      `<span>Uzunlik <b>${mtr(q.uzunlik_m, 1)}</b></span>` +
      `<span>Ishonch <b>${Math.round(q.ishonch * 100)} %</b></span>` +
      `<span>Muftalar <b>${q.mufta_soni}</b></span>` +
      `<span class="butun ${tq && tq.mos ? "mos" : "farq"}">Telefon natijasidan o'q farqi <b>${tq && tq.oq_farqi_m != null ? sm(tq.oq_farqi_m) : "—"}</b></span>` +
      `<span class="butun" id="q-loyiha-${i}"></span><span class="butun" id="q-taqqos-${i}"></span></div></div>`;
  }).join("") : `<div class="tafsilot">Serverda quvur aniqlanmadi.</div>`;
  for (const d of document.querySelectorAll(".quvur")) d.addEventListener("click", () => quvurgaUch(Number(d.dataset.i)));
  const j = n.jurnal || {}, g = n.georef || {}, s = g.server;
  const q = (a, b) => `<div class="q"><span>${a}</span><b>${b}</b></div>`;
  let h = q("Muhr zanjiri", `${esc((j.bosh || "").slice(0, 12))}… · ${j.yozuvlar} yozuv`) +
    q("PLY muhrlangan faylmi", j.ply_muhrlangan ? "ha" : "YO'Q") +
    q("Georeferens juftlari", `${j.juftlar} · NMEA da ${g.juftlar_nmeada_topildi} · RASMIY ${g.juftlar_rasmiy}`) +
    q("Server georeferensi", s ? `RMS ${sm(s.gorizontal_rms_m)} / ${sm(s.vertikal_rms_m)}` : "yo'q") +
    q("Telefon bilan farq", g.siljish_farqi_m != null ? `${sm(g.siljish_farqi_m)} · ${vergul(g.burchak_farqi_grad, 4)}°` : "—") +
    q("Quvurlar (server / telefon)", `${n.quvurlar.length} / ${n.telefon_quvurlar.length}`);
  for (const x2 of n.sabablar || []) h += `<div class="sabab">${esc(x2)}</div>`;
  for (const x2 of n.ogohlantirishlar || []) h += `<div>${esc(x2)}</div>`;
  el("tafsilot").innerHTML = h;
  el("shkala-past").textContent = s ? vergul(H.min[2] + s.t[2], 2) : vergul(H.min[2], 2);
  el("shkala-yuqori").textContent = (s ? vergul(H.max[2] + s.t[2], 2) : vergul(H.max[2], 2)) + " m";
}

function quvurgaUch(i) {
  const q = H.natija.quvurlar[i], o = q.oq_enu, mid = yoyNuqtasi(o, 0.5);
  H.kamera = { hedef: mid, masofa: Math.max(q.uzunlik_m * 1.1, 3), yaw: boylabYaw(q), pitch: 0.95 };
  chiz();
  kesimOch(mid);
  profilOch(i);
}

function xabar(html) {
  el("xabar").innerHTML = html;
  el("xabar").classList.remove("yashirin");
  el("izoh").textContent = "";
}

/* ---------- ishga tushirish ---------- */
async function boshla() {
  const id = Number(new URLSearchParams(location.search).get("tahlil"));
  if (!id) return xabar("Tahlil tanlanmagan. Portaldagi obyekt panelidan «3D ko'rish» ni bosing.");
  if (ULASH) {
    const b = document.querySelector(".brend");
    b.href = `/u/${ULASH}`;
    b.title = "Ulashilgan obyekt sahifasi";
  }
  let r = await fetch(`${API}/tahlil/${id}`, SOROV);
  if (r.status === 401) return xabar(`Kirish kerak. <a href="/">Portalga kiring</a>, so'ng sahifani yangilang.`);
  if (r.status === 410) return xabar("Havola muddati tugagan yoki bekor qilingan. Obyekt egasidan yangi havola so'rang.");
  if (!r.ok) return xabar("Tahlil topilmadi.");
  const t = await r.json();
  if (t.holat !== "tayyor" || !t.natija || !t.natija.korinish)
    return xabar(`Tahlil hali tayyor emas (holat: ${esc(t.holat)}). Ishchi navbatni bajargach ochiladi.`);
  canvas = el("sahna");
  gl = canvas.getContext("webgl2", { antialias: true });
  if (!gl) return xabar("Brauzer WebGL2 ni qo'llamaydi — zamonaviy Chrome, Edge, Firefox yoki Safari kerak.");
  r = await fetch(`${API}/tahlil/${id}/korinish.ply`, SOROV);
  if (!r.ok) return xabar("Ko'rinish fayliga ruxsat yo'q yoki fayl topilmadi.");
  const ply = plyOqiToliq(await r.arrayBuffer());
  H.P = ply.P;
  H.C = ply.C;
  H.n = H.P.length / 3;
  H.natija = t.natija; H.tahlil = t;
  const k = t.natija.korinish;
  H.min = k.min; H.max = k.max; H.markaz = V.kop(V.qosh(k.min, k.max), 0.5);
  const rang = getComputedStyle(document.documentElement).getPropertyValue(`--y-tarmoq-${t.natija.jurnal && t.natija.jurnal.tarmoq}`).trim();
  if (/^#[0-9a-f]{6}$/i.test(rang)) { const v = parseInt(rang.slice(1), 16); H.tarmoqRang = [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255]; }

  prog.nuqta = dastur(...SH.nuqta);
  prog.sirt = dastur(...SH.sirt);
  prog.chiziq = dastur(...SH.chiziq);
  prog.tanlash = dastur(...SH.tanlash);
  prog.farq = dastur(...SH.farq);
  prog.edl = dastur(...SH.edl);
  bufer.bulut = vao(prog.nuqta, H.C ? [["a_p", H.P, 3], ["a_c", H.C, 3]] : [["a_p", H.P, 3]]);
  // DS-07: zich bulutda haqiqiy rang bor — standart shu rejim
  if (H.C) {
    const tan = el("k-rang");
    if (tan && !tan.querySelector('option[value="haqiqiy"]')) tan.insertAdjacentHTML("afterbegin", '<option value="haqiqiy">Haqiqiy rang (kamera)</option>');
    if (tan) tan.value = "haqiqiy";
    H.rang = 2;
    el("shkala").classList.add("yashirin");
  }
  bufer.tanlash = vao(prog.tanlash, [["a_p", H.P, 3]]);
  bufer.quvurlar = t.natija.quvurlar.map((q) => { const m = naycha(q.oq_enu, q.radius_m + 0.012); return vao(prog.sirt, [["a_p", m.v, 3], ["a_n", m.n, 3]], m.ix); });
  bufer.telefon = t.natija.telefon_quvurlar.map((q) => { const c = chiziqlar(q.oq_enu); return vao(prog.chiziq, [["a_p", c.v, 3], ["a_s", c.s, 1]]); });
  panelChiz(t);
  boshqaruv();
  chizishKerak = false;
  boshlangichKorinish();
  window._yerosti3d = H;   // sinov/otladka tutqichi
  if (!ULASH) {
    try {
      const m = await (await fetch("/api/v1/men", SOROV)).json();
      H.yozuvchi = ["admin", "operator"].includes(m.foydalanuvchi && m.foydalanuvchi.rol);
    } catch { H.yozuvchi = false; }
  }
  el("izoh-asbob").classList.toggle("yashirin", !H.yozuvchi);
  el("klavish-izoh").classList.toggle("yashirin", !H.yozuvchi);
  if (ULASH) el("izoh").textContent += " · ulashilgan havola, faqat o'qish";
  await Promise.all([sanalarYukla(t).catch(() => {}), loyihaYukla(t).catch(() => {}), izohlarYukla().catch(() => {})]);
}

/* ---------- UTM ↔ mahalliy (joriy tahlil georeferensi) ---------- */
function utmdanMahalliy(e, n, z) {
  const g = H.natija.georef.server, a = g.burchak_grad * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  const dx = e - g.t[0], dy = n - g.t[1];
  return [c * dx + s * dy, -s * dx + c * dy, z == null ? null : z - g.t[2]];
}

function mahalliydanUtm(p, g) {
  const a = g.burchak_grad * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  return [c * p[0] - s * p[1] + g.t[0], s * p[0] + c * p[1] + g.t[1], p[2] + g.t[2]];
}

/** Nuqtadan poliliniyagacha gorizontal masofa, shu joyda balandlik farqi; poliliniya uchidan tashqaridagi nuqta — ichida=false. */
function engYaqin(P, p) {
  let eng = { gor: Infinity, dz: 0, ichida: false };
  for (let k = 0; k + 1 < P.length; k++) {
    const a = P[k], b = P[k + 1], dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy || 1e-12;
    const u = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2, uc = Math.min(Math.max(u, 0), 1);
    const d = Math.hypot(p[0] - (a[0] + dx * uc), p[1] - (a[1] + dy * uc));
    if (d < eng.gor) {
      const za = a[2] == null || b[2] == null ? null : a[2] + (b[2] - a[2]) * uc;
      eng = { gor: d, dz: za == null || p[2] == null ? null : p[2] - za, ichida: !(k === 0 && u < 0) && !(k === P.length - 2 && u > 1) };
    }
  }
  return eng;
}

/* ---------- TL-02: sanalar va taqqoslash ---------- */
async function sanalarYukla(t) {
  const quti = el("sanalar");
  const yol = ULASH ? `${API}/tahlillar` : `/api/v1/tahlillar?obyekt_id=${t.obyekt_id}`;
  const ro = ((await (await fetch(yol, SOROV)).json()).tahlillar || []).filter((x) => x.holat === "tayyor" && x.korinish);
  const boshqa = ro.filter((x) => x.id !== t.id);
  if (!boshqa.length) { quti.innerHTML = `<div class="tafsilot">Shu obyektda boshqa skan yo'q. Keyingi skan muhrlangach shu yerda taqqoslanadi.</div>`; return; }
  quti.innerHTML = boshqa.map((x) => `<div class="sana" data-id="${x.id}"><div class="sana-bosh"><b>Skan #${x.id}</b>` +
    `<span>${esc(mahalliySana(x.tugagan || x.yaratilgan))}</span>` +
    `<span class="nishon ${x.xulosa === "MOS" ? "ok" : x.xulosa === "FARQ" ? "ogoh" : "xato"}">${esc(x.xulosa || x.holat)}</span></div>` +
    `<div class="sana-tugma"><label class="bayroq"><input type="checkbox" data-taqqos="${x.id}"> Ustma-ust</label>` +
    (ULASH ? "" : `<a href="#" data-farq="${x.id}" title="M3C2: bulutlar orasidagi o'zgarish, LoD95 bilan">O'zgarish</a>`) +
    `<a href="?tahlil=${x.id}">Ochish</a></div><div class="sana-natija" id="sana-natija-${x.id}"></div></div>`).join("");
  for (const a of quti.querySelectorAll("[data-farq]")) a.addEventListener("click", (h) => { h.preventDefault(); farqHisobla(t, Number(a.dataset.farq)); });
  for (const c of quti.querySelectorAll("[data-taqqos]")) c.addEventListener("change", async () => {
    for (const d of quti.querySelectorAll("[data-taqqos]")) if (d !== c) d.checked = false;
    for (const d of quti.querySelectorAll(".sana-natija")) d.textContent = "";
    H.natija.quvurlar.forEach((_, i) => { const s2 = el(`q-taqqos-${i}`); if (s2) s2.innerHTML = ""; });
    H.taqqos = null; bufer.taqqos = null;
    if (c.checked) await taqqosYoq(Number(c.dataset.taqqos));
    chiz();
  });
}

/** KU-04: joriy tahlil (A) va boshqa sana (B) orasidagi M3C2 o'zgarish: server navbati → ishchi → farq buluti A ramkasida. */
async function farqHisobla(t, bId) {
  const natija = el(`sana-natija-${bId}`);
  natija.textContent = "O'zgarish hisoblanmoqda (M3C2)…";
  try {
    const r = await fetch(`/api/v1/obyekt/${t.obyekt_id}/farq`, { ...SOROV, method: "POST", headers: { ...(SOROV.headers || {}), "Content-Type": "application/json" },
      body: JSON.stringify({ a: t.id, b: bId }) });
    const j = await r.json();
    if (!r.ok) throw new Error(j.xato || `xato ${r.status}`);
    let f = null;
    for (let i = 0; i < 150; i++) {
      await new Promise((ok) => setTimeout(ok, 2000));
      f = await (await fetch(`/api/v1/tahlil/${j.tahlil_id}`, SOROV)).json();
      if (f.holat === "tayyor" || f.holat === "xato") break;
      natija.textContent = `Hisoblanmoqda… ${(i + 1) * 2} s`;
    }
    if (!f || f.holat !== "tayyor") throw new Error((f && f.xato) || "ishchi javob bermadi");
    const x = f.farq || {};
    const d = plyOqiFarq(await (await fetch(`/api/v1/tahlil/${j.tahlil_id}/korinish.ply`, SOROV)).arrayBuffer());
    // shkala: o'zgargan joy bo'lsa — ahamiyatli nuqtalar bo'yicha (aks holda o'zgarmagan sirt shkalani 2–3 sm ga siqib qo'yadi)
    const asos = x.dog_p95_abs_m > 0 ? x.dog_p95_abs_m : x.p95_ahamiyatli_abs_m > 0 ? x.p95_ahamiyatli_abs_m : (x.p95_abs_m || 0.05);
    const shkala = Math.max(0.02, Math.min(0.5, asos * 1.1));
    H.farq = { id: j.tahlil_id, shkala, xulosa: x };
    H.korsat.farq = true;
    bufer.farq = { ...vao(prog.farq, [["a_p", d.P, 3], ["a_f", d.farq, 1], ["a_l", d.lod, 1]]), soni: d.P.length / 3 };
    el("k-farq-q").classList.remove("yashirin"); el("k-farq").checked = true;
    el("farq-shkala").classList.remove("yashirin"); el("farq-izoh").classList.remove("yashirin");
    el("farq-past").textContent = `−${vergul(shkala * 100, 0)} sm`; el("farq-yuqori").textContent = `+${vergul(shkala * 100, 0)} sm`;
    el("farq-izoh").textContent = `M3C2 #${t.id} → #${bId}: ${x.baholangan} yadro nuqta, ahamiyatli ${x.ahamiyatli} (${Math.round((x.ahamiyatli_ulush || 0) * 100)} %), ` +
      `o'rtacha ${vergul((x.ortacha_m || 0) * 100, 1)} sm, maks ${vergul((x.maks_abs_m || 0) * 100, 1)} sm, LoD95 ${vergul((x.lod95_ortacha_m || 0) * 100, 1)} sm. ` +
      (x.dog_soni ? `Eng katta o'zgarish dog'i ${vergul(x.dog_maydon_m2 || 0, 2)} m², o'rtacha ${x.dog_ortacha_m > 0 ? "+" : "−"}${vergul(Math.abs(x.dog_ortacha_m || 0) * 100, 1)} sm. ` : "") +
      `Kulrang — LoD ichida (shovqindan ajralmaydi). Musbat — B sirt A dan yuqori.`;
    natija.textContent = `O'zgarish: ${f.xulosa === "OZGARISH" ? "BOR" : "yo'q"} — ` +
      (x.dog_soni ? `dog' ${vergul(x.dog_maydon_m2 || 0, 2)} m², o'rtacha ${x.dog_ortacha_m > 0 ? "+" : "−"}${vergul(Math.abs(x.dog_ortacha_m || 0) * 100, 1)} sm; ` : "") +
      `ahamiyatli ${Math.round((x.ahamiyatli_ulush || 0) * 100)} %`;
    chiz();
  } catch (e) { natija.textContent = `O'zgarish hisoblanmadi: ${e.message}`; }
}

async function taqqosYoq(id) {
  const natija = el(`sana-natija-${id}`);
  natija.textContent = "Yuklanmoqda…";
  const t2 = await (await fetch(`${API}/tahlil/${id}`, SOROV)).json();
  const g1 = H.natija.georef && H.natija.georef.server, g2 = t2.natija && t2.natija.georef && t2.natija.georef.server;
  if (!g1 || !g2) { natija.textContent = "Taqqoslab bo'lmaydi: skanlardan birida server georeferensi yo'q (UTM orqali ustma-ust qo'yiladi)."; return; }
  const oqlar = t2.natija.quvurlar.map((q) => q.oq_enu.map((p) => { const u = mahalliydanUtm(p, g2); return utmdanMahalliy(u[0], u[1], u[2]); }));
  H.taqqos = { id, oqlar };
  bufer.taqqos = oqlar.filter((P) => P.length >= 2).map((P) => { const c = chiziqlar(P); return vao(prog.chiziq, [["a_p", c.v, 3], ["a_s", c.s, 1]]); });
  const qatorlar = [];
  H.natija.quvurlar.forEach((q, i) => {
    let gor = null, ver = null;
    for (const L of oqlar) for (const p of L) {
      const r = engYaqin(q.oq_enu, p);
      if (r.gor > 1.0 || !r.ichida) continue;   // 1 m dan uzoq — boshqa quvur
      gor = Math.max(gor ?? 0, r.gor);
      if (r.dz != null) ver = Math.max(ver ?? 0, Math.abs(r.dz));
    }
    const m = gor == null ? "mos quvur topilmadi" : `gorizontal ${sm(gor)} · vertikal ${ver == null ? "—" : sm(ver)}`;
    qatorlar.push(`${quvurNomi(q, i)}: ${m}`);
    const s2 = el(`q-taqqos-${i}`);
    if (s2) s2.innerHTML = `Skan #${id} bilan eng katta og'ish <b>${gor == null ? "—" : sm(gor)}</b>`;
  });
  natija.innerHTML = qatorlar.map(esc).join("<br>") + `<br><span class="izoh-kul">Firuza punktir — skan #${id} quvur o'qlari (UTM orqali).</span>`;
}

/* ---------- IH-07: loyiha DXF qatlami ---------- */
const Z_TURI = { usti: "quvur usti", oq: "quvur o'qi", tubi: "quvur tubi" };
async function loyihaYukla(t) {
  const holat = el("loyiha-holat");
  const yol = ULASH ? `${API}/loyiha` : `/api/v1/obyekt/${t.obyekt_id}/loyiha`;
  const l = (await (await fetch(yol, SOROV)).json()).loyiha;
  if (!l) { holat.textContent = "Loyiha DXF yuklanmagan."; el("k-loyiha").disabled = true; return; }
  if (!(H.natija.georef && H.natija.georef.server)) { holat.textContent = "Georeferens yo'q: loyiha qo'yilmaydi."; el("k-loyiha").disabled = true; return; }
  const ell = l.z_tizimi === "ellipsoid", yer = H.max[2];
  const markaz = H.markaz, radius = V.uz(V.ayir(H.max, H.min)) + 50;
  const chiz2 = l.chiziqlar.map((c) => c.nuqtalar.map(([e, n, z]) => {
    const p = utmdanMahalliy(e, n, ell ? z : null);
    if (p[2] == null) p[2] = yer;   // balandliksiz yoki Boltiq — rejadagi o'rni yer sathida
    return p;
  })).filter((P) => P.some((p) => Math.hypot(p[0] - markaz[0], p[1] - markaz[1]) < radius));
  H.loyiha = { l, chiziqlar: chiz2 };
  bufer.loyiha = chiz2.filter((P) => P.length >= 2).map((P) => { const c = chiziqlar(P); return vao(prog.chiziq, [["a_p", c.v, 3], ["a_s", c.s, 1]]); });
  holat.textContent = `${l.fayl_nomi} · ${chiz2.length} chiziq yaqinida · ` +
    (ell ? `balandlik: ${Z_TURI[l.z_turi] || l.z_turi} (ellipsoid)` : "balandlik Boltiq yoki yo'q: yer sathida chizildi");
  H.natija.quvurlar.forEach((q, i) => {
    let maks = null;
    for (const p of q.oq_enu) {
      let eng = Infinity;
      for (const P of chiz2) eng = Math.min(eng, engYaqin(P, p).gor);
      if (eng <= 5) maks = Math.max(maks ?? 0, eng);   // 5 m dan uzoq — boshqa tarmoq loyihasi
    }
    const s2 = el(`q-loyiha-${i}`);
    if (s2) s2.innerHTML = `Loyihadan gorizontal og'ish maks <b>${maks == null ? "yaqin chiziq yo'q" : sm(maks)}</b>`;
  });
  chiz();
}

/* ---------- TL-03: izohlar ---------- */
async function izohlarYukla() {
  const r = await fetch(`${API}/tahlil/${H.tahlil.id}/izohlar`, SOROV);
  H.izohlar = r.ok ? ((await r.json()).izohlar || []) : [];
  const quti = el("izohlar");
  quti.innerHTML = H.izohlar.length ? H.izohlar.map((z, i) => `<div class="izoh-qator" data-i="${i}"><b>${i + 1}</b><div>${esc(z.matn)}` +
    `<small>${esc(z.muallif || "—")} · ${esc(mahalliySana(z.yaratilgan))}</small></div></div>`).join("")
    : `<div class="tafsilot">${H.yozuvchi ? "Izoh yo'q. «Izoh» asbobini tanlab, nuqtani bosing (4)." : "Izoh yo'q."}</div>`;
  for (const d of quti.querySelectorAll(".izoh-qator")) d.addEventListener("click", () => {
    const z = H.izohlar[Number(d.dataset.i)];
    H.kamera.hedef = [z.x, z.y, z.z];
    H.kamera.masofa = Math.min(H.kamera.masofa, 4);
    chiz();
  });
  chiz();
}

function izohFormaOch(p, x, y) {
  if (!H.yozuvchi) return;
  H.izohNuqta = p;
  const f = el("izoh-forma");
  f.classList.remove("yashirin");
  f.style.left = Math.min(Math.max(x - 140, 10), window.innerWidth - 300) + "px";
  f.style.top = Math.min(Math.max(y + 14, 70), window.innerHeight - 170) + "px";
  el("izoh-xato").textContent = "";
  el("izoh-matn").value = "";
  el("izoh-matn").focus();
}

function izohFormaYop() {
  el("izoh-forma").classList.add("yashirin");
  H.izohNuqta = null;
}

async function izohSaqla(h) {
  h.preventDefault();
  const p = H.izohNuqta, matn = el("izoh-matn").value.trim();
  if (!p || !matn) return;
  const r = await fetch(`/api/v1/tahlil/${H.tahlil.id}/izohlar`, { method: "POST", credentials: "same-origin",
    headers: { "X-Yerosti": "1", "Content-Type": "application/json" }, body: JSON.stringify({ x: p[0], y: p[1], z: p[2], matn }) });
  if (!r.ok) { el("izoh-xato").textContent = ((await r.json().catch(() => ({}))).xato) || `xato ${r.status}`; return; }
  izohFormaYop();
  await izohlarYukla();
}

boshla().catch((x) => xabar("Xato: " + esc(x.message)));
