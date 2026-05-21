package config

import "os"

// Config holds application configuration loaded from environment variables.
type Config struct {
	// Database
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string

	// Redis
	RedisAddr string

	// MinIO
	MinIOEndpoint  string
	MinIOAccessKey string
	MinIOSecretKey string
	MinIOBucket    string

	// Moodle
	MoodleURL string

	// Server
	ServerPort string
}

// Load reads configuration from environment variables with sensible defaults.
func Load() *Config {
	return &Config{
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "exambro"),
		DBPassword: getEnv("DB_PASSWORD", "exambro_secret"),
		DBName:     getEnv("DB_NAME", "exambro_security"),

		RedisAddr: getEnv("REDIS_ADDR", "localhost:6379"),

		MinIOEndpoint:  getEnv("MINIO_ENDPOINT", "localhost:9000"),
		MinIOAccessKey: getEnv("MINIO_ACCESS_KEY", "minioadmin"),
		MinIOSecretKey: getEnv("MINIO_SECRET_KEY", "minioadmin"),
		MinIOBucket:    getEnv("MINIO_BUCKET", "exam-screenshots"),

		MoodleURL: getEnv("MOODLE_URL", "http://192.168.2.200"),

		ServerPort: getEnv("SERVER_PORT", "8081"),
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
