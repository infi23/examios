package service

import (
	"log"
	"strconv"
	"strings"

	"github.com/exambro/server-b-security/internal/repository"
)

// VersionService mengevaluasi apakah versi aplikasi client (iOS/Android)
// masih didukung oleh server. Konfigurasi disimpan di tabel app_config
// (key min_supported_<platform>_version, force_update_<platform>).
type VersionService struct {
	cfg *repository.AppConfigRepo
}

func NewVersionService(cfg *repository.AppConfigRepo) *VersionService {
	return &VersionService{cfg: cfg}
}

// compareVersion: -1 jika a<b, 0 jika sama, 1 jika a>b. Format "x.y.z".
// Segmen yang hilang diperlakukan sebagai 0 ("1.0" == "1.0.0").
// Segmen non-numeric (mis. "1.0.0-beta") di-truncate ke angka di depannya.
func compareVersion(a, b string) int {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	n := len(pa)
	if len(pb) > n {
		n = len(pb)
	}
	for i := 0; i < n; i++ {
		na, nb := 0, 0
		if i < len(pa) {
			na, _ = strconv.Atoi(stripNonDigit(pa[i]))
		}
		if i < len(pb) {
			nb, _ = strconv.Atoi(stripNonDigit(pb[i]))
		}
		if na != nb {
			if na < nb {
				return -1
			}
			return 1
		}
	}
	return 0
}

// stripNonDigit mengembalikan prefix angka dari string (mis. "0-beta" → "0").
func stripNonDigit(s string) string {
	for i, c := range s {
		if c < '0' || c > '9' {
			return s[:i]
		}
	}
	return s
}

// CheckResult: hasil pengecekan versi untuk satu platform.
type CheckResult struct {
	Outdated   bool
	MinVersion string
	Force      bool
}

// Check membandingkan versi app terhadap konfigurasi DB.
// Fail-open: jika config gagal dibaca atau platform tak dikenal → CheckResult kosong (tidak blokir).
func (s *VersionService) Check(platform, appVersion string) CheckResult {
	if appVersion == "" {
		return CheckResult{}
	}

	var minKey, forceKey string
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "ios":
		minKey, forceKey = "min_supported_ios_version", "force_update_ios"
	case "android":
		minKey, forceKey = "min_supported_android_version", "force_update_android"
	default:
		return CheckResult{} // platform tak dikenal → fail-open
	}

	minVer, err := s.cfg.Get(minKey)
	if err != nil || minVer == "" {
		if err != nil {
			log.Printf("VersionService: gagal baca %s: %v (fail-open)", minKey, err)
		}
		return CheckResult{}
	}

	force, _ := s.cfg.Get(forceKey)

	return CheckResult{
		Outdated:   compareVersion(appVersion, minVer) < 0,
		MinVersion: minVer,
		Force:      strings.EqualFold(force, "true"),
	}
}
