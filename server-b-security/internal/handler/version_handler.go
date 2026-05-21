package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/exambro/server-b-security/internal/service"
)

// VersionCheckHandler menangani GET /api/v1/app/version-check.
type VersionCheckHandler struct {
	svc *service.VersionService
}

func NewVersionCheckHandler(svc *service.VersionService) *VersionCheckHandler {
	return &VersionCheckHandler{svc: svc}
}

// Check membandingkan versi app yang dikirim client terhadap konfigurasi
// app_config di DB. Kontrak:
//   - 200 { "status": "ok" }            → versi masih didukung
//   - 426 { "error": "APP_OUTDATED", ...} → versi usang
//
// Header response Cache-Control: public, max-age=60 — agar client/HTTP cache
// tidak banjir saat ribuan device launch bersamaan.
func (h *VersionCheckHandler) Check(c *gin.Context) {
	c.Header("Cache-Control", "public, max-age=60")

	platform := c.Query("platform")
	version := c.Query("version")

	res := h.svc.Check(platform, version)
	if res.Outdated {
		c.JSON(http.StatusUpgradeRequired, gin.H{
			"error":       "APP_OUTDATED",
			"min_version": res.MinVersion,
			"force":       res.Force,
			"message":     "Versi aplikasi terlalu lama. Wajib perbarui untuk melanjutkan.",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
