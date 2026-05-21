package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

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

	sqlBytes, err := os.ReadFile("migrations/002_student_data.sql")
	if err != nil {
		log.Fatalf("Failed to read sql: %v", err)
	}

	_, err = db.Exec(string(sqlBytes))
	if err != nil {
		log.Fatalf("Migration failed: %v", err)
	}
	log.Println("Migration successful!")
}
