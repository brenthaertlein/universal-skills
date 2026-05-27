---
name: security-review
description: "[pr-review-focus-area: Security] Web application security review for XSS, CSRF, SQL injection, auth bypass, data exposure, CORS, and rate limiting."
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Security Review

Review web application code for security vulnerabilities.

## Invocation

`/security-review` — reviews changed files for security issues.

## Checks

### XSS (Cross-Site Scripting)
- Flag unsafe HTML injection APIs (`innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `{@html}`, `[innerHTML]`, `outerHTML`, `document.write`).
- Flag rendering of user input without sanitization.
- Flag template literal injection into HTML.
- Verify Content Security Policy headers are configured.

### CSRF (Cross-Site Request Forgery)
- State-changing endpoints must validate CSRF tokens or use SameSite cookies.
- Flag forms without CSRF token fields.
- Flag API routes that accept state changes without origin validation.

### SQL Injection
- Flag string concatenation or template literals in SQL queries.
- Verify all queries use parameterized statements or the ORM's query builder.
- Flag raw SQL execution without parameter binding.

### Authentication & Authorization
- Flag routes missing auth middleware (cross-reference with CLAUDE.md patterns).
- Flag authorization checks that only verify authentication, not permissions.
- Flag hardcoded credentials, tokens, or secrets.
- Verify password handling uses bcrypt/argon2/scrypt, never MD5/SHA for passwords.
- Check session configuration: httpOnly, secure, sameSite flags on cookies.

### Sensitive Data Exposure
- Flag PII logged to console or application logs.
- Flag sensitive fields returned in API responses that should be omitted (passwords, tokens, keys).
- Verify error responses don't leak stack traces or internal details in production.
- Check that sensitive form fields use `type="password"` and `autocomplete="off"`.

### CORS Configuration
- Flag `Access-Control-Allow-Origin: *` on authenticated endpoints.
- Verify CORS origins are explicitly configured, not dynamically reflected from request.
- Check that credentials mode and allowed methods are appropriately scoped.

### Rate Limiting
- Flag authentication endpoints without rate limiting (login, register, password reset).
- Flag API endpoints that perform expensive operations without throttling.
- Verify rate limiting middleware is applied at the appropriate layer.

### Dependency Security
- Flag known vulnerable package patterns if detected in lock files.
- Suggest running `npm audit` / `pip audit` / equivalent if not part of CI.

### Senior Review

Dispatch to the `principal-frontend` subagent with the findings collected above. Ask it to apply its senior lens — XSS sinks, CSP posture, auth cookie flags, secret exposure in the client bundle — to the findings. Integrate its top findings into the Report Format below using the severity scale defined next; do not replace the skill's verdict contract.

Invocation:
```
Agent({
  subagent_type: "principal-frontend",
  description: "Security senior review",
  prompt: "Review these security findings: <summary of XSS, CSRF, SQLi, authn/z, data-exposure, CORS, rate-limit, and dependency findings>. Apply senior scrutiny to XSS sinks reachable via user input, CSP posture, auth cookie flags (httpOnly/secure/sameSite), and any secret/PII exposure in the client bundle. Return top security risks in severity order."
})
```

## Severity Levels

- **[CRITICAL]**: Exploitable vulnerability (SQL injection, auth bypass, credential exposure).
- **[HIGH]**: Significant risk (XSS, CSRF, missing auth).
- **[MEDIUM]**: Defense-in-depth issue (missing rate limiting, broad CORS).
- **[LOW]**: Best practice deviation (verbose error messages, missing security headers).

## Report Format

List each finding with severity, file, line, and remediation suggestion. End with a summary count by severity.
