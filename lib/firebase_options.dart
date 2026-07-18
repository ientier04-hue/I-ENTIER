// Generated from the Firebase project I-ENTIER (i-entier).
// Firebase API keys identify the project; access control must be enforced by
// Firebase Authentication and security rules, never by hiding these values.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase n’est pas configuré pour cette plateforme.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCj5HpAo0hdBqJ_jPJT5ySARAky3lVYzNA',
    appId: '1:273373283430:web:149c6f16df3652c47c19a7',
    messagingSenderId: '273373283430',
    projectId: 'i-entier',
    authDomain: 'i-entier.firebaseapp.com',
    storageBucket: 'i-entier.firebasestorage.app',
    measurementId: 'G-6FS6G1RJ4V',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDaKC1GhR_94odUsI4OBp4gisV3tI6sY4o',
    appId: '1:273373283430:android:7eef2a7e171341697c19a7',
    messagingSenderId: '273373283430',
    projectId: 'i-entier',
    storageBucket: 'i-entier.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAveONotYBgI4FiTEwmGK9p8dz6qCqeaRc',
    appId: '1:273373283430:ios:d524daf7ea7a22d97c19a7',
    messagingSenderId: '273373283430',
    projectId: 'i-entier',
    storageBucket: 'i-entier.firebasestorage.app',
    iosBundleId: 'com.ientier.iEntier',
  );
}
