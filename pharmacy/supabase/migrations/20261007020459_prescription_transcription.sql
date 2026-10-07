ALTER TABLE ientier.prescriptions
  ADD COLUMN IF NOT EXISTS transcription text NOT NULL DEFAULT ''
  CHECK (length(transcription) <= 20000);
COMMENT ON COLUMN ientier.prescriptions.transcription IS 'Patient-reviewed OCR text; not a validated medical prescription.';
