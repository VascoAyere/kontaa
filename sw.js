// Keeps Kontaa opening with no internet. Receipt links and sync go straight to the network.
const CACHE = "kontaa-v2";
const FILES = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES.map((f) => new Request(f, { cache: "reload" })))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.endsWith("/r.html")) return;
  // Newest version first, so updates show the next time Kontaa opens. If the network is
  // missing or takes more than 4 seconds, the saved copy opens instead.
  e.respondWith(caches.open(CACHE).then(async (c) => {
    const saved = await c.match(e.request, { ignoreSearch: true });
    const fresh = fetch(e.request, { cache: "no-cache" }).then((res) => { if (res.ok) c.put(e.request, res.clone()); return res; });
    if (!saved) return fresh.catch(() => c.match("./index.html"));
    e.waitUntil(fresh.catch(() => {}));
    return Promise.race([fresh, new Promise((ok) => setTimeout(() => ok(saved), 4000))]).catch(() => saved);
  }));
});
