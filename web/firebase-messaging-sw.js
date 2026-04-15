importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

// Take control immediately so push subscriptions are tied to this SW.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

firebase.initializeApp({
  apiKey: "AIzaSyARJfC5X_25RTZjHZQhOtFThFrrlXqH_f0",
  authDomain: "vereinsappell.firebaseapp.com",
  projectId: "vereinsappell",
  storageBucket: "vereinsappell.firebasestorage.app",
  messagingSenderId: "336568095877",
  appId: "1:336568095877:web:39669b73fb3fd869e8c5ec",
  measurementId: "G-JBREPFQ05W"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  // payload.notification is populated from webpush.notification in the FCM payload.
  // Fall back to payload.data for backwards compatibility.
  const title = payload.notification?.title || payload.data?.title || '';
  const notificationOptions = {
    body: payload.notification?.body || payload.data?.body || '',
    icon: 'icons/Icon-192.png',
    data: {
      url: payload.data?.url || '/',
    },
  };
  self.registration.showNotification(title, notificationOptions);
});

self.addEventListener('notificationclick', function(event) {
  const url = event.notification.data?.url || "/";
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(clientList => {
      for (let client of clientList) {
        if (client.url.endsWith(url) && 'focus' in client) {
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
