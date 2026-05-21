package repository

import (
	"database/sql"
	"sync"
	"time"
)

// AppConfigRepo membaca key-value dari tabel app_config dengan cache TTL 60 detik.
// Cache di-refresh ketika expired ATAU saat Set() dipanggil.
type AppConfigRepo struct {
	db     *sql.DB
	mu     sync.RWMutex
	cache  map[string]string
	expiry time.Time
}

const appConfigCacheTTL = 60 * time.Second

func NewAppConfigRepo(db *sql.DB) *AppConfigRepo {
	return &AppConfigRepo{db: db, cache: map[string]string{}}
}

// Get mengambil nilai dari cache (kalau masih segar) atau dari DB.
// Mengembalikan string kosong (tanpa error) bila key tidak ditemukan.
func (r *AppConfigRepo) Get(key string) (string, error) {
	r.mu.RLock()
	if time.Now().Before(r.expiry) {
		v, ok := r.cache[key]
		r.mu.RUnlock()
		if ok {
			return v, nil
		}
		// Cache valid tapi key tidak ada → tidak perlu round-trip DB.
		return "", nil
	}
	r.mu.RUnlock()
	return r.refresh(key)
}

// refresh muat ulang seluruh tabel ke cache & kembalikan nilai key.
func (r *AppConfigRepo) refresh(key string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Double-check di bawah lock untuk hindari thundering herd.
	if time.Now().Before(r.expiry) {
		return r.cache[key], nil
	}

	rows, err := r.db.Query(`SELECT key, value FROM app_config`)
	if err != nil {
		return "", err
	}
	defer rows.Close()

	fresh := map[string]string{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return "", err
		}
		fresh[k] = v
	}
	if err := rows.Err(); err != nil {
		return "", err
	}

	r.cache = fresh
	r.expiry = time.Now().Add(appConfigCacheTTL)
	return fresh[key], nil
}

// Set menulis (upsert) ke DB & invalidasi cache agar refresh berikutnya
// mengambil nilai terbaru. Dipakai bila ada dashboard admin mengubah konfigurasi.
func (r *AppConfigRepo) Set(key, value string) error {
	_, err := r.db.Exec(`
		INSERT INTO app_config (key, value, updated_at) VALUES ($1, $2, NOW())
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
	`, key, value)
	if err != nil {
		return err
	}

	r.mu.Lock()
	r.expiry = time.Time{} // invalidasi cache
	r.mu.Unlock()
	return nil
}
