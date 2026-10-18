// Keeps Kontaa opening with no internet. Receipt links and sync go straight to the network.
const CACHE = "kontaa-v1";
const FILES = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.endsWith("/r.html")) return;
  // Saved copy first so weak signal never slows the shop down; the fresh copy is fetched
  // in the background and used the next time Kontaa opens.
  e.respondWith(caches.open(CACHE).then(async (c) => {
    const saved = await c.match(e.request, { ignoreSearch: true });
    const fresh = fetch(e.request).then((res) => { if (res.ok) c.put(e.request, res.clone()); return res; });
    if (saved) { e.waitUntil(fresh.catch(() => {})); return saved; }
    return fresh.catch(() => c.match("./index.html"));
  }));
});
