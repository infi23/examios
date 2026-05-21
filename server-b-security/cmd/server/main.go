package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/redis/go-redis/v9"

	"github.com/exambro/server-b-security/internal/config"
	"github.com/exambro/server-b-security/internal/handler"
	"github.com/exambro/server-b-security/internal/middleware"
	"github.com/exambro/server-b-security/internal/repository"
	"github.com/exambro/server-b-security/internal/service"
)

func main() {
	cfg := config.Load()

	// Connect to PostgreSQL
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBName,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping PostgreSQL: %v", err)
	}
	log.Println("✓ Connected to PostgreSQL")

	// Connect to Redis
	rdb := redis.NewClient(&redis.Options{
		Addr: cfg.RedisAddr,
	})
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		log.Printf("⚠ Redis connection warning: %v (events will retry)", err)
	} else {
		log.Println("✓ Connected to Redis")
	}

	// Connect to MinIO
	minioClient, err := minio.New(cfg.MinIOEndpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.MinIOAccessKey, cfg.MinIOSecretKey, ""),
		Secure: false,
	})
	if err != nil {
		log.Fatalf("Failed to connect to MinIO: %v", err)
	}
	log.Println("✓ Connected to MinIO")

	// Auto-create bucket jika belum ada
	ctx := context.Background()
	exists, err := minioClient.BucketExists(ctx, cfg.MinIOBucket)
	if err != nil {
		log.Printf("⚠ Gagal cek bucket MinIO: %v", err)
	} else if !exists {
		err = minioClient.MakeBucket(ctx, cfg.MinIOBucket, minio.MakeBucketOptions{})
		if err != nil {
			log.Fatalf("Gagal membuat bucket '%s': %v", cfg.MinIOBucket, err)
		}
		log.Printf("✓ Bucket '%s' berhasil dibuat di MinIO", cfg.MinIOBucket)
	} else {
		log.Printf("✓ Bucket '%s' sudah ada di MinIO", cfg.MinIOBucket)
	}

	// Initialize repositories
	deviceRepo := repository.NewDeviceRepository(db)
	sessionRepo := repository.NewSessionRepository(db)
	eventRepo := repository.NewEventRepository(db)
	riskRepo := repository.NewRiskScoreRepository(db)
	studentRepo := repository.NewStudentRepository(db)
	examRepo := repository.NewExamRepository(db) // *NEW*
	appConfigRepo := repository.NewAppConfigRepo(db) // *NEW* runtime config (force-update)

	// Initialize services
	deviceSvc := service.NewDeviceService(deviceRepo)
	riskSvc := service.NewRiskService(riskRepo, eventRepo)
	screenshotSvc := service.NewScreenshotService(minioClient, cfg.MinIOBucket)
	eventSvc := service.NewEventService(eventRepo, riskSvc, rdb, screenshotSvc, sessionRepo, studentRepo)
	sessionSvc := service.NewSessionService(sessionRepo, riskSvc, examRepo, studentRepo) // *UPDATED*
	studentSvc := service.NewStudentService(studentRepo)
	examSvc := service.NewExamService(examRepo) // *NEW*
	versionSvc := service.NewVersionService(appConfigRepo) // *NEW* force-update

	// Initialize handlers
	deviceHandler := handler.NewDeviceHandler(deviceSvc)
	sessionHandler := handler.NewSessionHandler(sessionSvc)
	eventHandler := handler.NewEventHandler(eventSvc)
	screenshotHandler := handler.NewScreenshotHandler(screenshotSvc, sessionRepo, eventSvc)
	studentHandler := handler.NewStudentHandler(studentSvc)
	examHandler := handler.NewExamHandler(examSvc) // *NEW*
	versionHandler := handler.NewVersionCheckHandler(versionSvc) // *NEW* force-update
	latestAPKHandler := handler.NewLatestAPKHandler(appConfigRepo) // *NEW* APK distribution

	// Start HeartbeatChecker background goroutine
	hbChecker := service.NewHeartbeatChecker(sessionRepo, eventRepo, studentRepo, riskRepo, rdb)
	go hbChecker.Start()

	// Setup Gin router
	r := gin.Default()
	r.Use(middleware.CORS())

	v1 := r.Group("/api/v1")
	{
		devices := v1.Group("/devices")
		{ devices.POST("/register", deviceHandler.Register) }

		sessions := v1.Group("/sessions")
		{
			sessions.GET("", sessionHandler.GetAll)
			sessions.POST("/start", sessionHandler.Start)
			sessions.POST("/end", sessionHandler.End)
			sessions.GET("/:id/score", sessionHandler.GetScore)
			sessions.GET("/:id/events", sessionHandler.GetEvents)

			// Proktor update status (approve resume, force close, dll)
			sessions.PATCH("/:id/status", func(c *gin.Context) {
				sessionID := c.Param("id")
				var req struct {
					Status string `json:"status" binding:"required"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}
				if err := sessionRepo.UpdateStatus(sessionID, req.Status); err != nil {
					c.JSON(500, gin.H{"error": "failed to update status"})
					return
				}
				c.JSON(200, gin.H{"message": "status updated", "session_id": sessionID, "status": req.Status})
			})

			// Android Client mendeteksi nama subject (Course short name) di kuis
			sessions.PATCH("/:id/subject", func(c *gin.Context) {
				sessionID := c.Param("id")
				var req struct {
					SubjectName string `json:"subject_name" binding:"required"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}

				// 1. Cari subject dari active exam
				activeExam, err := examRepo.GetActiveExam()
				if err != nil || activeExam == nil {
					c.JSON(403, gin.H{"error": "Tidak ada ujian yang sedang aktif"})
					return
				}

				subject, err := examRepo.FindSubject(activeExam.ExamID, req.SubjectName)
				if err != nil || subject == nil {
					c.JSON(403, gin.H{"error": "Mata pelajaran tidak terdaftar dalam ujian aktif"})
					return
				}

				if subject.SubjectStatus != "on" {
					c.JSON(403, gin.H{"error": "Mata pelajaran belum dibuka oleh admin"})
					return
				}

				// 2. Cek apakah siswa ini berhak mengikuti mapel tersebut
				session, err := sessionRepo.FindByID(sessionID)
				if err != nil || session == nil {
					c.JSON(404, gin.H{"error": "Sesi tidak ditemukan"})
					return
				}

				student, err := studentRepo.FindByID(session.StudentID)
				if err != nil || student == nil {
					c.JSON(404, gin.H{"error": "Data siswa tidak ditemukan"})
					return
				}

				// Cek exam_courses (JSONB array) apakah mengandung course short name ini
				if !studentHasCourse(student.ExamCourses, req.SubjectName) {
					c.JSON(403, gin.H{"error": "Siswa tidak terdaftar pada mata pelajaran ini"})
					return
				}

				// 3. Semua validasi lolos, update session
				sessionRepo.UpdateSubject(sessionID, req.SubjectName)
				c.JSON(200, gin.H{"message": "Mata pelajaran diizinkan"})
			})

			// Proktor: Generate OTP keluar untuk siswa tertentu
			sessions.GET("/:id/exit-otp", func(c *gin.Context) {
				sessionID := c.Param("id")
				session, err := sessionRepo.FindByID(sessionID)
				if err != nil || session == nil {
					c.JSON(404, gin.H{"error": "Sesi tidak ditemukan"})
					return
				}
				secret := service.GenerateTOTPSecret(session.StudentID, session.ExamID)
				otp := service.GenerateTOTP(secret)
				remaining := service.GetRemainingSeconds()
				c.JSON(200, gin.H{
					"otp":               otp,
					"remaining_seconds": remaining,
					"student_id":        session.StudentID,
					"session_id":        sessionID,
				})
			})

			// Android: Verifikasi OTP keluar
			sessions.POST("/:id/verify-exit-otp", func(c *gin.Context) {
				sessionID := c.Param("id")
				var req struct {
					OTP string `json:"otp" binding:"required"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}

				session, err := sessionRepo.FindByID(sessionID)
				if err != nil || session == nil {
					c.JSON(404, gin.H{"error": "Sesi tidak ditemukan"})
					return
				}

				secret := service.GenerateTOTPSecret(session.StudentID, session.ExamID)
				if service.VerifyTOTP(secret, req.OTP) {
					c.JSON(200, gin.H{"verified": true, "message": "OTP valid. Siswa boleh keluar."})
				} else {
					c.JSON(403, gin.H{"verified": false, "message": "OTP salah atau sudah kedaluwarsa."})
				}
			})
		}

		events := v1.Group("/events")
		{
			events.POST("", eventHandler.Submit)
			events.POST("/batch", eventHandler.BatchSubmit)
		}

		screenshots := v1.Group("/screenshots")
		{
			screenshots.POST("/upload", screenshotHandler.Upload)

			// Proktor: Generate presigned URL untuk melihat screenshot dari dashboard
			screenshots.GET("/presign", func(c *gin.Context) {
				objectPath := c.Query("path")
				if objectPath == "" {
					c.JSON(400, gin.H{"error": "query param 'path' wajib diisi"})
					return
				}
				url, err := screenshotSvc.GetURL(c.Request.Context(), objectPath)
				if err != nil {
					c.JSON(500, gin.H{"error": "gagal generate presigned URL"})
					return
				}
				c.JSON(200, gin.H{"url": url})
			})
		}

		students := v1.Group("/students")
		{ 
			students.GET("", studentHandler.GetAllStudents)
			students.POST("/import", studentHandler.ImportCSV) 
			students.PATCH("/capture-status/bulk", studentHandler.UpdateCaptureStatusBulk)
			students.PATCH("/:id/status", func(c *gin.Context) {
				studentID := c.Param("id")
				var req struct {
					Status string `json:"status" binding:"required"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}
				if err := studentRepo.UpdateStudentStatus(studentID, req.Status); err != nil {
					c.JSON(500, gin.H{"error": "failed to update student status"})
					return
				}
				c.JSON(200, gin.H{"message": "student status updated"})
			})
		}

		exams := v1.Group("/exams")
		{
			exams.GET("", examHandler.GetAllExams)
			exams.PATCH("/:id/status", examHandler.ToggleExamStatus)
			exams.PATCH("/subjects/:id/status", examHandler.ToggleSubjectStatus)
		}

		// Force-update mechanism: client cek versi pada startup.
		// Konfigurasi minimum version disimpan di tabel app_config.
		app := v1.Group("/app")
		{
			app.GET("/version-check", versionHandler.Check)
			app.GET("/latest-apk", latestAPKHandler.Latest)
		}
	}

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "security-api"})
	})

	port := cfg.ServerPort
	if port == "" {
		port = "8081"
	}
	log.Printf("🚀 Security API starting on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// studentHasCourse checks if a course short name exists in the student's exam_courses JSONB array.
// exam_courses format: '["MAT-XII-IPA", "BIN-XII-IPA"]'
func studentHasCourse(examCoursesJSON string, courseShortName string) bool {
	if examCoursesJSON == "" {
		return false
	}
	var courses []string
	if err := json.Unmarshal([]byte(examCoursesJSON), &courses); err != nil {
		log.Printf("Warning: failed to parse exam_courses JSON: %v", err)
		return false
	}
	for _, c := range courses {
		if c == courseShortName {
			return true
		}
	}
	return false
}
