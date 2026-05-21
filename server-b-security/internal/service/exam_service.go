package service

import (
	"github.com/exambro/server-b-security/internal/repository"
)

type ExamService struct {
	repo repository.ExamRepository
}

func NewExamService(repo repository.ExamRepository) *ExamService {
	return &ExamService{repo: repo}
}

func (s *ExamService) GetAllExams() ([]map[string]interface{}, error) {
	categories, err := s.repo.GetAllCategories()
	if err != nil {
		return nil, err
	}

	var result []map[string]interface{}
	for _, cat := range categories {
		subjects, err := s.repo.GetSubjectsByCategory(cat.ExamID)
		if err != nil {
			return nil, err
		}
		
		item := map[string]interface{}{
			"exam_id":     cat.ExamID,
			"exam_name":   cat.ExamName,
			"exam_status": cat.ExamStatus,
			"subjects":    subjects,
		}
		result = append(result, item)
	}
	return result, nil
}

func (s *ExamService) ToggleExam(examID, status string) error {
	return s.repo.ToggleExamStatus(examID, status)
}

func (s *ExamService) ToggleSubject(subjectID int64, status string) error {
	return s.repo.ToggleSubjectStatus(subjectID, status)
}
