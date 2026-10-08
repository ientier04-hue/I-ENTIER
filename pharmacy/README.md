# Pharmacie I-ENTIER

Projet React Native / Expo autonome pour Android, iOS et le web. Ce dossier possède son propre package.json et lockfile : il peut être déplacé dans un dépôt séparé sans dépendre de Flutter. Le backend Supabase et les comptes restent partagés avec I-ENTIER.

## Développement

Node 22.13+ et npm sont requis.

```sh
npm ci
npm run web
# ou npm run android / npm run ios
```

Copier `.env.example` vers `.env.local` pour choisir un autre backend. Utiliser uniquement une clé publique Supabase, jamais une clé secrète. Les migrations du backend I-ENTIER doivent être présentes, notamment les opérations pharmacie et l’exposition du schéma `ientier`.

Catalogue publié, recherche et catégories, pharmacies, panier limité à une pharmacie, contrôle de stock, dépôt et consultation d’ordonnances, commandes, accès invité sans formulaire de connexion. Les stocks et autorisations sont revérifiés par la fonction serveur `place_pharmacy_order`. Aucun catalogue fictif n’est affiché en cas d’erreur.

L’ouverture réutilise la session locale ou crée automatiquement une session invitée Supabase. Aucun écran de connexion ni inscription n’est affiché. Le mode anonymous_users doit être activé dans Supabase Auth (déjà activé sur le projet actuel). Les règles RLS existantes continuent de protéger les documents et commandes par visiteur. La session est conservée sur l’appareil ; effacer son stockage fait perdre l’accès au dossier invité. Aucun jeton ni identifiant patient n’est transmis dans l’URL. La session invitée n’importe pas automatiquement le dossier du compte Flutter.

## Vérification et export

```sh
npm run typecheck
npm run lint
npm test
npm run build:web
```

Le dossier `dist/` peut être hébergé sur un domaine dédié. Configurer le serveur pour renvoyer `index.html` pour les routes inconnues. Pour un sous-dossier, définir `PHARMACY_BASE_PATH` avant l’export. L’hôte doit autoriser l’intégration par l’origine de l’app Flutter (`frame-ancestors`) et ne pas envoyer `X-Frame-Options: DENY`.

## Intégration Flutter

```sh
flutter run --dart-define=PHARMACY_WEB_URL=https://votre-domaine-pharmacie/
```

En local : `http://localhost:8081` pour Flutter web/iOS simulateur ; `http://10.0.2.2:8081` pour l’émulateur Android (autoriser HTTP uniquement dans une configuration Android de développement). Utiliser HTTPS en production. L’app conserve le service Flutter existant sans URL configurée. Les deux entrées, service et recherche universelle, ouvrent la vue web quand l’URL est définie. Windows/Linux ouvrent le navigateur système.

Le workflow GitHub Pages exporte aussi Pharmacie sous `/I-ENTIER/pharmacy/` et configure l’app Flutter avec cette URL. L’exécution locale des changements ne les publie pas : la publication intervient au prochain lancement du workflow après livraison du code.

## Limites de validation

Les tests locaux couvrent les règles de panier et l’intégration Flutter. La connexion réelle, la création de commandes, le dépôt d’ordonnances et le sélecteur de fichiers sur appareil restent à vérifier avec un compte de test. Aucune commande réelle n’a été créée pendant le développement.

L’audit npm de l’arbre Expo 57 remonte 28 alertes transitives (10 modérées, 18 élevées), notamment dans l’outillage Metro/Expo et certaines dépendances de navigation. Les corrections proposées par `--force` incluent des changements majeurs incompatibles : elles ne sont pas appliquées automatiquement. Réexaminer ces dépendances avant une publication en production.

## Scan et transcription

L’icône à côté de la recherche ouvre `/scan` : caméra ou galerie, OCR français/anglais, comparaison avec la photo, correction puis confirmation. Le texte est conservé dans `ientier.prescriptions.transcription` avec l’original privé. Appliquer la migration du dossier `pharmacy/supabase/migrations` aux autres environnements ; elle a été appliquée au backend partagé pendant cette implémentation.

Le moteur Tesseract.js 6.0.1 fonctionne dans une iframe web ou une WebView mobile. Il réduit les grandes images à 2400 pixels, ajuste l’inclinaison et reconnaît le texte sans interpréter les médicaments ni modifier les dosages. Il télécharge le moteur WASM et les langues depuis les CDN au premier usage : une connexion reste nécessaire pour ces ressources et pour enregistrer. Aucun document n’est envoyé au CDN. La reconnaissance manuscrite est limitée ; cette fonction ne garantit pas la lecture d’une écriture médicale et ne valide aucune prescription.

Une nouvelle compilation native est nécessaire pour intégrer la permission caméra et WebView aux builds déjà installés. Les images JPEG, PNG et WebP jusqu’à 10 Mo sont acceptées. L’annulation arrête le moteur ; les erreurs et délais de lecture permettent de reprendre la photo ou de saisir le texte. Aucune clé OCR ni fonction serveur supplémentaire n’est requise.

## Catalogue, formes et dosages

`ientier.medicines` porte l’identité du médicament et son laboratoire. Chaque ligne de `medicine_variants` représente une combinaison valide **forme + dosage/concentration + conditionnement**. `pharmacy_products.variant_id` rattache le prix et le stock d’une pharmacie à cette présentation. La contrainte d’unicité empêche les doublons de présentation dans une pharmacie. Les anciens produits sans variante et les identifiants utilisés par le panier/les commandes restent compatibles.

Le client lit `v_public_medicine_products`, une vue `security_invoker` incluant aussi les présentations indisponibles. L’ancienne vue limitée aux produits en stock reste intacte. Les tables de référence ont RLS et une lecture réservée au catalogue publié pour les sessions authentifiées, y compris les invités utilisés par l’app ; les écritures de référence se font côté service. Le prix et le stock restent soumis aux autorisations pharmacie existantes. Lors d’un changement de présentation, le panier garde chaque référence séparément.

Migration appliquée au backend partagé : `20261008015118_medicine_variants_4c.sql`. Échantillon de quatre médicaments 4C, douze présentations. Sources officielles consultées le 7 octobre 2026 : [Analgine](https://laboratoires4c.com/fr/resultat-produit/?id=26), [Pediaphen](https://laboratoires4c.com/fr/resultat-produit/?id=91), [Flaxan](https://laboratoires4c.com/fr/resultat-produit/?id=86), [Paracétamol](https://laboratoires4c.com/fr/resultat-produit/?id=16). Les visuels viennent de ces fiches, présentent parfois plusieurs conditionnements, et sont conservés dans `assets/medicines/`.

Les prix renseignés sont des références du catalogue fabricant, à valider par la pharmacie ; les prix absents sont à zéro et affichés « Prix à confirmer ». Aucun stock réel n’étant fourni, les douze lignes sont à zéro et ne peuvent pas être commandées. Le statut `requires_prescription` reste une métadonnée historique, ignorée par les cartes et la validation des commandes. Les prix et stocks sont à vérifier avant mise en vente. Aucune posologie thérapeutique n’est copiée depuis les fiches fabricant.

Les favoris sont conservés localement par session utilisateur. Tests ajoutés pour les combinaisons forme/dosage, le regroupement par pharmacie et les lignes distinctes du panier. L’audit Supabase confirme RLS ; ses avis de lecture par invités sont intentionnels pour ces deux tables publiques de référence ([règle correspondante](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins)).

Les cartes placent le favori à droite du nom et la quantité à droite du prix. La migration `20261008021428_optional_pharmacy_order_prescription.sql` rend l’ordonnance facultative dans `place_pharmacy_order` ; les contrôles de session, de disponibilité et de propriété des documents éventuellement transmis par les autres clients restent conservés.

L’adaptation de `../i_entier_pharmacie` utilise la migration `20261008022058_pharmacy_management_medicine_variants.sql` : lecture du catalogue regroupé via `v_pharmacy_management_products`, enregistrement atomique via `save_pharmacy_catalog_product`, identité gérée par la pharmacie propriétaire et synchronisation des champs historiques. Les prix et stocks restent propres à chaque présentation. Le test transactionnel `supabase/tests/pharmacy_management_variants.sql` est annulé intégralement après ses assertions.
