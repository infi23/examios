-- =============================================================
-- Exambro Smart System v2 - Initial Database Schema
-- =============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Tabel device fingerprint
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_hash VARCHAR(64) UNIQUE NOT NULL,
    android_id VARCHAR(64),
    device_model VARCHAR(128),
    manufacturer VARCHAR(128),
    screen_resolution VARCHAR(32),
    app_signature VARCHAR(128),
    first_seen TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP DEFAULT NOW()
);

-- Tabel sesi ujian
CREATE TABLE IF NOT EXISTS exam_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id),
    student_id VARCHAR(64) NOT NULL,
    exam_id VARCHAR(64) NOT NULL,
    moodle_session_id VARCHAR(128),
    started_at TIMESTAMP DEFAULT NOW(),
    ended_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'ACTIVE'
);

-- Tabel event keamanan
CREATE TABLE IF NOT EXISTS security_events (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID REFERENCES exam_sessions(id),
    event_type VARCHAR(50) NOT NULL,
    event_weight INT NOT NULL,
    duration_seconds INT DEFAULT 0,
    frequency INT DEFAULT 1,
    screenshot_path VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabel risk score (aggregate per sesi)
CREATE TABLE IF NOT EXISTS risk_scores (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID REFERENCES exam_sessions(id) UNIQUE,
    total_score INT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'SAFE',
    last_calculated TIMESTAMP DEFAULT NOW()
);

-- Indexes untuk performa query
CREATE INDEX IF NOT EXISTS idx_events_session ON security_events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_sessions_student ON exam_sessions(student_id);
CREATE INDEX IF NOT EXISTS idx_sessions_exam ON exam_sessions(exam_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON exam_sessions(status);
