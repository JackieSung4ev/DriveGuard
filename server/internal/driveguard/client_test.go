package driveguard

import (
	"strings"
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

func TestParseChineseStatus(t *testing.T) {
	values := parseStatus(`
当前配置：
  配置文件：/etc/driveguard/config.conf
  rclone remote：gdrive:
  远程目录：backup
  本地目录：/var/backups/driveguard
  保留份数：7
  定时任务：0 3 * * *
  网站列表：/etc/driveguard/sites.list
  MySQL/MariaDB 数据库列表：/etc/driveguard/databases.list
  密码文件：/etc/driveguard/archive.pass
`)

	if got := values["rclone remote"]; got != "gdrive:" {
		t.Fatalf("rclone remote = %q", got)
	}
	if got := values["remote directory"]; got != "backup" {
		t.Fatalf("remote directory = %q", got)
	}
	if got := values["mysql/mariadb database list"]; got != "/etc/driveguard/databases.list" {
		t.Fatalf("mysql/mariadb database list = %q", got)
	}
	if got := values["password file"]; got != "/etc/driveguard/archive.pass" {
		t.Fatalf("password file = %q", got)
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

func TestUpdateShellConfig(t *testing.T) {
	updated := updateShellConfig(`# existing
BACKUP_ROOT=/var/backups/driveguard
RCLONE_REMOTE=cloud
KEEP_COPIES=3
`, map[string]string{
		"RCLONE_REMOTE":      "gdrive",
		"RCLONE_REMOTE_PATH": "backup path",
		"KEEP_COPIES":        "7",
		"CRON_EXPR":          "30 2 * * *",
		"ENABLE_CRON_GUARD":  "1",
	}, planConfigKeyOrder)

	for _, expected := range []string{
		"BACKUP_ROOT=/var/backups/driveguard",
		"RCLONE_REMOTE='gdrive'",
		"RCLONE_REMOTE_PATH='backup path'",
		"KEEP_COPIES='7'",
		"CRON_EXPR='30 2 * * *'",
		"ENABLE_CRON_GUARD='1'",
	} {
		if !strings.Contains(updated, expected) {
			t.Fatalf("updated config does not contain %q:\n%s", expected, updated)
		}
	}
}

func TestPlansFromConfig(t *testing.T) {
	plans := PlansFromConfig(model.RuntimeConfig{
		Remote:          "gdrive:",
		RemotePath:      "backup",
		RetentionCopies: 3,
		Cron:            "0 3 * * *",
	})

	if len(plans) != 1 {
		t.Fatalf("len(plans) = %d", len(plans))
	}
	if !plans[0].Enabled || plans[0].State != model.PlanReady {
		t.Fatalf("plan not enabled: %+v", plans[0])
	}
	if plans[0].ProviderID != "google-drive" || plans[0].RemotePath != "backup" || plans[0].RetentionCopies != 3 {
		t.Fatalf("plan values = %+v", plans[0])
	}
}
