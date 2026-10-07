-- Repérage complémentaire de sigles dans les noms source.
UPDATE ientier.health_facilities
SET name_review_required = true
WHERE source_sha256 = 'f3b795f2b4675cee84c904946b2fe6e90b91648eb0ee6cdaa9a09e18627415bd'
  AND source_row IN (41, 342, 345, 404, 465, 468, 568, 674, 702, 706,
                     709, 870, 969, 977, 985)
  AND name_review_required = false;
