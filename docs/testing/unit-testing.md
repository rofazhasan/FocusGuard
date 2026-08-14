# Testing: Unit Tests

Unit tests validate isolated domain algorithms and business logic without external dependencies.

---

## 1. Running Unit Tests

```bash
cd backend
go test -v ./internal/policies ./internal/usage ./internal/auth ./internal/enrollment ./internal/commands
```

---

## 2. Key Unit Test Suites

- **Domain Normalization & Matching (`policies/domain_matcher_test.go`)**: Validates exact matching, subdomain matching, category mapping, and negative substring safety (`notyoutube.com`).
- **Usage Normalization (`usage/usage_test.go`)**: Validates delta accumulation and date partitioning.
- **Pairing Code Generator (`enrollment/enrollment_test.go`)**: Verifies 6-character length, character set, and `FG-` prefix format.
- **Command Expiration (`commands/commands_test.go`)**: Verifies deadline calculations.
