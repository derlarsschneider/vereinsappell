importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

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
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: 'icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
