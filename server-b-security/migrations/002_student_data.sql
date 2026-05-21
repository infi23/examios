CREATE TABLE IF NOT EXISTS student_data (
    student_id VARCHAR(100) PRIMARY KEY,
    student_name VARCHAR(255) NOT NULL,
    student_class VARCHAR(100) NOT NULL,
    room_id VARCHAR(100) NOT NULL,
    image_url VARCHAR(500),
    exam_period VARCHAR(100),
    exam_session VARCHAR(100),
    exam_courses JSONB
);

-- DUMMY DATA UNTUK PENGUJIAN
INSERT INTO student_data (student_id, student_name, student_class, room_id, image_url, exam_period, exam_session, exam_courses) 
VALUES (
    'UNKNOWN', 
    'Siswa Simulasi', 
    'Kelas 12 IPA 1', 
    'Lab Komputer 1', 
    '', 
    'Ujian Akhir Semester 2026', 
    'Sesi 1', 
    '["Matematika", "Fisika"]'
) ON CONFLICT (student_id) DO NOTHING;
