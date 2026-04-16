const CACHE_NAME = 'unsa-energie-v10';
const ASSETS_TO_CACHE = [
  './',
  './index.html',
  './admin.html',
  './manifest.json',
  './logo.png',
  './favicon.png',
  './icons/icon-192x192.png',
  './icons/icon-512x512.png',
  'https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800;900&family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&display=swap'
];

// Install — cache core assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSETS_TO_CACHE))
      .then(() => self.skipWaiting())
  );
});

// Activate — clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch — network first, cache fallback (for dynamic content like Supabase)
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Skip Supabase API calls — always go to network
  if (url.hostname.includes('supabase.co') || url.hostname.includes('openrouter.ai')) {
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then(response => {
        // Cache successful GET requests
        if (event.request.method === 'GET' && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});

// Push notification received
self.addEventListener('push', event => {
  let data = { title: 'UNSA Énergie', body: 'Nouvelle notification', icon: './icons/icon-192x192.png' };
  try { data = { ...data, ...event.data.json() }; } catch (e) {}
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: data.icon || './icons/icon-192x192.png',
      badge: './icons/icon-96x96.png',
      vibrate: [200, 100, 200],
      data: { url: data.url || './' },
      actions: data.actions || []
    })
  );
});

// Notification click
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = event.notification.data.url || './';
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(list => {
      for (const client of list) {
        if (client.url.includes('unsa-energie-pwa') && 'focus' in client) return client.focus();
      }
      return clients.openWindow(url);
    })
  );
});
