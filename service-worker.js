const CACHE = 'speaking-draw-v1';
const FILES = ['./','./index.html','./2%ED%95%99%EB%85%84%20%EB%A7%90%ED%95%98%EA%B8%B0%20%EC%A0%9C%EB%B9%84%EB%BD%91%EA%B8%B0.html','./manifest.webmanifest','./icon.svg'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => { if (e.request.method === 'GET') e.respondWith(caches.match(e.request).then(r => r || fetch(e.request))); });
