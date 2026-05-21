package repository

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/exambro/server-b-security/internal/model"
)

// DeviceRepository handles device fingerprint persistence.
type DeviceRepository struct {
	db *sql.DB
}

func NewDeviceRepository(db *sql.DB) *DeviceRepository {
	return &DeviceRepository{db: db}
}

func (r *DeviceRepository) Upsert(d *model.RegisterDeviceRequest) (*model.Device, error) {
	var device model.Device
	err := r.db.QueryRow(`
		INSERT INTO devices (fingerprint_hash, android_id, device_model, manufacturer, screen_resolution, app_signature)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (fingerprint_hash) DO UPDATE SET
			last_seen = NOW(),
			android_id = EXCLUDED.android_id,
			device_model = EXCLUDED.device_model
		RETURNING id, fingerprint_hash, android_id, device_model, manufacturer, screen_resolution, app_signature, first_seen, last_seen
	`, d.FingerprintHash, d.AndroidID, d.DeviceModel, d.Manufacturer, d.ScreenResolution, d.AppSignature).
		Scan(&device.ID, &device.FingerprintHash, &device.AndroidID, &device.DeviceModel,
			&device.Manufacturer, &device.ScreenResolution, &device.AppSignature,
			&device.FirstSeen, &device.LastSeen)
	return &device, err
}

func (r *DeviceRepository) FindByFingerprint(hash string) (*model.Device, error) {
	var device model.Device
	err := r.db.QueryRow(`SELECT id, fingerprint_hash, android_id, device_model, manufacturer, screen_resolution, app_signature, first_seen, last_seen FROM devices WHERE fingerprint_hash = $1`, hash).
		Scan(&device.ID, &device.FingerprintHash, &device.AndroidID, &device.DeviceModel,
			&device.Manufacturer, &device.ScreenResolution, &device.AppSignature,
			&device.FirstSeen, &device.LastSeen)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &device, err
}

// SessionRepository handles exam session persistence.
type SessionRepository struct {
	db *sql.DB
}

func NewSessionRepository(db *sql.DB) *SessionRepository {
	return &SessionRepository{db: db}
}

func (r *SessionRepository) Create(req *model.StartSessionRequest, examID string) (*model.ExamSession, error) {
	var session model.ExamSession
	err := r.db.QueryRow(`
		INSERT INTO exam_sessions (device_id, student_id, exam_id, moodle_session_id, status, last_heartbeat)
		VALUES ($1, $2, $3, $4, 'active', NOW())
		RETURNING id, device_id, student_id, exam_id, COALESCE(exam_subject, ''), moodle_session_id, started_at, status, last_heartbeat
	`, req.DeviceID, req.StudentID, examID, req.MoodleSessionID).
		Scan(&session.ID, &session.DeviceID, &session.StudentID, &session.ExamID, &session.ExamSubject,
			&session.MoodleSessionID, &session.StartedAt, &session.Status, &session.LastHeartbeat)
	return &session, err
}

func (r *SessionRepository) End(sessionID string) error {
	now := time.Now()
	_, err := r.db.Exec(`UPDATE exam_sessions SET status = 'ENDED', ended_at = $1 WHERE id = $2`, now, sessionID)
	return err
}

func (r *SessionRepository) UpdateStatus(sessionID, status string) error {
	_, err := r.db.Exec(`UPDATE exam_sessions SET status = $1 WHERE id = $2`, status, sessionID)
	return err
}

func (r *SessionRepository) UpdateHeartbeat(sessionID string) error {
	// Hanya update timestamp heartbeat. JANGAN auto-revert dari warning_loss ke active —
	// reconciliation status dilakukan oleh Android via STATUS_CHANGE event setelah
	// ia memvalidasi state lokal/DOM Moodle saat reconnect.
	_, err := r.db.Exec(`UPDATE exam_sessions SET last_heartbeat = NOW() WHERE id = $1`, sessionID)
	return err
}

func (r *SessionRepository) UpdateSubject(sessionID, subjectName string) error {
	_, err := r.db.Exec(`UPDATE exam_sessions SET exam_subject = $1 WHERE id = $2`, subjectName, sessionID)
	return err
}

// FindStaleSessions finds sessions that are active/in_progress but heartbeat is older than timeout.
func (r *SessionRepository) FindStaleSessions(timeoutSeconds int) ([]model.ExamSession, error) {
	rows, err := r.db.Query(`
		SELECT id, device_id, student_id, exam_id, COALESCE(exam_subject, ''), moodle_session_id, started_at, ended_at, status, last_heartbeat
		FROM exam_sessions
		WHERE status IN ('active', 'in_progress')
		  AND last_heartbeat < NOW() - INTERVAL '1 second' * $1
	`, timeoutSeconds)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []model.ExamSession
	for rows.Next() {
		var s model.ExamSession
		if err := rows.Scan(&s.ID, &s.DeviceID, &s.StudentID, &s.ExamID, &s.ExamSubject,
			&s.MoodleSessionID, &s.StartedAt, &s.EndedAt, &s.Status, &s.LastHeartbeat); err != nil {
			return nil, err
		}
		sessions = append(sessions, s)
	}
	return sessions, nil
}

func (r *SessionRepository) FindByID(id string) (*model.ExamSession, error) {
	var session model.ExamSession
	err := r.db.QueryRow(`
		SELECT id, device_id, student_id, exam_id, COALESCE(exam_subject, ''), moodle_session_id, started_at, ended_at, status, last_heartbeat
		FROM exam_sessions WHERE id = $1
	`, id).Scan(&session.ID, &session.DeviceID, &session.StudentID, &session.ExamID, &session.ExamSubject,
		&session.MoodleSessionID, &session.StartedAt, &session.EndedAt, &session.Status, &session.LastHeartbeat)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &session, err
}

func (r *SessionRepository) FindAllHistory() ([]model.SessionHistoryDTO, error) {
	query := `
		SELECT 
			s.id AS session_id,
			s.device_id,
			s.student_id,
			COALESCE(st.student_name, 'Unknown') AS student_name,
			COALESCE(st.student_class, 'Unknown') AS student_class,
			COALESCE(st.room_id, 'Unknown') AS room_id,
			s.started_at,
			s.ended_at,
			s.status AS session_status,
			COALESCE(rs.total_score, 0) AS risk_score,
			COALESCE(rs.status, 'SAFE') AS risk_status
		FROM exam_sessions s
		LEFT JOIN student_data st ON s.student_id = st.student_id
		LEFT JOIN risk_scores rs ON s.id = rs.session_id
		ORDER BY s.started_at DESC
	`
	rows, err := r.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var history []model.SessionHistoryDTO
	for rows.Next() {
		var h model.SessionHistoryDTO
		if err := rows.Scan(
			&h.SessionID, &h.DeviceID, &h.StudentID, &h.StudentName,
			&h.StudentClass, &h.RoomID, &h.StartedAt, &h.EndedAt,
			&h.SessionStatus, &h.RiskScore, &h.RiskStatus,
		); err != nil {
			return nil, err
		}
		history = append(history, h)
	}
	return history, nil
}

// EventRepository handles security event persistence.
type EventRepository struct {
	db *sql.DB
}

func NewEventRepository(db *sql.DB) *EventRepository {
	return &EventRepository{db: db}
}

func (r *EventRepository) Create(e *model.SecurityEvent) (*model.SecurityEvent, error) {
	err := r.db.QueryRow(`
		INSERT INTO security_events (session_id, event_type, event_weight, duration_seconds, frequency, screenshot_path, metadata)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, created_at
	`, e.SessionID, e.EventType, e.EventWeight, e.DurationSeconds, e.Frequency, e.ScreenshotPath, e.Metadata).
		Scan(&e.ID, &e.CreatedAt)
	return e, err
}

func (r *EventRepository) FindBySessionID(sessionID string) ([]model.SecurityEvent, error) {
	rows, err := r.db.Query(`
		SELECT id, session_id, event_type, event_weight, duration_seconds, frequency, screenshot_path, metadata, created_at
		FROM security_events WHERE session_id = $1 ORDER BY created_at DESC
	`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []model.SecurityEvent
	for rows.Next() {
		var e model.SecurityEvent
		if err := rows.Scan(&e.ID, &e.SessionID, &e.EventType, &e.EventWeight,
			&e.DurationSeconds, &e.Frequency, &e.ScreenshotPath, &e.Metadata, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, nil
}

// --- Student Repository ---

type StudentRepository struct {
	db *sql.DB
}

func NewStudentRepository(db *sql.DB) *StudentRepository {
	return &StudentRepository{db: db}
}

func (r *StudentRepository) Upsert(s *model.StudentData) error {
	_, err := r.db.Exec(`
		INSERT INTO student_data (student_id, student_name, student_class, room_id, image_url, exam_period, exam_session, exam_courses, student_status, capture_status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', 'inactive')
		ON CONFLICT (student_id) DO UPDATE SET
			student_name = EXCLUDED.student_name,
			student_class = EXCLUDED.student_class,
			room_id = EXCLUDED.room_id,
			image_url = EXCLUDED.image_url,
			exam_period = EXCLUDED.exam_period,
			exam_session = EXCLUDED.exam_session,
			exam_courses = EXCLUDED.exam_courses
	`, s.StudentID, s.StudentName, s.StudentClass, s.RoomID, s.ImageURL, s.ExamPeriod, s.ExamSession, s.ExamCourses)
	return err
}

func (r *StudentRepository) FindByID(studentID string) (*model.StudentData, error) {
	var s model.StudentData
	err := r.db.QueryRow(`
		SELECT student_id, COALESCE(student_name, ''), COALESCE(student_class, ''), COALESCE(room_id, ''), COALESCE(image_url, ''), COALESCE(exam_period, ''), COALESCE(exam_session, ''), COALESCE(exam_courses, '[]'), COALESCE(student_status, 'active'), COALESCE(capture_status, 'inactive')
		FROM student_data WHERE student_id = $1
	`, studentID).Scan(&s.StudentID, &s.StudentName, &s.StudentClass, &s.RoomID, &s.ImageURL, &s.ExamPeriod, &s.ExamSession, &s.ExamCourses, &s.StudentStatus, &s.CaptureStatus)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &s, err
}

func (r *StudentRepository) UpdateStudentStatus(studentID, status string) error {
	_, err := r.db.Exec(`UPDATE student_data SET student_status = $1 WHERE student_id = $2`, status, studentID)
	return err
}

func (r *StudentRepository) GetAllStudents() ([]model.StudentData, error) {
	rows, err := r.db.Query(`
		SELECT student_id, COALESCE(student_name, ''), COALESCE(student_class, ''), COALESCE(room_id, ''), COALESCE(image_url, ''), COALESCE(exam_period, ''), COALESCE(exam_session, ''), COALESCE(exam_courses, '[]'), COALESCE(student_status, 'active'), COALESCE(capture_status, 'inactive')
		FROM student_data
		ORDER BY student_class, student_name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var students []model.StudentData
	for rows.Next() {
		var s model.StudentData
		if err := rows.Scan(&s.StudentID, &s.StudentName, &s.StudentClass, &s.RoomID, &s.ImageURL, &s.ExamPeriod, &s.ExamSession, &s.ExamCourses, &s.StudentStatus, &s.CaptureStatus); err == nil {
			students = append(students, s)
		}
	}
	return students, nil
}

func (r *StudentRepository) UpdateCaptureStatusBulk(filterType, filterValue, status string) error {
	query := ""
	switch filterType {
	case "student":
		query = `UPDATE student_data SET capture_status = $1 WHERE student_id = $2`
	case "class":
		query = `UPDATE student_data SET capture_status = $1 WHERE student_class = $2`
	case "exam":
		// using JSONB contains operator to check if exam_courses array contains the filterValue
		query = `UPDATE student_data SET capture_status = $1 WHERE exam_courses @> ('"' || $2 || '"')::jsonb`
	case "all":
		query = `UPDATE student_data SET capture_status = $1`
		_, err := r.db.Exec(query, status)
		return err
	default:
		return fmt.Errorf("invalid filter_type")
	}

	_, err := r.db.Exec(query, status, filterValue)
	return err
}

// SumScoreBySession returns the total risk score for a session.
func (r *EventRepository) SumScoreBySession(sessionID string) (int, error) {
	var total int
	err := r.db.QueryRow(`
		SELECT COALESCE(SUM(event_weight * GREATEST(duration_seconds, 1) * GREATEST(frequency, 1)), 0)
		FROM security_events WHERE session_id = $1
	`, sessionID).Scan(&total)
	return total, err
}

// RiskScoreRepository handles risk score persistence.
type RiskScoreRepository struct {
	db *sql.DB
}

func NewRiskScoreRepository(db *sql.DB) *RiskScoreRepository {
	return &RiskScoreRepository{db: db}
}

func (r *RiskScoreRepository) Upsert(sessionID string, totalScore int, status string) (*model.RiskScore, error) {
	var rs model.RiskScore
	err := r.db.QueryRow(`
		INSERT INTO risk_scores (session_id, total_score, status, last_calculated)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (session_id) DO UPDATE SET
			total_score = EXCLUDED.total_score,
			status = EXCLUDED.status,
			last_calculated = NOW()
		RETURNING id, session_id, total_score, status, last_calculated
	`, sessionID, totalScore, status).
		Scan(&rs.ID, &rs.SessionID, &rs.TotalScore, &rs.Status, &rs.LastCalculated)
	return &rs, err
}

func (r *RiskScoreRepository) FindBySessionID(sessionID string) (*model.RiskScore, error) {
	var rs model.RiskScore
	err := r.db.QueryRow(`
		SELECT id, session_id, total_score, status, last_calculated
		FROM risk_scores WHERE session_id = $1
	`, sessionID).Scan(&rs.ID, &rs.SessionID, &rs.TotalScore, &rs.Status, &rs.LastCalculated)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &rs, err
}
