package service

import "testing"

func TestCompareVersion(t *testing.T) {
	tests := []struct {
		a, b string
		want int
	}{
		{"1.0.0", "1.0.0", 0},
		{"1.0", "1.0.0", 0},     // segmen hilang = 0
		{"0.9.0", "1.0.0", -1},
		{"1.0.0", "0.9.0", 1},
		{"1.2.3", "1.2.4", -1},
		{"1.2.10", "1.2.9", 1},  // numeric, bukan lexicographic
		{"2.0.0", "1.99.99", 1},
		{"1.0.0-beta", "1.0.0", 0}, // suffix non-digit di-truncate
		{"", "1.0.0", -1},
		{"1.0.0", "", 1},
	}
	for _, tt := range tests {
		got := compareVersion(tt.a, tt.b)
		if got != tt.want {
			t.Errorf("compareVersion(%q, %q) = %d, want %d", tt.a, tt.b, got, tt.want)
		}
	}
}
