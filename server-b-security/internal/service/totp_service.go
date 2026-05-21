package service

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"time"
)

const (
	// OTP berlaku 60 detik per interval
	TOTPInterval = 60
	// OTP 6 digit
	TOTPDigits = 6
)

// GenerateTOTPSecret membuat secret key unik per sesi ujian siswa.
// Secret = SHA256(studentID + examID + tanggal)
func GenerateTOTPSecret(studentID, examID string) []byte {
	today := time.Now().Format("2006-01-02")
	raw := studentID + ":" + examID + ":" + today
	hash := sha256.Sum256([]byte(raw))
	return hash[:]
}

// GenerateTOTP menghasilkan OTP 6 digit berbasis waktu.
func GenerateTOTP(secret []byte) string {
	return generateTOTPAtTime(secret, time.Now())
}

// VerifyTOTP memverifikasi OTP dengan toleransi ±1 interval (±60 detik)
// agar tidak gagal jika jam HP sedikit berbeda.
func VerifyTOTP(secret []byte, otp string) bool {
	now := time.Now()
	// Cek interval saat ini dan ±1 interval sebelum/sesudahnya
	for _, offset := range []time.Duration{0, -TOTPInterval * time.Second, TOTPInterval * time.Second} {
		expected := generateTOTPAtTime(secret, now.Add(offset))
		if expected == otp {
			return true
		}
	}
	return false
}

// GetRemainingSeconds mengembalikan detik tersisa sebelum OTP berganti
func GetRemainingSeconds() int {
	now := time.Now().Unix()
	elapsed := now % TOTPInterval
	return int(TOTPInterval - elapsed)
}

func generateTOTPAtTime(secret []byte, t time.Time) string {
	// Hitung time step (interval 60 detik)
	timeStep := t.Unix() / TOTPInterval

	// Encode time step ke bytes
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, uint64(timeStep))

	// HMAC-SHA256
	mac := hmac.New(sha256.New, secret)
	mac.Write(buf)
	hash := mac.Sum(nil)

	// Dynamic truncation: ambil 4 byte dari offset
	offset := hash[len(hash)-1] & 0x0F
	code := binary.BigEndian.Uint32(hash[offset:offset+4]) & 0x7FFFFFFF

	// Ambil 6 digit terakhir
	otp := code % 1000000
	return fmt.Sprintf("%06d", otp)
}
