# Firebase — I-ENTIER

Le projet Flutter est relié au projet Firebase `i-entier` pour Android, iOS et Web. La configuration SDK est dans `lib/firebase_options.dart` et Firebase est initialisé au lancement.

1. Connectez-vous au compte Google autorisé dans un navigateur ou via `firebase login`.
2. Installez l’outil requis : `dart pub global activate flutterfire_cli`.
3. À la racine du projet, lancez : `flutterfire configure --project=i-entier` si les identifiants de plateformes changent.
4. Lors de l’ajout de services (Authentication, Firestore, Storage), activez-les dans la console Firebase et définissez leurs règles d’accès avant de les consommer dans l’app.

Ne placez jamais un mot de passe Google dans le code, les variables de build ou Git.
