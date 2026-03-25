# Quality Defect Management System – MySQL Schema

This database container uses MySQL and initializes the application schema automatically during startup.

## Connection details (source of truth)

The connection command is stored in:

- `database/db_connection.txt`

Example:

```bash
mysql -u appuser -pdbuser123 -h localhost -P 5000 myapp
```

All schema initialization uses this file to ensure alignment with the running container credentials/port.

## Initialization behavior

- `database/startup.sh` starts MySQL, creates the database/user, writes `db_connection.txt`, then runs:
  - `database/init_schema.sh`

`init_schema.sh` is **idempotent** and safe to run multiple times.

## Tables

### RBAC
- `roles`
- `users`
- `user_roles`

### Defects
- `defects`

### Root Cause Analysis (5 Whys)
- `defect_rca_5whys` (1:1 with defects via `UNIQUE(defect_id)`)

### Corrective Actions
- `corrective_actions` (many per defect)

## Audit fields

Most tables include:

- `created_at`, `updated_at`
- `created_by`, `updated_by` (where applicable)
- additional timestamps such as `verified_at`, `completed_at`, etc.

## Indexes

Indexes are included for common access patterns:

- defect status/severity, due_date, reported_at
- corrective action status/due_date/owner
- user and role uniqueness constraints
