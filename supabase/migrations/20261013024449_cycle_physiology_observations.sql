BEGIN;

-- Optional observations only: no diagnosis or ovulation status is persisted.
-- Existing entries, grants and owner policies are preserved.
ALTER TABLE ientier.cycle_entries
  ADD COLUMN basal_temperature_c numeric(4,2),
  ADD COLUMN temperature_disturbed boolean NOT NULL DEFAULT false,
  ADD COLUMN lh_test text NOT NULL DEFAULT '',
  ADD COLUMN cervical_mucus text NOT NULL DEFAULT '',
  ADD CONSTRAINT cycle_basal_temperature_range
    CHECK (basal_temperature_c BETWEEN 34 AND 42),
  ADD CONSTRAINT cycle_lh_test_value
    CHECK (lh_test IN ('', 'negative', 'positive')),
  ADD CONSTRAINT cycle_cervical_mucus_value
    CHECK (cervical_mucus IN ('', 'dry', 'sticky', 'creamy', 'watery', 'stretchy'));

NOTIFY pgrst, 'reload schema';
COMMIT;
