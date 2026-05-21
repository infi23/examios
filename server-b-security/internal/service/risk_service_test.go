package service

import (
	"testing"
	"github.com/stretchr/testify/assert"
)

func TestGetStatus(t *testing.T) {
	tests := []struct {
		name           string
		score          int
		expectedStatus string
	}{
		{"Safe Boundary Low", 0, "SAFE"},
		{"Safe Boundary High", 59, "SAFE"},
		{"Warning Boundary Low", 60, "WARNING"},
		{"Warning Boundary High", 120, "WARNING"},
		{"Investigate Boundary Low", 121, "INVESTIGATE"},
		{"Investigate Boundary High", 200, "INVESTIGATE"},
		{"Disqualified Boundary", 201, "DISQUALIFIED"},
		{"Extreme Disqualified", 500, "DISQUALIFIED"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			status := GetStatus(tt.score)
			assert.Equal(t, tt.expectedStatus, status)
		})
	}
}

func TestGetEventWeight(t *testing.T) {
	tests := []struct {
		eventType      string
		expectedWeight int
	}{
		{"SPLIT_SCREEN", 60},
		{"INTERNET_ACCESS", 200},
		{"AI_APP_LAUNCH", 120},
		{"APP_SWITCH", 40},
		{"UNKNOWN_EVENT", 10}, // Default fallback
	}

	for _, tt := range tests {
		t.Run(tt.eventType, func(t *testing.T) {
			weight := GetEventWeight(tt.eventType)
			assert.Equal(t, tt.expectedWeight, weight)
		})
	}
}
