package handler

import (
	"net/http"
	"strconv"

	"github.com/exambro/server-b-security/internal/service"
	"github.com/gin-gonic/gin"
)

type ExamHandler struct {
	svc *service.ExamService
}

func NewExamHandler(svc *service.ExamService) *ExamHandler {
	return &ExamHandler{svc: svc}
}

func (h *ExamHandler) GetAllExams(c *gin.Context) {
	exams, err := h.svc.GetAllExams()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"exams": exams})
}

func (h *ExamHandler) ToggleExamStatus(c *gin.Context) {
	examID := c.Param("id")
	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.svc.ToggleExam(examID, req.Status); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Exam status updated"})
}

func (h *ExamHandler) ToggleSubjectStatus(c *gin.Context) {
	idStr := c.Param("id")
	subjectID, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subject ID"})
		return
	}

	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.svc.ToggleSubject(subjectID, req.Status); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Subject status updated"})
}
