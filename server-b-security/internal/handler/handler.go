package handler

import (
	"encoding/csv"
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/exambro/server-b-security/internal/model"
	"github.com/exambro/server-b-security/internal/repository"
	"github.com/exambro/server-b-security/internal/service"
)

// --- Device Handler ---

type DeviceHandler struct {
	svc *service.DeviceService
}

func NewDeviceHandler(svc *service.DeviceService) *DeviceHandler {
	return &DeviceHandler{svc: svc}
}

func (h *DeviceHandler) Register(c *gin.Context) {
	var req model.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	device, err := h.svc.Register(&req)
	if err != nil {
		log.Printf("ERROR registering device: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"device": device})
}

// --- Session Handler ---

type SessionHandler struct {
	svc *service.SessionService
}

func NewSessionHandler(svc *service.SessionService) *SessionHandler {
	return &SessionHandler{svc: svc}
}

func (h *SessionHandler) Start(c *gin.Context) {
	var req model.StartSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	session, captureStatus, err := h.svc.Start(&req)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"session": session, "capture_status": captureStatus})
}

func (h *SessionHandler) End(c *gin.Context) {
	var req model.EndSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.svc.End(req.SessionID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to end session"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "session ended"})
}

func (h *SessionHandler) GetScore(c *gin.Context) {
	sessionID := c.Param("id")
	score, err := h.svc.GetScore(sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get score"})
		return
	}
	if score == nil {
		c.JSON(http.StatusOK, gin.H{"score": model.RiskScore{SessionID: sessionID, TotalScore: 0, Status: "SAFE"}})
		return
	}
	c.JSON(http.StatusOK, gin.H{"score": score})
}

func (h *SessionHandler) GetEvents(c *gin.Context) {
	sessionID := c.Param("id")
	events, err := h.svc.GetEvents(sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get events"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"events": events})
}

func (h *SessionHandler) GetAll(c *gin.Context) {
	sessions, err := h.svc.GetAllSessions()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get sessions"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"sessions": sessions})
}

// --- Student Handler ---

type StudentHandler struct {
	svc *service.StudentService
}

func NewStudentHandler(svc *service.StudentService) *StudentHandler {
	return &StudentHandler{svc: svc}
}

func (h *StudentHandler) ImportCSV(c *gin.Context) {
	file, _, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file csv required"})
		return
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to parse csv"})
		return
	}

	if len(records) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "csv must contain header and at least 1 row"})
		return
	}

	// Assuming header: student_id,student_name,student_class,room_id,image_url,exam_period,exam_session,exam_courses
	var importedCount int
	for i, row := range records {
		if i == 0 {
			continue // skip header
		}
		if len(row) < 8 {
			continue // skip malformed row
		}

		// Parse courses (e.g., "Math, Physics" -> JSON array)
		courseStr := row[7]
		courseList := strings.Split(courseStr, ",")
		for j, v := range courseList {
			courseList[j] = strings.TrimSpace(v)
		}
		courseJSON, _ := json.Marshal(courseList)

		student := &model.StudentData{
			StudentID:    row[0],
			StudentName:  row[1],
			StudentClass: row[2],
			RoomID:       row[3],
			ImageURL:     row[4],
			ExamPeriod:   row[5],
			ExamSession:  row[6],
			ExamCourses:  string(courseJSON),
		}

		if err := h.svc.Upsert(student); err != nil {
			log.Printf("Failed to upsert student %s: %v", row[0], err)
		} else {
			importedCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{"message": "success", "imported": importedCount})
}

func (h *StudentHandler) GetAllStudents(c *gin.Context) {
	students, err := h.svc.GetAllStudents()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch students"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": students})
}

func (h *StudentHandler) UpdateCaptureStatusBulk(c *gin.Context) {
	var req struct {
		Status      string `json:"status" binding:"required"`      // 'active' or 'inactive'
		FilterType  string `json:"filter_type" binding:"required"` // 'student', 'class', 'exam', 'all'
		FilterValue string `json:"filter_value"`                   // value to match
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Status != "active" && req.Status != "inactive" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be active or inactive"})
		return
	}

	if err := h.svc.UpdateCaptureStatusBulk(req.FilterType, req.FilterValue, req.Status); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update capture status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "capture status updated successfully"})
}

// --- Event Handler ---

type EventHandler struct {
	svc *service.EventService
}

func NewEventHandler(svc *service.EventService) *EventHandler {
	return &EventHandler{svc: svc}
}

func (h *EventHandler) Submit(c *gin.Context) {
	var req model.SubmitEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	event, riskScore, err := h.svc.Submit(&req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to submit event"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"event":      event,
		"risk_score": riskScore,
	})
}

func (h *EventHandler) BatchSubmit(c *gin.Context) {
	var req model.BatchSubmitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.svc.BatchSubmit(req.Events); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to batch submit"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "batch submitted", "count": len(req.Events)})
}

// --- Screenshot Handler ---

type ScreenshotHandler struct {
	svc         *service.ScreenshotService
	sessionRepo *repository.SessionRepository
	eventSvc    *service.EventService
}

func NewScreenshotHandler(svc *service.ScreenshotService, sessionRepo *repository.SessionRepository, eventSvc *service.EventService) *ScreenshotHandler {
	return &ScreenshotHandler{svc: svc, sessionRepo: sessionRepo, eventSvc: eventSvc}
}

func (h *ScreenshotHandler) Upload(c *gin.Context) {
	file, header, err := c.Request.FormFile("screenshot")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "screenshot file required"})
		return
	}
	defer file.Close()

	sessionID := c.PostForm("exam_id") // Klien lama/baru mengirim sessionID di field exam_id
	studentID := c.PostForm("student_id")
	eventType := c.PostForm("event_type")

	if sessionID == "" || studentID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "exam_id (session_id) and student_id required"})
		return
	}

	if eventType == "" {
		eventType = "STUDENT_SCREENSHOT"
	}

	// Cari session dari database untuk mendapatkan subject_name dan exam_id asli
	session, err := h.sessionRepo.FindByID(sessionID)
	if err != nil || session == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Session not found"})
		return
	}

	subjectName := session.ExamSubject
	if subjectName == "" {
		subjectName = "UNKNOWN_SUBJECT"
	}

	path, err := h.svc.Upload(c.Request.Context(), subjectName, session.ExamID, studentID, eventType, file, header.Size)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to upload screenshot"})
		return
	}

	// Buat security event dengan screenshot_path tertaut
	if _, _, err := h.eventSvc.Submit(&model.SubmitEventRequest{
		SessionID:      sessionID,
		EventType:      eventType,
		Frequency:      1,
		Metadata:       "{}",
		ScreenshotPath: path,
	}); err != nil {
		log.Printf("Warning: failed to create screenshot event: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"path": path})
}
