package service

import (
	"context"
	"fmt"
	"io"
	"log"
	"time"

	"github.com/minio/minio-go/v7"
)

// ScreenshotService handles screenshot upload and retrieval via MinIO.
type ScreenshotService struct {
	client *minio.Client
	bucket string
}

func NewScreenshotService(client *minio.Client, bucket string) *ScreenshotService {
	return &ScreenshotService{client: client, bucket: bucket}
}

// Upload stores a screenshot in MinIO and returns the object path.
// Path format: exam-screenshots/{exam_subject}/student_{studentID}/event_{event_type}_{timestamp}.jpg
func (s *ScreenshotService) Upload(ctx context.Context, subjectName, examID, studentID, eventType string, reader io.Reader, size int64) (string, error) {
	objectName := fmt.Sprintf("%s/student_%s/event_%s_%d.jpg",
		subjectName, studentID, eventType, time.Now().UnixMilli())

	_, err := s.client.PutObject(ctx, s.bucket, objectName, reader, size, minio.PutObjectOptions{
		ContentType: "image/jpeg",
	})
	if err != nil {
		return "", fmt.Errorf("failed to upload screenshot: %w", err)
	}

	log.Printf("Screenshot uploaded: %s/%s", s.bucket, objectName)
	return objectName, nil
}

// GetURL generates a presigned URL for accessing a screenshot.
func (s *ScreenshotService) GetURL(ctx context.Context, objectName string) (string, error) {
	url, err := s.client.PresignedGetObject(ctx, s.bucket, objectName, 15*time.Minute, nil)
	if err != nil {
		return "", fmt.Errorf("failed to generate presigned URL: %w", err)
	}
	return url.String(), nil
}
