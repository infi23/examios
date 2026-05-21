-- =============================================================
-- Exambro Smart System v2 - Migration 005
-- Tabel konfigurasi runtime untuk Server B (key-value sederhana).
-- Diubah lewat SQL/dashboard tanpa redeploy.
-- =============================================================

CREATE TABLE IF NOT EXISTS app_config (
    key        VARCHAR(64)  PRIMARY KEY,
    value      VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP    DEFAULT NOW()
);

-- Seed nilai awal force-update.
-- Naikkan min_supported_*_version untuk memblokir versi lama.
INSERT INTO app_config (key, value) VALUES
    ('min_supported_ios_version',     '1.0.0'),
    ('force_update_ios',              'true'),
    ('min_supported_android_version', '1.0.0'),
    ('force_update_android',          'true')
ON CONFLICT (key) DO NOTHING;
