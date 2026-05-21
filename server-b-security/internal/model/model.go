package model

import "time"

// Device represents a registered device fingerprint.
type Device struct {
	ID               string    `json:"id" db:"id"`
	FingerprintHash  string    `json:"fingerprint_hash" db:"fingerprint_hash"`
	AndroidID        string    `json:"android_id" db:"android_id"`
	DeviceModel      string    `json:"device_model" db:"device_model"`
	Manufacturer     string    `json:"manufacturer" db:"manufacturer"`
	ScreenResolution string    `json:"screen_resolution" db:"screen_resolution"`
	AppSignature     string    `json:"app_signature" db:"app_signature"`
	FirstSeen        time.Time `json:"first_seen" db:"first_seen"`
	LastSeen         time.Time `json:"last_seen" db:"last_seen"`
}

// ExamSession represents an active or completed exam session.
type ExamSession struct {
	ID              string     `json:"id" db:"id"`
	DeviceID        string     `json:"device_id" db:"device_id"`
	StudentID       string     `json:"student_id" db:"student_id"`
	ExamID          string     `json:"exam_id" db:"exam_id"`
	ExamSubject     string     `json:"exam_subject" db:"exam_subject"`
	MoodleSessionID string     `json:"moodle_session_id" db:"moodle_session_id"`
	StartedAt       time.Time  `json:"started_at" db:"started_at"`
	EndedAt         *time.Time `json:"ended_at,omitempty" db:"ended_at"`
	Status          string     `json:"status" db:"status"`
	LastHeartbeat   time.Time  `json:"last_heartbeat" db:"last_heartbeat"`
}

// SessionHistoryDTO represents a joined result for the Reports dashboard.
type SessionHistoryDTO struct {
	SessionID       string     `json:"session_id"`
	DeviceID        string     `json:"device_id"`
	StudentID       string     `json:"student_id"`
	StudentName     string     `json:"student_name"`
	StudentClass    string     `json:"student_class"`
	RoomID          string     `json:"room_id"`
	StartedAt       time.Time  `json:"started_at"`
	EndedAt         *time.Time `json:"ended_at,omitempty"`
	SessionStatus   string     `json:"session_status"`
	RiskScore       int        `json:"risk_score"`
	RiskStatus      string     `json:"risk_status"`
}

// StudentData represents the enriched metadata for a student.
type StudentData struct {
	StudentID     string `json:"student_id" db:"student_id"`
	StudentName   string `json:"student_name" db:"student_name"`
	StudentClass  string `json:"student_class" db:"student_class"`
	RoomID        string `json:"room_id" db:"room_id"`
	ImageURL      string `json:"image_url,omitempty" db:"image_url"`
	ExamPeriod    string `json:"exam_period" db:"exam_period"`
	ExamSession   string `json:"exam_session" db:"exam_session"`
	ExamCourses   string `json:"exam_courses" db:"exam_courses"`      // Disimpan sebagai JSON string di DB
	StudentStatus string `json:"student_status" db:"student_status"`  // 'active' or 'inactive'
	CaptureStatus string `json:"capture_status" db:"capture_status"`
}

// ExamCategory represents an exam group (e.g. 210424-J1)
type ExamCategory struct {
	ExamID     string `json:"exam_id" db:"exam_id"`
	ExamName   string `json:"exam_name" db:"exam_name"`
	ExamStatus string `json:"exam_status" db:"exam_status"` // 'on' or 'off'
}

// ExamSubject represents a specific subject within an exam category
type ExamSubject struct {
	ID            int64  `json:"id" db:"id"`
	ExamID        string `json:"exam_id" db:"exam_id"`
	ExamSubject   string `json:"exam_subject" db:"exam_subject"`
	SubjectStatus string `json:"subject_status" db:"subject_status"` // 'on' or 'off'
}

// SecurityEvent represents a security-related event during an exam.
type SecurityEvent struct {
	ID              int64     `json:"id" db:"id"`
	SessionID       string    `json:"session_id" db:"session_id"`
	EventType       string    `json:"event_type" db:"event_type"`
	EventWeight     int       `json:"event_weight" db:"event_weight"`
	DurationSeconds int       `json:"duration_seconds" db:"duration_seconds"`
	Frequency       int       `json:"frequency" db:"frequency"`
	ScreenshotPath  string    `json:"screenshot_path,omitempty" db:"screenshot_path"`
	Metadata        string    `json:"metadata,omitempty" db:"metadata"`
	CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

// RiskScore holds the aggregated risk score for a session.
type RiskScore struct {
	ID             int64     `json:"id" db:"id"`
	SessionID      string    `json:"session_id" db:"session_id"`
	TotalScore     int       `json:"total_score" db:"total_score"`
	Status         string    `json:"status" db:"status"`
	LastCalculated time.Time `json:"last_calculated" db:"last_calculated"`
}

// --- Request/Response DTOs ---

// RegisterDeviceRequest is the payload to register or update a device.
type RegisterDeviceRequest struct {
	FingerprintHash  string `json:"fingerprint_hash" binding:"required"`
	AndroidID        string `json:"android_id" binding:"required"`
	DeviceModel      string `json:"device_model" binding:"required"`
	Manufacturer     string `json:"manufacturer" binding:"required"`
	ScreenResolution string `json:"screen_resolution" binding:"required"`
	AppSignature     string `json:"app_signature" binding:"required"`
}

// StartSessionRequest is the payload to start a new exam session.
type StartSessionRequest struct {
	DeviceID        string `json:"device_id" binding:"required"`
	StudentID       string `json:"student_id" binding:"required"`
	MoodleSessionID string `json:"moodle_session_id"`
	// ExamID is removed because it will be auto-assigned by the server
}

// EndSessionRequest is the payload to end an exam session.
type EndSessionRequest struct {
	SessionID string `json:"session_id" binding:"required"`
}

// SubmitEventRequest is the payload for a single security event.
type SubmitEventRequest struct {
	SessionID       string `json:"session_id" binding:"required"`
	EventType       string `json:"event_type" binding:"required"`
	DurationSeconds int    `json:"duration_seconds"`
	Frequency       int    `json:"frequency"`
	Metadata        string `json:"metadata"`
	ScreenshotPath  string `json:"screenshot_path,omitempty"`
}

// BatchSubmitRequest contains multiple events (offline sync).
type BatchSubmitRequest struct {
	Events []SubmitEventRequest `json:"events" binding:"required,min=1"`
}
