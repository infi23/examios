package repository

import (
	"database/sql"
	"fmt"

	"github.com/exambro/server-b-security/internal/model"
)

// ExamRepository defines methods for managing exams and subjects.
type ExamRepository interface {
	GetActiveExam() (*model.ExamCategory, error)
	FindSubject(examID, subjectName string) (*model.ExamSubject, error)
	GetAllCategories() ([]model.ExamCategory, error)
	GetSubjectsByCategory(examID string) ([]model.ExamSubject, error)
	ToggleExamStatus(examID, status string) error
	ToggleSubjectStatus(subjectID int64, status string) error
}

type examRepository struct {
	db *sql.DB
}

// NewExamRepository creates a new ExamRepository.
func NewExamRepository(db *sql.DB) ExamRepository {
	return &examRepository{db: db}
}

func (r *examRepository) GetActiveExam() (*model.ExamCategory, error) {
	var category model.ExamCategory
	query := `SELECT exam_id, exam_name, exam_status FROM exam_categories WHERE exam_status = 'on' LIMIT 1`
	err := r.db.QueryRow(query).Scan(&category.ExamID, &category.ExamName, &category.ExamStatus)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Not found
		}
		return nil, fmt.Errorf("failed to get active exam: %w", err)
	}
	return &category, nil
}

func (r *examRepository) FindSubject(examID, subjectName string) (*model.ExamSubject, error) {
	var subject model.ExamSubject
	query := `SELECT id, exam_id, exam_subject, subject_status FROM exam_subjects WHERE exam_id = $1 AND exam_subject = $2 LIMIT 1`
	err := r.db.QueryRow(query, examID, subjectName).Scan(&subject.ID, &subject.ExamID, &subject.ExamSubject, &subject.SubjectStatus)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to find subject: %w", err)
	}
	return &subject, nil
}

func (r *examRepository) GetAllCategories() ([]model.ExamCategory, error) {
	var categories []model.ExamCategory
	query := `SELECT exam_id, exam_name, exam_status FROM exam_categories ORDER BY exam_id ASC`
	rows, err := r.db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to get categories: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var cat model.ExamCategory
		if err := rows.Scan(&cat.ExamID, &cat.ExamName, &cat.ExamStatus); err != nil {
			return nil, err
		}
		categories = append(categories, cat)
	}
	return categories, nil
}

func (r *examRepository) GetSubjectsByCategory(examID string) ([]model.ExamSubject, error) {
	var subjects []model.ExamSubject
	query := `SELECT id, exam_id, exam_subject, subject_status FROM exam_subjects WHERE exam_id = $1 ORDER BY exam_subject ASC`
	rows, err := r.db.Query(query, examID)
	if err != nil {
		return nil, fmt.Errorf("failed to get subjects: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var sub model.ExamSubject
		if err := rows.Scan(&sub.ID, &sub.ExamID, &sub.ExamSubject, &sub.SubjectStatus); err != nil {
			return nil, err
		}
		subjects = append(subjects, sub)
	}
	return subjects, nil
}

func (r *examRepository) ToggleExamStatus(examID, status string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 1. Update the exam category status
	_, err = tx.Exec(`UPDATE exam_categories SET exam_status = $1 WHERE exam_id = $2`, status, examID)
	if err != nil {
		return fmt.Errorf("failed to update exam status: %w", err)
	}

	// 2. If turning ON, turn OFF all other exams
	if status == "on" {
		_, err = tx.Exec(`UPDATE exam_categories SET exam_status = 'off' WHERE exam_id != $1`, examID)
		if err != nil {
			return fmt.Errorf("failed to turn off other exams: %w", err)
		}
	}

	// 3. Automatically turn ON/OFF all its subjects
	_, err = tx.Exec(`UPDATE exam_subjects SET subject_status = $1 WHERE exam_id = $2`, status, examID)
	if err != nil {
		return fmt.Errorf("failed to update subjects status: %w", err)
	}

	return tx.Commit()
}

func (r *examRepository) ToggleSubjectStatus(subjectID int64, status string) error {
	_, err := r.db.Exec(`UPDATE exam_subjects SET subject_status = $1 WHERE id = $2`, status, subjectID)
	if err != nil {
		return fmt.Errorf("failed to update subject status: %w", err)
	}
	return nil
}
