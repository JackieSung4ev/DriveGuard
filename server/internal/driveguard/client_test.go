package driveguard

import (
	"testing"

	"github.com/JackieSung4ev/gdrive/server/internal/model"
)

func TestParseStatus(t *testing.T) {
	values := parseStatus(`
Current configuration:
  Config file: /etc/driveguard/config.conf
  rclone remote: cloud:
  Remote directory: driveguard
  Local directory: /var/backups/driveguard
  Retention copies: 7
  Cron schedule: 0 3 * * *
  Website list: /etc/driveguard/sites.list
`)

	if got := values["rclone remote"]; got != "cloud:" {
		t.Fatalf("rclone remote = %q", got)
	}
	if got := values["retention copies"]; got != "7" {
		t.Fatalf("retention copies = %q", got)
	}
}

func TestParseLogLines(t *testing.T) {
	lines := parseLogLines(`
[2026-06-06 03:07:15] Uploaded database/store.sql.gz.enc
[2026-06-06 03:08:24] Warning: PostgreSQL password file should be checked
`)

	if len(lines) != 2 {
		t.Fatalf("len(lines) = %d", len(lines))
	}
	if lines[0].Time != "03:07:15" {
		t.Fatalf("first time = %q", lines[0].Time)
	}
	if lines[1].Level != model.LogWarning {
		t.Fatalf("second level = %q", lines[1].Level)
	}
}
