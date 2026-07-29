# Financement solidaire

Le service de financement participatif médical est partagé par l’application
Patient et le portail Administration.

## Déploiement

Appliquer les migrations Supabase dans l’ordre, notamment :

```text
supabase/migrations/202607290002_add_crowdfunding.sql
```

La migration crée :

- les campagnes, contributions et revues administratives ;
- une table privée séparée pour le propriétaire et le téléphone de contact ;
- les politiques RLS pour le créateur, le public authentifié et les
  administrateurs ;
- les fonctions atomiques de soumission, revue, création d’une intention de
  contribution et confirmation d’un paiement ;
- les flux Realtime et l’entrée du catalogue de services.

Le schéma `ientier` doit rester exposé dans les API Settings de Supabase, comme
pour les autres modules.

## Parcours

1. Le patient envoie une campagne avec son consentement.
2. La campagne reste privée avec le statut `pending`.
3. Un administrateur vérifie le dossier puis l’approuve ou le refuse avec un
   motif.
4. Une campagne approuvée devient publique dans l’application.
5. Un soutien crée une contribution `pending_payment`.
6. Le paiement est rapproché avec une référence prestataire.
7. `confirm_crowdfunding_contribution` confirme une seule fois la contribution
   et met à jour atomiquement le total et le nombre de soutiens.

Une intention en attente n’est jamais affichée dans le total collecté.

## Prestataire de paiement

L’application propose les rails `moncash`, `card` et `bank_transfer`, mais elle
ne simule pas un débit. La fonction
`ientier.start_crowdfunding_contribution` crée une intention et renvoie sa
référence.

Pour automatiser la production :

1. créer une Edge Function Supabase côté serveur qui initialise le paiement
   chez le prestataire choisi ;
2. stocker les secrets uniquement dans les secrets de l’Edge Function ;
3. rediriger le patient vers l’URL de paiement renvoyée par le prestataire ;
4. traiter le webhook signé du prestataire ;
5. après validation de la signature du webhook, appeler avec la clé
   `service_role` :

```sql
select ientier.confirm_crowdfunding_contribution_webhook(
  p_contribution_id := '...',
  p_processor_reference := '...',
  p_amount := 2500,
  p_currency := 'HTG'
);
```

Cette fonction compare le montant et la devise à l’intention originale et
accepte sans double comptage la répétition du même webhook.

En attendant ce webhook, le portail Administration permet un rapprochement
manuel contrôlé. La référence est obligatoire et une contribution déjà traitée
ne peut pas être confirmée une seconde fois.
