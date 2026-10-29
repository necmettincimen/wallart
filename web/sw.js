// Uygulama dosyaları önce ağdan alınır, böylece yeni sürüm hemen gelir;
// ağ yoksa son kaydedilen kopya kullanılır. Dış kaynaklar (API, görseller) önbelleğe alınmaz.
const CACHE = 'wallart';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match('./')))
  );
});
