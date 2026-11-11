const CACHE='speaking-draw-v19';
const APP_PAGE='./2%ED%95%99%EB%85%84%20%EB%A7%90%ED%95%98%EA%B8%B0%20%EC%A0%9C%EB%B9%84%EB%BD%91%EA%B8%B0.html';
const FILES=[
  './','./index.html',APP_PAGE,`${APP_PAGE}?v=19`,
  './manifest.webmanifest?v=19','./manifest-legacy.webmanifest?v=19',
  './icon.svg','./icon-180.png?v=15','./icon-192.png?v=15','./icon-512.png?v=15',
  './html2canvas.min.js?v=1','./xlsx.full.min.js?v=1','./Sortable.min.js?v=1'
];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET') return;
  if(e.request.mode==='navigate') {
    e.respondWith(fetch(e.request).then(res=>{const copy=res.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));return res;}).catch(()=>caches.match(e.request)));
    return;
  }
  e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(res=>{const copy=res.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));return res;})));
});
