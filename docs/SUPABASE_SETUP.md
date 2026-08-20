# Supabase — i-ENTIER

Les quatre applications Flutter utilisent le projet Supabase
`dktjnxbtyhxvapyheosh` et le schéma PostgreSQL `ientier`.

La base démarre volontairement vide. Les nouveaux utilisateurs sont créés et
gérés directement par Supabase Auth.

## Configuration du projet Supabase

1. Appliquer, dans l’ordre, les fichiers de `supabase/migrations`.
   Pour activer les opérations Pharmacie sur une base déjà initialisée,
   appliquer `20260810172603_add_pharmacy_operations.sql` après les migrations
   précédentes.
2. Dans **Project Settings > API**, ajouter `ientier` aux schémas exposés.
3. La clé publique est déjà configurée dans les quatre clients. Elle peut être
   remplacée au build avec `SUPABASE_PUBLISHABLE_KEY`. Ne jamais placer la clé
   `service_role` dans une application Flutter.
4. Dans **Authentication > URL Configuration**, définir le Site URL de
   production et autoriser :
   - `com.ientier.i_entier://login-callback`
   - `com.ientier.i_entier_professionnel://login-callback`
   - `com.ientier.i_entier_pharmacie://login-callback`
   - les URL Web locales et de production utilisées par l’administration.

## Connexion anonyme

Dans **Authentication > Providers**, activer **Allow anonymous sign-ins** pour
le projet hébergé. La configuration locale équivalente est déjà activée avec
`auth.enable_anonymous_sign_ins = true` dans `supabase/config.toml`.

Le client Patient propose alors **Continuer en mode invité**. Supabase crée un
utilisateur avec le rôle PostgreSQL `authenticated` et le claim JWT
`is_anonymous = true`; les politiques RLS existantes continuent donc à isoler
ses données avec `auth.uid()`. Un compte invité ne peut pas être récupéré après
une déconnexion, un changement d’appareil ou l’effacement des données locales.

Avant une mise en production à grande échelle, activer CAPTCHA/Turnstile et
prévoir la purge périodique des comptes anonymes anciens pour limiter les abus.

## Connexion Google

Dans Google Cloud Console, le client OAuth Web doit autoriser l’URI :

```text
https://dktjnxbtyhxvapyheosh.supabase.co/auth/v1/callback
```

Reporter ensuite son Client ID et son Client Secret dans
**Authentication > Providers > Google** de Supabase. Les schémas d’URL mobiles
sont déjà déclarés dans Android et iOS pour les applications Patient,
Professionnel et Pharmacie.

## Lancement

```sh
flutter pub get
flutter run
```

Les valeurs `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` possèdent déjà la
configuration du projet. Elles peuvent être remplacées avec `--dart-define`.

## Sécurité

Les données sont protégées par des politiques RLS. Les décisions
administratives, les mouvements de stock, les ventes, les réceptions d’achat et
les commandes patient passent par des fonctions SQL atomiques. Le catalogue
patient n’expose que les produits publiés par une pharmacie active. Le bucket
`prescriptions` reste privé et n’autorise que le propriétaire du dossier à
accéder à son préfixe.
