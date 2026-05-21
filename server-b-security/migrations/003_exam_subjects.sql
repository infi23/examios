-- =============================================================
-- Exambro Smart System v2 - Migration 003
-- Tambah tabel exam_categories, exam_subjects, dan kolom exam_subject
-- =============================================================

-- Tabel kategori ujian (mis. UTS-2026-IPA, UAS-2026-IPS)
CREATE TABLE IF NOT EXISTS exam_categories (
    exam_id VARCHAR(64) PRIMARY KEY,
    exam_name VARCHAR(255) NOT NULL,
    exam_status VARCHAR(8) DEFAULT 'off' CHECK (exam_status IN ('on', 'off'))
);

-- Tabel mata pelajaran (sub-tes) per kategori ujian
CREATE TABLE IF NOT EXISTS exam_subjects (
    id BIGSERIAL PRIMARY KEY,
    exam_id VARCHAR(64) NOT NULL REFERENCES exam_categories(exam_id) ON DELETE CASCADE,
    exam_subject VARCHAR(255) NOT NULL,
    subject_status VARCHAR(8) DEFAULT 'off' CHECK (subject_status IN ('on', 'off')),
    UNIQUE (exam_id, exam_subject)
);

CREATE INDEX IF NOT EXISTS idx_exam_subjects_exam_id ON exam_subjects(exam_id);

-- Tambah kolom exam_subject ke exam_sessions (untuk track sub-tes per sesi)
ALTER TABLE exam_sessions
    ADD COLUMN IF NOT EXISTS exam_subject VARCHAR(255);

-- Tambah status 'warning_loss' yang dipakai heartbeat checker
-- (kolom status sudah ada, hanya pastikan tidak ada constraint terlalu ketat)
-- Status valid: ACTIVE, ENDED, warning_loss
