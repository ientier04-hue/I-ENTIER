# Supabase — i-ENTIER

Les trois applications Flutter utilisent le projet Supabase
`dktjnxbtyhxvapyheosh` et le schéma PostgreSQL `ientier`.

La base démarre volontairement sans les comptes ni les données de test
Firebase. Les nouveaux utilisateurs seront créés directement par Supabase Auth.

## Configuration du projet Supabase

1. Appliquer, dans l’ordre, les fichiers de `supabase/migrations`.
2. Dans **Project Settings > API**, ajouter `ientier` aux schémas exposés.
3. La clé publique est déjà configurée dans les trois clients. Elle peut être
   remplacée au build avec `SUPABASE_PUBLISHABLE_KEY`. Ne jamais placer la clé
   `service_role` dans une application Flutter.
4. Dans **Authentication > URL Configuration**, définir le Site URL de
   production et autoriser :
   - `com.ientier.i_entier://login-callback`
   - `com.ientier.i_entier_professionnel://login-callback`
   - les URL Web locales et de production utilisées par l’administration.

## Connexion Google

Dans Google Cloud Console, le client OAuth Web doit autoriser l’URI :

```text
https://dktjnxbtyhxvapyheosh.supabase.co/auth/v1/callback
```

Reporter ensuite son Client ID et son Client Secret dans
**Authentication > Providers > Google** de Supabase. Les schémas d’URL mobiles
sont déjà déclarés dans Android et iOS pour les applications Patient et
Professionnel.

## Lancement

```sh
flutter pub get
flutter run
```

Les valeurs `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` possèdent déjà la
configuration du projet. Elles peuvent être remplacées avec `--dart-define`.

## Sécurité

Les données sont protégées par les politiques RLS de la migration initiale.
Les décisions administratives et les réponses aux rendez-vous passent par des
fonctions SQL atomiques. Le bucket `prescriptions` est privé et n’autorise que
le propriétaire du dossier à accéder à son préfixe.
