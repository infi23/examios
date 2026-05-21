package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/exambro/server-b-security/internal/repository"
)

// LatestAPKHandler — GET /api/v1/app/latest-apk
// Mengembalikan metadata APK Android terbaru untuk in-app self-update.
// Tidak menyajikan file APK itu sendiri — itu di MinIO bucket publik /
// CDN / nginx static. Hanya pointer-nya yang ada di sini.
type LatestAPKHandler struct {
	cfg *repository.AppConfigRepo
}

func NewLatestAPKHandler(cfg *repository.AppConfigRepo) *LatestAPKHandler {
	return &LatestAPKHandler{cfg: cfg}
}

func (h *LatestAPKHandler) Latest(c *gin.Context) {
	c.Header("Cache-Control", "public, max-age=60")

	url, _ := h.cfg.Get("latest_apk_url")
	version, _ := h.cfg.Get("latest_apk_version")
	sizeStr, _ := h.cfg.Get("latest_apk_size_bytes")
	sha256, _ := h.cfg.Get("latest_apk_sha256")

	if url == "" || version == "" {
		// Admin belum konfigurasi APK distribution.
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "NO_APK_AVAILABLE",
			"message": "APK distribution belum dikonfigurasi server.",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"url":         url,
		"version":     version,
		"size_bytes":  sizeStr,
		"sha256":      sha256,
	})
}
