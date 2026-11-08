# États et transitions de Pharmacie

Cette carte couvre les deux routes de l’application Expo et les contrats du backend qu’elles utilisent. Pour modifier un parcours, partir du propriétaire de l’état indiqué dans la dernière colonne. Les chemins du client partent de `src/`. Les mutations de commande et de prescription décrites ici dépendent aussi du schéma I-ENTIER partagé.

## Session, navigation et données

| Parcours | Transitions et règle à préserver | Propriétaire |
| --- | --- | --- |
| Accès invité | Ouverture → restauration locale ou connexion anonyme → session prête. Un échec permet de réessayer. Les demandes simultanées partagent la même tentative. Un changement de patient invalide les opérations du précédent, même si ce patient se reconnecte ensuite. | [guestSession.ts](../src/guestSession.ts), [api.ts](../src/api.ts), [useGuestAccess.ts](../src/useGuestAccess.ts), [app/_layout.tsx](../src/app/_layout.tsx) |
| Activité de l’app | Passage au premier plan → reprise du renouvellement du jeton. Passage en arrière-plan → arrêt. Un renouvellement pour le même utilisateur conserve son panier et ses brouillons. | [useGuestAccess.ts](../src/useGuestAccess.ts) |
| Navigation | L’URL choisit l’onglet, puis le panier ou l’historique. L’ancien onglet `Commandes` ouvre toujours l’historique. Le scan ouvre une route distincte. Fermer revient à la navigation précédente, enregistrer ouvre les ordonnances. | [app/index.tsx](../src/app/index.tsx), [app/scan.tsx](../src/app/scan.tsx) |
| Catalogue et pharmacies | Premier chargement → données ou erreur → actualisation. Une actualisation conserve les cartes déjà chargées. Une réponse vide réussie autorise l’état vide. Une erreur de notes laisse le catalogue utilisable. | [usePharmacyCatalog.ts](../src/usePharmacyCatalog.ts) |
| Dossier patient | Session → préparation du profil → prêt. Une lecture ou une soumission peut retenter la préparation. Seul l’onglet privé visible charge sa collection. Focus, changement de collection et nouvelle tentative déclenchent une lecture. Un dépôt achevé pendant la lecture garde sa place dans la liste. | [usePatientFile.ts](../src/usePatientFile.ts) |
| Favoris médicaments et pharmacies | Pour chaque patient et chaque liste, lecture locale → commandes actives → lecture/modification/écriture en série. Une lecture échouée ne réécrit pas la liste. Un nouvel appui retente la lecture. Les médicaments conservent les anciennes clés par pharmacie. | [favoriteStorage.ts](../src/favoriteStorage.ts), [useStoredFavorites.ts](../src/useStoredFavorites.ts), [catalog.ts](../src/catalog.ts) |
| Recherche et filtres | Texte, catégorie, pharmacie choisie et mode toutes/proches/favorites déterminent les résultats. Ouvrir le catalogue d’une pharmacie sélectionne son identifiant et réinitialise texte et catégorie. | [app/index.tsx](../src/app/index.tsx), [catalog.ts](../src/catalog.ts) |
| Proximité | Demande de permission → acquisition → coordonnées et tri. Refus, erreur ou délai de 15 s pendant l’acquisition permettent de réessayer. Choisir un autre filtre invalide la demande en cours. | [app/index.tsx](../src/app/index.tsx) (`locate`, `selectPharmacies`), [pharmacies.ts](../src/pharmacies.ts) |
| Actions et messages | Une action de dépôt, consultation, appel, itinéraire ou commande en cours empêche un double déclenchement. Le nom de l’opération détermine son indicateur. La navigation efface le message de l’onglet. | [app/index.tsx](../src/app/index.tsx) (`run`, `setTab`) |

## Médicaments et pharmacies

| Parcours | Transitions et règle à préserver | Propriétaire |
| --- | --- | --- |
| Publication et disponibilité | Le backend filtre la publication des références et l’activité des pharmacies. Parmi les produits reçus, un stock positif et un prix positif rendent l’offre commandable. Les prix et quantités appartiennent à la présentation vendue par cette pharmacie. | Vue `v_public_medicine_products`, [catalog.ts](../src/catalog.ts) |
| Références historiques | Un produit ancien peut être rattaché à une présentation du catalogue partagé. Une présentation déjà rattachée reste fixe. Une pharmacie ne peut pas créer un doublon de cette présentation. | RPC `save_pharmacy_catalog_product`, migration `20261008034400_pharmacy_legacy_catalog_link.sql` |
| Présentation et vendeur | Sélection automatique → choix explicite de forme, dosage, conditionnement ou vendeur. Si une offre disparaît, la carte recherche la même présentation parmi les vendeurs disponibles. Une ligne du panier reste liée à son produit exact. | [catalog.ts](../src/catalog.ts), [MedicineCard](../src/components/MedicineCard.tsx), [MedicineFormatPicker](../src/components/MedicineFormatPicker.tsx), [PharmacyOffersModal](../src/components/PharmacyOffersModal.tsx) |
| Fenêtres d’une carte | Fermée → choix du format, choix du vendeur ou mesure de la photo → fiche. Une mesure tardive ne peut ouvrir la fiche après un autre choix. La disparition des options ferme le sélecteur. | [medicineOverlay.ts](../src/medicineOverlay.ts), [MedicineCard](../src/components/MedicineCard.tsx) |
| Fiche médicament | Mesure → ouverture → consultation → fermeture. La préférence de mouvement réduit adapte l’animation. La fiche mémorise sa section détails/pharmacies et le résultat d’une modification du panier. | [MedicineDetails](../src/components/MedicineDetails.tsx) |
| Note d’une pharmacie | Résumé reçu → éditeur initialisé avec la note du patient → choix de 1 à 5 → enregistrement. Un échec garde le choix pour réessayer. Le succès recharge la moyenne. Une ancienne lecture de notes ne remplace pas une lecture plus récente de la même pharmacie. | [PharmacyCard](../src/components/PharmacyCard.tsx), [usePharmacyCatalog.ts](../src/usePharmacyCatalog.ts), RPC `pharmacy_rating_summaries` |
| Photos et mouvement | Source locale ou distante → image ou visuel de secours en cas d’échec de cette source. Entrée des cartes, pression/relâchement et sélection animent les éléments concernés selon les préférences de mouvement. | [ProductPhoto](../src/components/ProductPhoto.tsx), [PharmacyCard](../src/components/PharmacyCard.tsx), [Motion](../src/components/Motion.tsx) |
| Téléphone et itinéraire | Coordonnée disponible → action accessible → ouverture par le système ou erreur. | [PharmacyCard](../src/components/PharmacyCard.tsx), [app/index.tsx](../src/app/index.tsx) |

## Panier et commandes

| Parcours | Transitions et règle à préserver | Propriétaire |
| --- | --- | --- |
| Panier | Vide → première ligne d’une pharmacie → ajustement ou retrait → vide. Une baisse de stock peut rendre une ligne invalide et le patient peut toujours en réduire la quantité. Si un produit disparaît du catalogue, le patient peut retirer les références manquantes avant de commander. | [cart.ts](../src/cart.ts), [app/index.tsx](../src/app/index.tsx) |
| Envoi | Validation locale et profil prêt → RPC en cours → confirmation, refus ou réponse incertaine. Seule une confirmation vide le panier. Une perte de réponse invite à consulter les commandes avant de réessayer. Le RPC ne prend pas de clé d’idempotence. | `orderLines`, [app/index.tsx](../src/app/index.tsx), RPC `place_pharmacy_order` |
| Traitement de la commande | `pending` → `accepted` → `preparing` → `ready` → `completed`. Le serveur permet `cancelled` depuis les trois premiers états. L’historique affiche le statut reçu, y compris un statut inconnu. | RPC `update_pharmacy_order_status` du backend partagé, [Overview.OrderProgress](../src/components/Overview.tsx) |

## Ordonnances

| Parcours | Transitions et règle à préserver | Propriétaire |
| --- | --- | --- |
| Photo du scan | Brouillon vide ou existant → sélection caméra/galerie → annulation, erreur ou nouvelle image. Android peut restituer une sélection interrompue. Sur le web, rouvrir le sélecteur rend l’ancienne réponse caduque. | [scanWorkflow.ts](../src/scanWorkflow.ts), [app/scan.tsx](../src/app/scan.tsx) |
| Reconnaissance | Image validée → démarrage du moteur → progression → texte, résultat vide ou erreur. Annulation, délai de 120 s et nouvelle lecture invalident les anciens événements. Le moteur s’exécute dans une iframe web ou une WebView native. | [scanWorkflow.ts](../src/scanWorkflow.ts), [prescriptionScan.ts](../src/prescriptionScan.ts), [ocr/](../src/ocr) |
| Correction et confirmation | Résultat → correction → confirmation d’un texte non vide → photo privée → ligne de prescription → dossier. Une relecture vide ou un échec d’enregistrement préserve les corrections. Une nouvelle tentative réutilise l’identifiant de la photo. Si la ligne existe déjà, la confirmation vérifie que le texte enregistré correspond au brouillon. | [scanWorkflow.ts](../src/scanWorkflow.ts), [app/scan.tsx](../src/app/scan.tsx) |
| Dépôt direct | Choix de fichier → annulation ou lecture → contrôle de taille → profil → stockage → insertion → mise à jour de la liste. L’objet et la ligne sont deux écritures distinctes. Une réponse perdue peut laisser le résultat du dépôt incertain. | [app/index.tsx](../src/app/index.tsx) (`upload`), [usePatientFile.ts](../src/usePatientFile.ts) |
| Consultation | Seules les ordonnances du patient dont le statut est `available` sont listées. Pour ouvrir un document, la demande génère un lien signé de 60 s puis le transmet au système. Expiration, révocation et dispensation sont gérées par le backend partagé. | [usePatientFile.ts](../src/usePatientFile.ts), [app/index.tsx](../src/app/index.tsx) |

Les tests de transition se trouvent dans `src/*.test.ts`. Pour une opération asynchrone, couvrir aussi le cas où le résultat arrive **après** l’annulation, une autre sélection ou un changement de patient. Un état déduit du stock, du prix ou de l’URL peut être vérifié directement à partir de ces données.
