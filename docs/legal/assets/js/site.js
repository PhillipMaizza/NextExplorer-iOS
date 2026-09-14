/* NextExplorer site: shared header + footer injection, theme toggle. */
(function () {
  var LOGO =
    '<svg viewBox="0 0 96 96" aria-hidden="true">' +
    '<linearGradient id="lg-a" gradientUnits="userSpaceOnUse" x1="29.86" x2="29.86" y1="21.003" y2="72.2939"><stop offset="0" stop-color="#fecb50"/><stop offset="1" stop-color="#f9b54b"/></linearGradient>' +
    '<linearGradient id="lg-b" gradientUnits="userSpaceOnUse" x1="30.96" x2="30.96" y1="65.9392" y2="20.3341"><stop offset="0" stop-color="#f9a22f"/><stop offset="1" stop-color="#f8ba37"/></linearGradient>' +
    '<linearGradient id="lg-c" gradientUnits="userSpaceOnUse" x1="65.04" x2="65.04" y1="65.1732" y2="29.7664"><stop offset="0" stop-color="#f9a22f"/><stop offset="1" stop-color="#f8ba37"/></linearGradient>' +
    '<linearGradient id="lg-d" gradientUnits="userSpaceOnUse" x1="66.435" x2="66.435" y1="19.9817" y2="75.7713"><stop offset="0" stop-color="#fecb50"/><stop offset="1" stop-color="#f9b54b"/></linearGradient>' +
    '<path d="m43.57 66.49-27.42 10.17v-57.32z" fill="url(#lg-a)"/>' +
    '<path d="m45.77 30.9601v34.7199l-2.2.81-27.42-47.15z" fill="url(#lg-b)"/>' +
    '<path d="m79.85 76.66-29.62-10.98v-34.7199l2.79-1.0901z" fill="url(#lg-c)"/>' +
    '<path d="m79.85 19.34v57.32l-26.83-46.79z" fill="url(#lg-d)"/>' +
    '</svg>';

  var HEADER =
    '<header><div class="wrap topbar">' +
    '<a class="brand" href="index.html" aria-label="NextExplorer for iOS home">' +
    LOGO + '<span class="name">NextExplorer for iOS</span></a>' +
    '<button class="theme-toggle" id="themeToggle" type="button" aria-label="Toggle color theme">' +
    '<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>' +
    '<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>' +
    '</button></div></header>';

  var FOOTER =
    '<footer class="pagefoot"><div class="wrap">' +
    '<div class="footrow">' +
    '<p class="foot-tag"><span class="name">NextExplorer for iOS</span>: a client for the files on your own server.</p>' +
    '<nav class="foot-links">' +
    '<a href="index.html">Home</a>' +
    '<a href="privacy.html">Privacy</a>' +
    '<a href="terms.html">Terms</a>' +
    '<a href="mailto:hello@phillipmaizza.com">Support</a>' +
    '</nav></div>' +
    '<p class="foot-copy">&copy; <span id="footYear">2026</span> Phillip Maizza.</p>' +
    '</div></footer>';

  function mount(id, html) {
    var el = document.getElementById(id);
    if (el) el.innerHTML = html;
  }

  mount("site-header", HEADER);
  mount("site-footer", FOOTER);

  var y = document.getElementById("footYear");
  if (y) y.textContent = String(new Date().getFullYear());

  var root = document.documentElement;
  var btn = document.getElementById("themeToggle");
  function current() {
    var t = root.getAttribute("data-theme");
    if (t) return t;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  if (btn) {
    btn.addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("ne-theme", next); } catch (e) {}
    });
  }
})();
