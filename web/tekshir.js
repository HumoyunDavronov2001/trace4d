"use strict";
/* IH-08: PDF xeshini brauzerda hisoblash — fayl serverga yuborilmaydi. crypto.subtle faqat HTTPS (yoki localhost) da. */
(function () {
  const quti = document.getElementById("xesh-tekshir");
  const fayl = document.getElementById("xesh-fayl");
  const natija = document.getElementById("xesh-natija");
  if (!quti || !fayl || !natija) return;
  const kutilgan = (quti.dataset.sha256 || "").toLowerCase();
  fayl.addEventListener("change", async () => {
    const f = fayl.files && fayl.files[0];
    natija.className = "o-natija";
    if (!f) { natija.textContent = ""; return; }
    if (!window.crypto || !crypto.subtle) {
      natija.textContent = "Brauzer xeshni hisoblay olmaydi (HTTPS kerak). Pastdagi buyruqdan foydalaning.";
      return;
    }
    natija.textContent = "Hisoblanmoqda…";
    const x = new Uint8Array(await crypto.subtle.digest("SHA-256", await f.arrayBuffer()));
    const hex = Array.from(x, (b) => b.toString(16).padStart(2, "0")).join("");
    if (hex === kutilgan) {
      natija.classList.add("mos");
      natija.textContent = "Mos: bu fayl reestrdagi hujjatning aynan o'zi.";
    } else {
      natija.classList.add("farq");
      natija.textContent = "Mos emas: fayl o'zgartirilgan yoki boshqa hujjat. Xesh: " + hex;
    }
  });
})();
