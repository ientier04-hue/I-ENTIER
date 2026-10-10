# Appels vidéo — Patient et Professionnel

## Fonctionnement livré

L’icône caméra de l’en-tête Patient et de l’en-tête mobile Professionnel ouvre
une page indépendante **Appels vidéo**. Sur ordinateur, le portail Professionnel
propose aussi cette entrée dans sa barre latérale. La page contient les
rendez-vous vidéo confirmés et les 100 derniers appels.

Les deux titulaires d’un rendez-vous peuvent appeler, entre 30 minutes avant et
4 heures après l’horaire prévu. Le prestataire doit rester approuvé. Le serveur
déduit les identités du rendez-vous : aucun identifiant d’interlocuteur ni nom
de salle libre n’est accepté depuis le client. Une personne ne peut participer
qu’à un seul appel actif. Les appels croisés sur le même rendez-vous réutilisent
l’invitation existante.

L’invitation expire après 60 secondes. Le destinataire peut accepter ou refuser,
y compris depuis une autre page de l’application. La vidéo utilise LiveKit
2.13.1, une salle limitée à deux participants, une caméra 360p/24 images par
seconde, un plafond vidéo de 500 kbit/s et l’adaptation réseau. Micro, caméra,
raccrochage, changement de caméra et haut-parleur mobile sont intégrés.
Les appareils libèrent leur caméra et leur microphone en quittant l’écran.

Les métadonnées sont dans `ientier.video_calls`, protégées par RLS et accessibles
uniquement aux deux participants disposant de comptes permanents. Les sessions
anonymes sont exclues par une politique restrictive et par le serveur. Seule
l’Edge Function peut changer l’état.
Les jetons LiveKit durent deux minutes pour la connexion, n’autorisent que la
salle concernée et la publication caméra/micro. Ils restent uniquement en
mémoire. Le transport WebRTC est chiffré ; cette version n’active pas E2EE.
Aucun enregistrement n’est lancé.

Une présence est envoyée toutes les 20 secondes. Une absence de 90 secondes ou
une durée totale de deux heures termine la session. Le client coupe aussi les
médias s’il ne parvient plus à renouveler sa présence. Le nettoyage planifié
ci-dessous ferme les salles abandonnées, même après la fermeture des applications.

## Configuration déployée

Projet : `dktjnxbtyhxvapyheosh` (**ientier**). L’accès direct par le connecteur
est confirmé, même si la liste des projets ne montre que le projet DRH. Toujours
cibler explicitement cette référence pour les appels vidéo.

1. Les migrations `20261010175340_add_video_calls.sql`,
   `20261010175704_restrict_video_calls_to_permanent_users.sql` et
   `20261010181301_schedule_video_call_cleanup.sql` sont déjà appliquées
   sur ce projet. Ne pas les rejouer. La table, les transitions réservées au
   serveur, les politiques RLS et Realtime sont vérifiés. Les trois fonctions
   sont également déployées.
2. Le projet LiveKit **i-ENTIER Vidéo** (`p_1wxxku1hhqz`) est créé, avec
   l’observabilité des agents désactivée. Son URL est
   `wss://project-i-entier-video-44yr4r3r.livekit.cloud`. La clé de service
   **i-ENTIER Supabase video calls** est créée. Les quatre variables sont
   enregistrées dans `.env.video-calls`, ignoré par Git, avec permissions `0600`.
   Le secret de nettoyage possède 256 bits aléatoires.
3. Les quatre secrets sont enregistrés dans les Edge Functions de Supabase.
   Pour les renouveler, utiliser **Edge Functions → Secrets** avec le compte
   propriétaire ou administrateur, ou une CLI authentifiée :

   ```sh
   supabase secrets set --project-ref dktjnxbtyhxvapyheosh --env-file .env.video-calls
   ```

   Leur redéploiement n’est pas nécessaire pour un changement de secrets.
   En cas de renouvellement du secret de nettoyage, actualiser aussi l’entrée
   correspondante dans Vault.

   `verify_jwt = false` est volontaire dans `config.toml` : `video-call` vérifie
   explicitement la session avec `auth.getUser`, le webhook vérifie la signature
   LiveKit, et le nettoyage vérifie un secret privé. Ne jamais ajouter de clé
   `service_role`, de secret LiveKit ou de secret de nettoyage dans Flutter.
4. Le webhook LiveKit **i-ENTIER appels vidéo** est enregistré à l’adresse
   `https://dktjnxbtyhxvapyheosh.supabase.co/functions/v1/livekit-webhook`, signé
   avec la clé de service ci-dessus. L’événement `room_finished` termine les
   appels restants. Les requêtes signées sont acceptées ; les signatures
   manquantes et les corps modifiés sont refusés.
5. Les extensions `pg_cron` et `pg_net` et le job
   `ientier-video-call-cleanup` sont installés. Le job appelle le nettoyage
   chaque minute avec le secret `ientier_video_call_cleanup_secret` de Vault,
   correspondant au fichier local. Aucun secret ne figure dans la migration
   ou dans le texte du job. Le job est actif ; contrôler ses exécutions dans
   `cron.job_run_details` et les réponses HTTP dans `net._http_response`.
6. Les builds web et Android de débogage ont été validés localement pour les
   deux applications. Leur publication reste distincte. Aucun paramètre LiveKit n’est
   nécessaire au build : l’URL et le jeton sont remis par le backend authentifié.

## Vérification avec deux comptes

Créer un rendez-vous en mode vidéo, le confirmer côté Professionnel et utiliser
un horaire dans la fenêtre d’appel. Ouvrir Patient et Professionnel dans deux
profils de navigateur différents ou sur deux appareils. Autoriser caméra et
micro sur HTTPS (ou localhost).

Tester : invitation dans chaque sens, refus, appel sans réponse, caméra coupée,
micro coupé, passage Wi-Fi/données mobiles, raccrochage, sortie arrière, double
clic sur Appeler, tentative d’un troisième compte et fermeture forcée d’une
application. Vérifier que la salle disparaît après le nettoyage. Faire aussi un
essai Android/iOS réel : les builds et tests locaux ne valident pas à eux seuls
la capture sur appareil ni la connectivité TURN du projet Cloud.

## Limites de cette version

Les invitations sont reçues tant que l’application est ouverte et connectée.
La sonnerie lorsque l’application est tuée, les appels natifs sur écran verrouillé
et la réception garantie en arrière-plan demandent une intégration push
FCM/APNs et CallKit/ConnectionService, non incluse dans cette version.
Le mode audio iOS en arrière-plan est déclaré pour un appel déjà établi.
Le comportement en arrière-plan doit être vérifié sur appareils ; le maintien
d’un appel Android en arrière-plan n’est pas garanti sans service natif dédié.

La configuration serveur est active sur Supabase i-ENTIER et LiveKit. Les
secrets restent côté serveur et dans le fichier local privé. Un essai média a été réalisé dans deux fenêtres Safari sur le même Mac ;
un appel entre deux appareils physiques reste à vérifier.

## Maintenance et tests

Les deux dépôts sont construits séparément. `lib/video_calls` est maintenu dans
Patient puis recopié à l’identique dans Professionnel :

```sh
python3 tools/sync_video_calls.py
python3 tools/sync_video_calls.py --check
flutter analyze
flutter test
npx --yes deno task --config supabase/functions/deno.json check
npx --yes deno task --config supabase/functions/deno.json test
python3 tools/test_video_calls_database.py
```

Le test SQL utilise un conteneur PostgreSQL 17 éphémère, sans port exposé, et
ne contacte jamais Supabase Cloud. Il vérifie RLS, refus des écritures client,
appel croisé, accès d’un tiers, limite de fréquence, expiration et transitions.
Le fichier de verrouillage Deno épingle également les dépendances transitives.

## État vérifié après déploiement

L’accès direct au projet i-ENTIER fonctionne malgré son absence dans
`list_projects`. `video-call` et `video-call-cleanup` renvoient HTTP 401 sans
authentification. Le nettoyage renvoie HTTP 200 avec son secret privé.
`livekit-webhook` accepte un événement signé avec HTTP 200 et refuse une
signature absente ou un corps altéré avec HTTP 401. Les clients peuvent lire
leurs appels via RLS, mais ne peuvent ni écrire dans la table ni exécuter la
commande serveur.

La clé LiveKit a été vérifiée par la création puis la suppression d’une salle
temporaire vide avec `maxParticipants = 2`. Aucun appel média entre deux
appareils n’a encore été testé. Le job Cron est actif chaque minute et utilise
le même secret privé que l’Edge Function. Son exécution du 10 octobre 2026 à
14 h 25 (America/Port-au-Prince) est confirmée `succeeded`, avec une réponse
HTTP 200, sans délai dépassé ni erreur réseau.

Le conseiller Supabase conserve un avertissement générique sur les sessions
anonymes pour la politique permissive de lecture. La politique restrictive
`video_calls_permanent_accounts` s’ajoute à cette politique : le test SQL vérifie
qu’une session anonyme, même avec l’identité d’un participant, ne voit aucun appel.
Voir [le contrôle Supabase](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins)
et [les politiques restrictives recommandées](https://supabase.com/docs/guides/auth/auth-anonymous#access-control).
Les autres avertissements de sécurité préexistaient à cette fonctionnalité.
L’activation de Cron ajoute deux avertissements génériques sur ses politiques
internes. Les rôles `anon` et `authenticated` n’ont pas l’accès au schéma `cron`
ni à Vault ; aucun secret n’est exposé à l’application.

## Essai réel du 10 octobre 2026

Les composants Flutter de production ont été exécutés dans deux sessions Safari
sur deux origines locales distinctes, avec trois comptes temporaires et un
rendez-vous de test sur le backend déployé. Invitation dans les deux sens,
réception hors de la page des appels, refus, acceptation, jetons distincts,
présence et raccrochage ont été vérifiés. Le troisième compte reçoit HTTP 403
et ne peut pas lire l’appel via RLS.

La vidéo distante a été observée dans les deux sens, successivement avec la
caméra physique partagée du Mac. Les commandes micro/caméra et l’activation
audio Safari ont répondu. La qualité sonore perçue et deux appareils physiques
ne sont pas validés par cet essai. Un premier essai a nécessité une reconnexion,
puis a expiré avec une session en onglet de fond ; le second, en fenêtres
visibles, a tenu plus de quatre minutes jusqu’au raccrochage volontaire.

La fermeture serveur des quatre appels de test est confirmée, sans salle
LiveKit restante. Comptes Auth, profils et rendez-vous temporaires supprimés.
Le message de déconnexion média est désormais effacé lorsqu’une fin normale
est reçue du serveur, pour éviter une fausse erreur au raccrochage distant.
