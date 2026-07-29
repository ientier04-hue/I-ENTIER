# i-ENTIER Patient

Application Flutter patient de l’écosystème i-ENTIER. L’authentification, les
dossiers de santé, les rendez-vous, les notifications et les ordonnances sont
stockés dans Supabase.

## Démarrage

```sh
flutter pub get
flutter run
```

Le projet Supabase et la connexion Google sont documentés dans
[docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md).

Le parcours de financement solidaire et le raccordement du prestataire de
paiement sont documentés dans
[docs/CROWDFUNDING_SETUP.md](docs/CROWDFUNDING_SETUP.md).

## Base de données

Le schéma relationnel partagé par Patient, Professionnel et Administration est
dans `supabase/migrations`. La migration démarre avec une base Supabase vide :
les anciens comptes et données de test Firebase ne sont pas repris.
