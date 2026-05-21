-- =============================================================
-- Exambro Smart System v2 - Migration 004
-- Tambah kolom student_status & capture_status ke student_data
-- =============================================================

ALTER TABLE student_data
    ADD COLUMN IF NOT EXISTS student_status VARCHAR(16) DEFAULT 'active'
        CHECK (student_status IN ('active', 'inactive'));

ALTER TABLE student_data
    ADD COLUMN IF NOT EXISTS capture_status VARCHAR(16) DEFAULT 'inactive'
        CHECK (capture_status IN ('active', 'inactive'));

CREATE INDEX IF NOT EXISTS idx_student_data_class ON student_data(student_class);
CREATE INDEX IF NOT EXISTS idx_student_data_status ON student_data(student_status);
