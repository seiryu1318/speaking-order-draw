const CACHE_PREFIXES=['speaking-order-draw-','speaking-draw-'];
const CACHE='speaking-order-draw-v22';
const SCOPE_URL=new URL(self.registration.scope);
const APP_PAGE='./2%ED%95%99%EB%85%84%20%EB%A7%90%ED%95%98%EA%B8%B0%20%EC%A0%9C%EB%B9%84%EB%BD%91%EA%B8%B0.html';
const APP_PAGE_URL=new URL(APP_PAGE, SCOPE_URL);
const FILES=[
  './','./index.html',APP_PAGE,`${APP_PAGE}?v=22`,
  './manifest.webmanifest?v=22','./manifest-legacy.webmanifest?v=22',
  './icon.svg','./icon-180.png?v=15','./icon-192.png?v=15','./icon-512.png?v=15',
  './html2canvas.min.js?v=1','./xlsx.full.min.js?v=1','./Sortable.min.js?v=1'
];
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE)
    .then((cache) => cache.addAll(FILES.map(
      (path) => new Request(new URL(path, SCOPE_URL), { cache: 'reload' })
    )))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys
      .filter((key) => key !== CACHE && CACHE_PREFIXES.some((prefix) => key.startsWith(prefix)))
      .map((key) => caches.delete(key))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(SCOPE_URL.href)) return;

  const isNavigation = request.mode === 'navigate';
  const isDrawPage = new URL(request.url).pathname === APP_PAGE_URL.pathname;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (!isNavigation) {
      const cached = await cache.match(request);
      if (cached) return cached;
    }

    let response;
    try {
      response = await fetch(request);
    } catch {
      if (!isNavigation) return Response.error();
      return (await cache.match(request)) ||
        (isDrawPage && await cache.match(APP_PAGE_URL.href)) ||
        Response.error();
    }
    if (response.ok && !response.redirected) {
      await cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  })());
});
