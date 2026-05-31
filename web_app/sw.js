/* Minimal service worker — enables “Add to Home Screen” / installed app mode. Network-first (always live data). */
const SW_VERSION = 'ba-sales-v5';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});
