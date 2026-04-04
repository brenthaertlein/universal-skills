---
name: security-audit
description: "Comprehensive security and PII audit for infrastructure repos. Scan for secrets, credentials, and sensitive data before committing."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Security & PII Audit

Scan tracked and staged files for secrets, credentials, PII, and sensitive data. This skill is designed to catch leaks before they are committed.

## Invocation

Run automatically as part of pre-commit workflows, or manually via `/security-audit`.

## Scan Categories

### 1. PII Scan

Search for personally identifiable information in all tracked and staged files:

- **Email addresses**: patterns matching `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`
- **Phone numbers**: US and international formats
- **Credit card numbers**: 13-19 digit sequences matching Luhn algorithm patterns
- **SSNs**: `\d{3}-\d{2}-\d{4}` patterns
- **Real names**: check for name-like strings in config files, comments, and variables (flag for human review)

Exclude: test fixtures with obviously fake data (e.g., `test@example.com`, `Jane Doe`).

### 2. Secrets Scan

Search for credentials and API keys:

- **AWS**: `AKIA[0-9A-Z]{16}`, `aws_secret_access_key`, `AWS_SESSION_TOKEN`
- **GCP**: service account JSON keys, `GOOGLE_APPLICATION_CREDENTIALS`
- **Azure**: `AccountKey=`, `client_secret`, Azure connection strings
- **GitHub**: `ghp_`, `gho_`, `ghs_`, `ghr_`, `github_pat_` prefixed tokens
- **Generic API keys**: `api[_-]?key`, `api[_-]?secret`, `bearer [a-zA-Z0-9._-]+`
- **Private keys**: `-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----`
- **Passwords**: `password\s*[:=]`, `passwd\s*[:=]`, hardcoded credential assignments
- **Database URLs**: connection strings with embedded credentials (`://user:pass@`)
- **JWT tokens**: `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+`

### 3. Infrastructure Scan

Search for infrastructure details that should not be in code:

- **IP addresses**: IPv4 and IPv6 (exclude `127.0.0.1`, `0.0.0.0`, `::1`, and RFC 5737 documentation ranges)
- **Hostnames/domains**: FQDN patterns in config files
- **Port numbers**: non-standard ports in hardcoded strings (exclude well-known defaults like 80, 443, 22)
- **Connection strings**: database, Redis, AMQP, and other service connection strings

**Note**: Internal IPs and domain names documented in the project's CLAUDE.md are expected findings. Flag these as **[OK]**, not **[WARN]**.

### 4. Sensitive File Types

Check that none of the following file types are staged for commit:

| Pattern         | Description                    |
| --------------- | ------------------------------ |
| `.env`          | Environment variables          |
| `.env.*`        | Environment variant files      |
| `*.pem`         | Certificates                   |
| `*.key`         | Private keys                   |
| `*.p12`         | PKCS#12 keystores              |
| `*.pfx`         | PKCS#12 keystores              |
| `*.tfstate`     | Terraform state                |
| `*.tfstate.*`   | Terraform state backups        |
| `*.tfvars`      | Terraform variables (may contain secrets) |
| `id_rsa*`       | SSH private keys               |
| `id_ed25519*`   | SSH private keys               |
| `kubeconfig`    | Kubernetes credentials         |
| `credentials`   | Generic credential files       |
| `*.jks`         | Java keystores                 |

## Output Format

For each finding, report one of:

- **[BLOCK]** — Must be fixed before commit. Secrets, credentials, private keys.
- **[WARN]** — Requires human review. PII patterns, infrastructure details that may be intentional.
- **[OK]** — Expected finding. Known internal values documented in CLAUDE.md, test fixtures, documentation examples.

### Report Structure

```
## Security Audit Report

### PII Scan
- [WARN] src/config/notifications.ts:42 — Email address found: review if real or example
- [OK] tests/fixtures/users.json:5 — Test fixture with example data

### Secrets Scan
- [BLOCK] scripts/deploy.sh:18 — Hardcoded API key assignment
- [OK] docs/setup.md:33 — Example placeholder key

### Infrastructure Scan
- [OK] ansible/inventory/hosts.yml:4 — Internal IP (documented in CLAUDE.md)
- [WARN] scripts/backup.sh:12 — Hardcoded hostname

### Sensitive Files
- [BLOCK] .env.production — Staged for commit, must be removed

### Verdict: FAIL
- 2 BLOCK findings must be resolved
- 1 WARN finding requires review
```

## Verdict Rules

- **PASS**: No [BLOCK] or [WARN] findings.
- **PASS WITH WARNINGS**: No [BLOCK] findings, but one or more [WARN] findings that need human review.
- **FAIL**: One or more [BLOCK] findings.

## Execution Notes

1. Read CLAUDE.md first to identify known internal IPs, hostnames, and domains that are expected.
2. Use `git diff --cached --name-only` for staged files and `git ls-files` for tracked files.
3. Binary files should be checked by name/extension only (sensitive file type check), not content-scanned.
4. Minimize false positives: skip test fixtures with obviously fake data, documentation examples with placeholder values, and `.example` files.
