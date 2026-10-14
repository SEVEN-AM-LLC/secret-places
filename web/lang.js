// Bilingual pages: every block exists in both languages; <html lang> picks one.
(function () {
  var root = document.documentElement;
  function pick() {
    try { var saved = localStorage.getItem("sp-lang"); if (saved === "en" || saved === "uk") return saved; } catch (e) {}
    var q = new URLSearchParams(location.search).get("lang");
    if (q === "en" || q === "uk") return q;
    return /^(uk|ru)\b/i.test(navigator.language || "") ? "uk" : "en";
  }
  function apply(lang) {
    root.lang = lang;
    document.querySelectorAll(".lang button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    });
    var t = document.querySelector('meta[name="title-' + lang + '"]');
    if (t) document.title = t.content;
  }
  // Loaded in <head>: set the language before first paint, sync buttons once the DOM exists.
  var initial = pick();
  root.lang = initial;
  document.addEventListener("DOMContentLoaded", function () { apply(root.lang || initial); });
  document.addEventListener("click", function (e) {
    var b = e.target.closest(".lang button");
    if (!b) return;
    apply(b.dataset.lang);
    try { localStorage.setItem("sp-lang", b.dataset.lang); } catch (err) {}
  });
})();
