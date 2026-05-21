package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/redis/go-redis/v9"

	"github.com/exambro/server-b-security/internal/model"
	"github.com/exambro/server-b-security/internal/repository"
)

// --- Event Weights (PRD v2) ---
var EventWeights = map[string]int{
	"SPLIT_SCREEN":           60,
	"BACKGROUND_APP":         20,
	"AI_APP_LAUNCH":          120,
	"INTERNET_ACCESS":        100,
	"APP_SWITCH":             40,
	"MULTI_WINDOW":           60,
	"OVERLAY_APP":            80,
	"FLOATING_WINDOW":        80,
	"SCREEN_RECORDING":       100,
	"NETWORK_CHANGE":         30,
	"IDENTITY_MISMATCH":      150,
	"STUDENT_SCREENSHOT":     50,
	"QUICK_SETTINGS_OPENED":  20,
	"CONNECTIVITY_LOSS":      80,
	"GUIDED_ACCESS_EXITED":   200,
	"SESSION_KILLED":         200,
	"USB_DEBUG_ENABLED":      0, // Diabaikan untuk keperluan testing developer
	"DEVICE_RESTARTED":       100,
	"APP_INSTALLED":          200,
	"FORCE_CLOSE":            100,
	"STATUS_CHANGE":          0,
	"SESSION_RESUME_REQUEST": 0,
	"NORMALLY_CLOSE":         0,
	"HEARTBEAT":              0,
}

// --- Risk Service ---

type RiskService struct {
	riskRepo  *repository.RiskScoreRepository
	eventRepo *repository.EventRepository
}

func NewRiskService(riskRepo *repository.RiskScoreRepository, eventRepo *repository.EventRepository) *RiskService {
	return &RiskService{riskRepo: riskRepo, eventRepo: eventRepo}
}

func (s *RiskService) Recalculate(sessionID string) (*model.RiskScore, error) {
	totalScore, err := s.eventRepo.SumScoreBySession(sessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to sum score: %w", err)
	}

	status := GetStatus(totalScore)
	return s.riskRepo.Upsert(sessionID, totalScore, status)
}

func (s *RiskService) GetScore(sessionID string) (*model.RiskScore, error) {
	return s.riskRepo.FindBySessionID(sessionID)
}

func GetStatus(score int) string {
	switch {
	case score < 60:
		return "SAFE"
	case score <= 120:
		return "WARNING"
	case score <= 200:
		return "INVESTIGATE"
	default:
		return "DISQUALIFIED"
	}
}

func GetEventWeight(eventType string) int {
	if w, ok := EventWeights[eventType]; ok {
		return w
	}
	return 10
}

// --- Device Service ---

type DeviceService struct {
	repo *repository.DeviceRepository
}

func NewDeviceService(repo *repository.DeviceRepository) *DeviceService {
	return &DeviceService{repo: repo}
}

func (s *DeviceService) Register(req *model.RegisterDeviceRequest) (*model.Device, error) {
	return s.repo.Upsert(req)
}

// --- Session Service ---

type SessionService struct {
	repo        *repository.SessionRepository
	riskSvc     *RiskService
	examRepo    repository.ExamRepository
	studentRepo *repository.StudentRepository
}

func NewSessionService(repo *repository.SessionRepository, riskSvc *RiskService, examRepo repository.ExamRepository, studentRepo *repository.StudentRepository) *SessionService {
	return &SessionService{repo: repo, riskSvc: riskSvc, examRepo: examRepo, studentRepo: studentRepo}
}

func (s *SessionService) Start(req *model.StartSessionRequest) (*model.ExamSession, string, error) {
	// 1. Validasi Status Siswa
	student, err := s.studentRepo.FindByID(req.StudentID)
	if err != nil {
		return nil, "", fmt.Errorf("error finding student: %w", err)
	}
	if student == nil || student.StudentStatus != "active" {
		return nil, "", fmt.Errorf("Siswa tidak terdaftar atau berstatus inactive")
	}

	// 2. Dapatkan Ujian yang sedang aktif
	activeExam, err := s.examRepo.GetActiveExam()
	if err != nil {
		return nil, "", fmt.Errorf("error finding active exam: %w", err)
	}
	if activeExam == nil {
		return nil, "", fmt.Errorf("Tidak ada ujian yang sedang dibuka saat ini")
	}

	session, err := s.repo.Create(req, activeExam.ExamID)
	return session, student.CaptureStatus, err
}

func (s *SessionService) End(sessionID string) error {
	return s.repo.End(sessionID)
}

func (s *SessionService) GetScore(sessionID string) (*model.RiskScore, error) {
	return s.riskSvc.GetScore(sessionID)
}

func (s *SessionService) GetAllSessions() ([]model.SessionHistoryDTO, error) {
	return s.repo.FindAllHistory()
}

func (s *SessionService) GetEvents(sessionID string) ([]model.SecurityEvent, error) {
	return s.riskSvc.eventRepo.FindBySessionID(sessionID)
}

// --- Student Service ---

type StudentService struct {
	repo *repository.StudentRepository
}

func NewStudentService(repo *repository.StudentRepository) *StudentService {
	return &StudentService{repo: repo}
}

func (s *StudentService) Upsert(student *model.StudentData) error {
	return s.repo.Upsert(student)
}

func (s *StudentService) GetAllStudents() ([]model.StudentData, error) {
	return s.repo.GetAllStudents()
}

func (s *StudentService) UpdateCaptureStatusBulk(filterType, filterValue, status string) error {
	return s.repo.UpdateCaptureStatusBulk(filterType, filterValue, status)
}

// --- Event Service ---

type EventService struct {
	eventRepo     *repository.EventRepository
	riskSvc       *RiskService
	redis         *redis.Client
	screenshotSvc *ScreenshotService
	sessionRepo   *repository.SessionRepository
	studentRepo   *repository.StudentRepository
}

func NewEventService(eventRepo *repository.EventRepository, riskSvc *RiskService, rdb *redis.Client, screenshotSvc *ScreenshotService, sessionRepo *repository.SessionRepository, studentRepo *repository.StudentRepository) *EventService {
	return &EventService{
		eventRepo:     eventRepo,
		riskSvc:       riskSvc,
		redis:         rdb,
		screenshotSvc: screenshotSvc,
		sessionRepo:   sessionRepo,
		studentRepo:   studentRepo,
	}
}

func (s *EventService) Submit(req *model.SubmitEventRequest) (*model.SecurityEvent, *model.RiskScore, error) {
	weight := GetEventWeight(req.EventType)
	frequency := req.Frequency
	if frequency == 0 {
		frequency = 1
	}
	// Pastikan metadata adalah JSON valid (kolom postgres bertipe JSONB)
	if req.Metadata == "" {
		req.Metadata = "{}"
	}

	// Update heartbeat timestamp setiap kali menerima event apapun
	if req.SessionID != "" {
		s.sessionRepo.UpdateHeartbeat(req.SessionID)
	}

	// Handle STATUS_CHANGE: update session status di database
	if req.EventType == "STATUS_CHANGE" && req.Metadata != "" {
		// Metadata berisi status baru, e.g. {"new_status":"in_progress"}
		var meta map[string]string
		if err := json.Unmarshal([]byte(req.Metadata), &meta); err == nil {
			if newStatus, ok := meta["new_status"]; ok {
				s.sessionRepo.UpdateStatus(req.SessionID, newStatus)
			}
		}
	}

	// Handle NORMALLY_CLOSE / FORCE_CLOSE: end session
	if req.EventType == "NORMALLY_CLOSE" || req.EventType == "FORCE_CLOSE" {
		s.sessionRepo.UpdateStatus(req.SessionID, req.EventType)
	}

	event := &model.SecurityEvent{
		SessionID:       req.SessionID,
		EventType:       req.EventType,
		EventWeight:     weight,
		DurationSeconds: req.DurationSeconds,
		Frequency:       frequency,
		Metadata:        req.Metadata,
		ScreenshotPath:  req.ScreenshotPath,
	}

	created, err := s.eventRepo.Create(event)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create event: %w", err)
	}

	riskScore, err := s.riskSvc.Recalculate(req.SessionID)
	if err != nil {
		return created, nil, fmt.Errorf("failed to recalculate risk: %w", err)
	}

	// Publish event to Redis for realtime engine
	go s.publishToRedis(created, riskScore)

	return created, riskScore, nil
}

func (s *EventService) BatchSubmit(events []model.SubmitEventRequest) error {
	for _, req := range events {
		if _, _, err := s.Submit(&req); err != nil {
			log.Printf("Error submitting batch event: %v", err)
		}
	}
	return nil
}

func (s *EventService) publishToRedis(event *model.SecurityEvent, risk *model.RiskScore) {
	payload := map[string]interface{}{
		"event":      event,
		"risk_score": risk,
	}

	session, err := s.sessionRepo.FindByID(event.SessionID)
	if err == nil && session != nil {
		studentData, err := s.studentRepo.FindByID(session.StudentID)
		if err == nil && studentData != nil {
			payload["student_data"] = studentData
		}
	}

	data, err := json.Marshal(payload)
	if err != nil {
		log.Printf("Failed to marshal event for Redis: %v", err)
		return
	}
	if err := s.redis.Publish(context.Background(), "security:events", data).Err(); err != nil {
		log.Printf("Failed to publish to Redis: %v", err)
	}
}
