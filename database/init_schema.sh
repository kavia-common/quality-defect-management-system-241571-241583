#!/bin/bash
set -euo pipefail

# Initializes the MySQL schema for the Quality Defect Management System.
# - Idempotent: safe to re-run (uses IF NOT EXISTS).
# - Aligned with db_connection.txt connection details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [ ! -f "db_connection.txt" ]; then
  echo "ERROR: db_connection.txt not found. Cannot determine DB connection details."
  exit 1
fi

MYSQL_CMD="$(cat db_connection.txt | tr -d '\n' | sed 's/[[:space:]]*$//')"
if [ -z "${MYSQL_CMD}" ]; then
  echo "ERROR: db_connection.txt is empty."
  exit 1
fi

run_sql() {
  local sql="$1"
  # Use -e and ensure it runs non-interactively.
  ${MYSQL_CMD} -e "${sql}"
}

echo "Initializing application schema using:"
echo "  ${MYSQL_CMD}"

# Ensure consistent defaults
run_sql "SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';"
run_sql "SET SESSION time_zone = '+00:00';"

# Core RBAC tables
run_sql "CREATE TABLE IF NOT EXISTS roles ( \
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, \
  name VARCHAR(64) NOT NULL, \
  description VARCHAR(255) NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  PRIMARY KEY (id), \
  UNIQUE KEY uq_roles_name (name) \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

run_sql "CREATE TABLE IF NOT EXISTS users ( \
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, \
  username VARCHAR(64) NOT NULL, \
  email VARCHAR(255) NOT NULL, \
  password_hash VARCHAR(255) NOT NULL, \
  display_name VARCHAR(128) NULL, \
  is_active TINYINT(1) NOT NULL DEFAULT 1, \
  last_login_at TIMESTAMP NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  PRIMARY KEY (id), \
  UNIQUE KEY uq_users_username (username), \
  UNIQUE KEY uq_users_email (email), \
  KEY ix_users_active (is_active), \
  KEY ix_users_created_at (created_at) \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

run_sql "CREATE TABLE IF NOT EXISTS user_roles ( \
  user_id BIGINT UNSIGNED NOT NULL, \
  role_id BIGINT UNSIGNED NOT NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  PRIMARY KEY (user_id, role_id), \
  KEY ix_user_roles_role_id (role_id), \
  CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE, \
  CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

# Defects
run_sql "CREATE TABLE IF NOT EXISTS defects ( \
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, \
  defect_code VARCHAR(32) NOT NULL, \
  title VARCHAR(255) NOT NULL, \
  description TEXT NULL, \
  severity ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL, \
  status ENUM('OPEN','IN_PROGRESS','RESOLVED','CLOSED') NOT NULL DEFAULT 'OPEN', \
  category VARCHAR(128) NULL, \
  product_line VARCHAR(128) NULL, \
  process_step VARCHAR(128) NULL, \
  location VARCHAR(128) NULL, \
  detected_at TIMESTAMP NULL, \
  reported_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  due_date DATE NULL, \
  is_recurring TINYINT(1) NOT NULL DEFAULT 0, \
  created_by BIGINT UNSIGNED NULL, \
  assigned_to BIGINT UNSIGNED NULL, \
  updated_by BIGINT UNSIGNED NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  closed_at TIMESTAMP NULL, \
  PRIMARY KEY (id), \
  UNIQUE KEY uq_defects_code (defect_code), \
  KEY ix_defects_status (status), \
  KEY ix_defects_severity (severity), \
  KEY ix_defects_reported_at (reported_at), \
  KEY ix_defects_due_date (due_date), \
  KEY ix_defects_assigned_to (assigned_to), \
  KEY ix_defects_created_by (created_by), \
  CONSTRAINT fk_defects_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_defects_assigned_to FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_defects_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

# 5-Whys RCA: one-to-one with defect (enforced by UNIQUE(defect_id))
run_sql "CREATE TABLE IF NOT EXISTS defect_rca_5whys ( \
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, \
  defect_id BIGINT UNSIGNED NOT NULL, \
  why1 TEXT NULL, \
  why2 TEXT NULL, \
  why3 TEXT NULL, \
  why4 TEXT NULL, \
  why5 TEXT NULL, \
  root_cause TEXT NULL, \
  contributing_factors TEXT NULL, \
  verified_by BIGINT UNSIGNED NULL, \
  verified_at TIMESTAMP NULL, \
  created_by BIGINT UNSIGNED NULL, \
  updated_by BIGINT UNSIGNED NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  PRIMARY KEY (id), \
  UNIQUE KEY uq_rca_defect (defect_id), \
  KEY ix_rca_verified_at (verified_at), \
  KEY ix_rca_verified_by (verified_by), \
  CONSTRAINT fk_rca_defect FOREIGN KEY (defect_id) REFERENCES defects(id) ON DELETE CASCADE, \
  CONSTRAINT fk_rca_verified_by FOREIGN KEY (verified_by) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_rca_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_rca_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

# Corrective actions: multiple per defect
run_sql "CREATE TABLE IF NOT EXISTS corrective_actions ( \
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, \
  defect_id BIGINT UNSIGNED NOT NULL, \
  action_title VARCHAR(255) NOT NULL, \
  action_description TEXT NULL, \
  owner_id BIGINT UNSIGNED NULL, \
  status ENUM('OPEN','IN_PROGRESS','COMPLETED','CANCELLED') NOT NULL DEFAULT 'OPEN', \
  priority ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'MEDIUM', \
  due_date DATE NULL, \
  completed_at TIMESTAMP NULL, \
  completion_notes TEXT NULL, \
  effectiveness_check_notes TEXT NULL, \
  effectiveness_checked_by BIGINT UNSIGNED NULL, \
  effectiveness_checked_at TIMESTAMP NULL, \
  created_by BIGINT UNSIGNED NULL, \
  updated_by BIGINT UNSIGNED NULL, \
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  PRIMARY KEY (id), \
  KEY ix_actions_defect_id (defect_id), \
  KEY ix_actions_status (status), \
  KEY ix_actions_due_date (due_date), \
  KEY ix_actions_owner_id (owner_id), \
  KEY ix_actions_completed_at (completed_at), \
  CONSTRAINT fk_actions_defect FOREIGN KEY (defect_id) REFERENCES defects(id) ON DELETE CASCADE, \
  CONSTRAINT fk_actions_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_actions_eff_checked_by FOREIGN KEY (effectiveness_checked_by) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_actions_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL, \
  CONSTRAINT fk_actions_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL \
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"

# Seed baseline roles (idempotent)
run_sql "INSERT INTO roles (name, description) VALUES \
 ('ADMIN','System administrator'), \
 ('QUALITY_MANAGER','Quality manager / approver'), \
 ('ENGINEER','Engineer / investigator'), \
 ('OPERATOR','Operator / reporter') \
 ON DUPLICATE KEY UPDATE description = VALUES(description);"

echo "Schema initialization completed successfully."
