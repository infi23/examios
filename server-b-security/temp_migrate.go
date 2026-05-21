package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
	"github.com/exambro/server-b-security/internal/config"
)

func main() {
	cfg := config.Load()
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBName,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer db.Close()

	_, err = db.Exec(`ALTER TABLE student_data ADD COLUMN IF NOT EXISTS capture_status VARCHAR(20) DEFAULT 'inactive';`)
	if err != nil {
		log.Fatalf("Migration failed: %v", err)
	}
	log.Println("Migration 003 successful!")
}
