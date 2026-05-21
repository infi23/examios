-- =============================================================
-- Exambro Smart System v2 - Migration 006
-- Distribusi APK Android self-hosted (offline-first).
-- Server B menyediakan metadata APK; file fisik di MinIO bucket publik.
-- =============================================================

INSERT INTO app_config (key, value) VALUES
    -- URL lengkap ke file APK. Bisa di-host di MinIO publik, nginx static,
    -- atau S3. Android akan download dari URL ini.
    ('latest_apk_url',          ''),
    -- Versi semver dari APK yang di-host. Naikkan saat upload APK baru.
    ('latest_apk_version',      ''),
    -- Ukuran file dalam bytes (opsional, untuk progress bar).
    ('latest_apk_size_bytes',   '0'),
    -- SHA-256 file APK (opsional, untuk verifikasi integritas pasca-download).
    ('latest_apk_sha256',       '')
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE app_config IS 'Runtime config Server B. Force-update, APK distribution, dll. Dibaca oleh AppConfigRepo dengan cache TTL 60 detik.';
