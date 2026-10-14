# Coffre médical du patient — protocole v1

## Périmètre

Le dossier médical, les pièces des ordonnances, les notes privées des rendez-vous et les documents des consultations sont chiffrés sur l’appareil avant écriture. Les dossiers d’assurance et de Crédit Santé restent dans leurs circuits actuels, conformément au choix du produit. L’identité du compte, les prestataires, les horaires, les lieux des rendez-vous, les paiements et les commandes sont des métadonnées opérationnelles hors coffre. Une référence d’ordonnance utilisée par une commande ne contient ni médicament, ni pièce jointe, ni transcription.

## Clés et carte

`lib/privacy/vault_crypto.dart` utilise AES-GCM-256 du paquet `cryptography`, une clé aléatoire de 32 octets, un nonce aléatoire de 12 octets par chiffrement et un tag de 16 octets. Les données associées lient les enveloppes à leur patient, coffre, collection ou autorisation et document. Le serveur reçoit `{v,n,c,t}`, jamais la clé ni le code de carte.

La carte PDF est produite localement, sans service QR ni police distante, au format 85,60 × 53,98 mm. Elle porte `IEV1.<patient base64url>.<coffre UUID>.<clé base64url>`, également encodé en QR. L’activation demande de télécharger la carte puis d’en recopier les six derniers caractères. Pour un nouvel appareil, le patient se connecte à son compte et entre le code complet de cette carte.

Sur Android/iOS, une copie de la clé reste dans le stockage sécurisé de l’appareil. iOS utilise un élément Keychain `unlocked_this_device`; Android exclut les préférences des sauvegardes cloud et du transfert de téléphone. Sur le Web, la clé reste en mémoire par défaut. L’option « Mémoriser sur cet appareil », décochée initialement, conserve une copie chiffrée de la carte dans IndexedDB pour ce patient. Le chiffrement local utilise AES-GCM-256, un nonce aléatoire de 12 octets, des données associées liées au patient et une clé Web Crypto non exportable, enregistrée dans la même base du navigateur. Aucun secret de carte n’est placé dans localStorage/sessionStorage ni transmis au serveur. Après rechargement ou reconnexion du même compte, le client vérifie à nouveau la carte mémorisée contre le coffre avant de l’ouvrir. Cette copie locale reste présente après déconnexion, comme le stockage sécurisé natif; elle s’efface en désactivant l’option dans « Mon coffre » ou en supprimant les données du site. La session actuellement ouverte reste utilisable après avoir désactivé l’option. Un autre compte ne peut pas utiliser cette carte. La déconnexion efface la clé en mémoire. Le compte Supabase reste nécessaire en plus de la carte. La carte téléchargée est elle-même un secret : une copie faite par le patient reste sous son contrôle. Le navigateur ne garantit pas un stockage matériel : un script malveillant de la même origine, une extension privilégiée ou un navigateur/OS compromis peut utiliser les clés locales. La mémorisation est donc un choix pour un appareil personnel. Référence : [sérialisation des CryptoKey et IndexedDB](https://www.w3.org/TR/webcrypto/).

Il n’existe ni clé détenue par l’administration, ni réinitialisation du coffre, ni accès d’urgence. Réinitialiser le mot de passe du compte ne recrée pas la clé médicale. Perdre la carte et tous les appareils qui la conservent rend les données irrécupérables. Ne pas ajouter de journalisation des requêtes contenant des codes, ni d’analytics sur les champs de saisie ou le PDF.

## Autorisations temporaires

Le patient choisit un rendez-vous, les catégories à partager et une durée (15 min, 30 min, 1 h, 2 h ou 24 h). L’application chiffre un instantané des catégories sélectionnées avec une nouvelle clé indépendante. Le code `IEA1.<autorisation UUID>.<clé base64url>` est transmis directement au professionnel choisi. La carte privée n’est pas partagée.

Le professionnel doit être authentifié sous le compte désigné et avoir un profil approuvé. La base contrôle ces conditions, la révocation et l’expiration à chaque lecture et publication. Les sondes de validité renvoient uniquement des métadonnées. Le client vérifie toutes les 10 secondes (timeout de 8 secondes), se ferme si la vérification échoue et applique un minuteur fondé sur l’heure du serveur. Le passage en arrière-plan et la déconnexion ferment également l’accès. Les documents/modalités cliniques sont retirés de l’écran et les images sont évincées du cache à sa fermeture.

Les images et PDF autorisés sont rendus localement. Le client Web professionnel embarque PDF.js 6.4.299, avec les polices et modules associés, et désactive `isEvalSupported`; il remplace le chargement distant par défaut du plugin Printing. Sources de maintenance : [version officielle](https://github.com/mozilla/pdf.js/releases/tag/v6.4.299) et [avis de sécurité du moteur ancien](https://github.com/mozilla/pdf.js/security/advisories/GHSA-wgrm-67xf-hhpq).

Les nouveaux documents sont chiffrés avec la clé temporaire. Une copie de cette clé, chiffrée avec la clé du patient, permet au patient de les importer même après l’expiration ou la révocation. Les nouvelles ordonnances et demandes d’examens sont intégrées dans leurs collections chiffrées. Les publications sont idempotentes pour un même identifiant et une même enveloppe. Les écritures concurrentes du coffre utilisent des révisions optimistes : un conflit est refusé, pas écrasé silencieusement.

La révocation interdit les nouvelles opérations sur le serveur immédiatement après validation de la transaction. L’écran professionnel se ferme au prochain contrôle (au plus environ 18 secondes avec le délai réseau configuré). Elle ne peut pas effacer une capture d’écran, une photo, une copie ou une clé déjà conservée par un destinataire. Un navigateur ou un appareil compromis, ou une version malveillante du client distribuée par un serveur compromis, sort également de cette garantie.

## Migration et mise en service

Fichier : `supabase/migrations/20261014070107_patient_e2ee_vault.sql`.

La migration SQL crée les tables, politiques et RPC. Elle accepte l’absence du module de médecine traditionnelle en exportant ses collections vides. Si ce module est ajouté plus tard, ses protections `vault_no_plaintext`, `vault_legacy_owner_only` et `vault_no_permanent_sharing` doivent être installées dans la même transaction avant de le rendre accessible. Elle ne génère aucune clé pour les patients. Chaque dossier existant est converti lorsque son patient active son coffre avec la nouvelle application :

1. Export authentifié du dossier et empreinte de comparaison.
2. Chiffrement et vérification locale de chaque collection, téléchargement local des anciennes pièces.
3. Comparaison sous verrous dans une transaction. Si les données ont changé, annulation sans purge.
4. Enregistrement des enveloppes, suppression du contenu médical des anciennes tables, conservation des seules références opérationnelles, révocation des anciens partages permanents.
5. Relecture des pièces chiffrées puis suppression des anciens objets Storage. Un échec de suppression est retenté à l’ouverture suivante; il ne provoque ni une perte du coffre ni une nouvelle demande de clé.

Les anciennes copies de sauvegarde PostgreSQL/Storage, exports, caches ou journaux déjà créés ne sont pas réécrits par cette opération. Leur purge et leur durée de rétention doivent être traitées avec l’hébergeur selon la politique de conservation retenue. Les dossiers de patients n’ayant pas encore activé leur coffre restent dans l’ancien format; les nouveaux clients n’utilisent aucun repli vers des écritures médicales en clair.

Préparer ensemble la migration de la base et les nouvelles versions **patient et professionnel**. Les anciennes versions professionnelles ne peuvent plus écrire de contenu médical pour un coffre activé. Vérifier en environnement de recette l’activation d’un dossier contenant des données et pièces, la reconnexion sur un second appareil avec la carte, l’autorisation et la révocation, puis les parcours pharmacie/assurance/Crédit Santé avant la publication des clients. Le code et les tests locaux ne constituent pas un déploiement du service en ligne.

Limites actuelles : une enveloppe est limitée à 32 Mio côté SQL; les pièces sont regroupées dans la collection `files` et les catégories partagées dans un même instantané. Un dépassement est refusé sans purge de l’ancien dossier. Les listes d’autorisations sont limitées aux 100 entrées récentes. Un contrôle de sécurité indépendant est recommandé avant d’utiliser ce nouveau protocole avec des dossiers réels.

## Vérification locale

- `flutter analyze` puis `flutter test` dans chaque application.
- `python3 tools/test_vault_database.py` dans l’application patient : PostgreSQL 17 Docker jetable, sans réseau ni données de production. Applique les migrations réelles du dossier, de l’authentification, de la pharmacie et des consultations avant le coffre; teste l’activation atomique, la purge, l’isolation patient/admin/professionnel, le refus du clair, les conflits, les références pharmacie, les rendez-vous de suivi, l’expiration et la révocation.
- `python3 tools/test_vault_database.py --without-traditional` vérifie la même suite sur un schéma sans le module traditionnel, comme la production au moment du déploiement.
- `test/vault_workflow_test.dart` : carte, activation, catégories exclues du partage, absence de secrets dans les requêtes, écritures concurrentes et import idempotent après révocation.

## Déploiement du 14 octobre 2026

La migration `20261014070107_patient_e2ee_vault` a été appliquée au projet Supabase `dktjnxbtyhxvapyheosh`. Le schéma distant ne contient pas les tables optionnelles de médecine traditionnelle. Les cinq tables du coffre ont RLS actif, aucune lecture pour le rôle `anon` et aucune écriture directe pour le rôle `authenticated`; les RPC du coffre sont inaccessibles au rôle `anon`. Vingt-cinq tables cliniques existantes ont un garde contre les écritures en clair après activation.

Les clients sont publiés par les workflows GitHub Pages des dépôts [Patient](https://github.com/ientier04-hue/I-ENTIER/actions/workflows/deploy-web.yml) et [Professionnel](https://github.com/louvenslouis/i_entier_professionnel/actions/workflows/deploy-pages.yml). Les URL de production sont [Patient](https://ientier04-hue.github.io/I-ENTIER/) et [Professionnel](https://louvenslouis.github.io/i_entier_professionnel/). La publication concerne les versions Web; les APK de vérification locaux sont des builds de développement.

## Mémorisation locale du 14 octobre 2026

Le correctif patient ajoute le choix de mémoriser l’appareil au déverrouillage Web et dans « Mon coffre ». Aucune migration SQL ni modification du client professionnel n’est nécessaire. Les tests couvrent la réouverture sans ressaisie, le renouvellement du jeton, l’oubli de l’appareil, le stockage indisponible et les erreurs de nettoyage des anciennes pièces. `flutter test --platform chrome test/vault_device_store_web_test.dart` vérifie dans Chrome le stockage chiffré, l’impossibilité d’exporter la clé locale, la séparation des comptes et la suppression.
