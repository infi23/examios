package service

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/exambro/server-b-security/internal/repository"
)

// HeartbeatChecker runs in background, checking for stale sessions.
// If a session's heartbeat is older than 60 seconds, it's marked as "warning_loss".
type HeartbeatChecker struct {
	sessionRepo *repository.SessionRepository
	eventRepo   *repository.EventRepository
	studentRepo *repository.StudentRepository
	riskRepo    *repository.RiskScoreRepository
	rdb         *redis.Client
	stopCh      chan struct{}
}

func NewHeartbeatChecker(
	sessionRepo *repository.SessionRepository,
	eventRepo *repository.EventRepository,
	studentRepo *repository.StudentRepository,
	riskRepo *repository.RiskScoreRepository,
	rdb *redis.Client,
) *HeartbeatChecker {
	return &HeartbeatChecker{
		sessionRepo: sessionRepo,
		eventRepo:   eventRepo,
		studentRepo: studentRepo,
		riskRepo:    riskRepo,
		rdb:         rdb,
		stopCh:      make(chan struct{}),
	}
}

// Start begins the heartbeat checking loop.
func (hc *HeartbeatChecker) Start() {
	log.Println("✓ HeartbeatChecker started (interval: 15s, timeout: 60s)")
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			hc.checkStaleSessions()
		case <-hc.stopCh:
			log.Println("HeartbeatChecker stopped")
			return
		}
	}
}

// Stop stops the heartbeat checking loop.
func (hc *HeartbeatChecker) Stop() {
	close(hc.stopCh)
}

func (hc *HeartbeatChecker) checkStaleSessions() {
	// Find sessions where heartbeat is older than 30 seconds
	staleSessions, err := hc.sessionRepo.FindStaleSessions(60)
	if err != nil {
		log.Printf("HeartbeatChecker: error finding stale sessions: %v", err)
		return
	}

	for _, session := range staleSessions {
		log.Printf("⚠ HeartbeatChecker: session %s (student: %s) heartbeat stale → warning_loss",
			session.ID, session.StudentID)

		// Update status to warning_loss
		if err := hc.sessionRepo.UpdateStatus(session.ID, "warning_loss"); err != nil {
			log.Printf("HeartbeatChecker: failed to update status: %v", err)
			continue
		}

		// Broadcast warning_loss event to dashboard via Redis
		hc.publishWarningLoss(session.ID, session.StudentID)
	}
}

func (hc *HeartbeatChecker) publishWarningLoss(sessionID, studentID string) {
	// Ambil risk score aktual dari database agar dashboard tidak menampilkan undefined
	var totalScore int
	riskScore, err := hc.riskRepo.FindBySessionID(sessionID)
	if err == nil && riskScore != nil {
		totalScore = riskScore.TotalScore
	}

	event := map[string]interface{}{
		"event": map[string]interface{}{
			"session_id":   sessionID,
			"student_id":   studentID,
			"event_type":   "WARNING_LOSS",
			"event_weight":  0,
			"metadata":     `{"detail":"Heartbeat timeout - koneksi terputus"}`,
		},
		"risk_score": map[string]interface{}{
			"session_id":  sessionID,
			"total_score": totalScore,
			"status":      "warning_loss",
		},
	}

	// Enrich with student data if available
	session, err := hc.sessionRepo.FindByID(sessionID)
	if err == nil && session != nil {
		studentData, err := hc.studentRepo.FindByID(session.StudentID)
		if err == nil && studentData != nil {
			event["student_data"] = studentData
		}
	}

	data, err := json.Marshal(event)
	if err != nil {
		log.Printf("HeartbeatChecker: failed to marshal event: %v", err)
		return
	}

	if err := hc.rdb.Publish(context.Background(), "security:events", data).Err(); err != nil {
		log.Printf("HeartbeatChecker: failed to publish to Redis: %v", err)
	}
}
