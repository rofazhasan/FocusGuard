package middleware

import (
	"context"
	"database/sql"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/pkg/apierror"
	"github.com/focusguard/focusguard/backend/pkg/authcontext"
	"github.com/focusguard/focusguard/backend/pkg/requestid"
)

type DeviceContext = authcontext.DeviceContext

const UserContextKey = authcontext.UserClaimsKey

// AuthMiddleware validates User JWT tokens (for Dashboard / Owner operations)
func AuthMiddleware(tokenService *auth.TokenService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			reqID := requestid.FromContext(r.Context())
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Authorization header missing", reqID)
				return
			}

			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Invalid authorization header format", reqID)
				return
			}

			tokenString := parts[1]
			claims, err := tokenService.ValidateToken(tokenString)
			if err != nil {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthExpired, "Invalid or expired token", reqID)
				return
			}

			ctx := auth.WithUserClaims(r.Context(), claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// DeviceAuthMiddleware validates Device credentials (rejects revoked, expired, unknown devices)
func DeviceAuthMiddleware(db *sql.DB, tokenService *auth.TokenService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			reqID := requestid.FromContext(r.Context())
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Device authorization header missing", reqID)
				return
			}

			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Invalid authorization header format", reqID)
				return
			}

			tokenString := parts[1]
			claims, err := tokenService.ValidateToken(tokenString)
			if err != nil {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthExpired, "Invalid or expired device credential", reqID)
				return
			}

			deviceID := claims.DeviceID
			if deviceID == uuid.Nil {
				if parsed, parseErr := uuid.Parse(claims.Subject); parseErr == nil {
					deviceID = parsed
				}
			}

			if deviceID == uuid.Nil {
				apierror.Write(w, http.StatusForbidden, apierror.CodeAuthInvalid, "Token is not an authorized device credential", reqID)
				return
			}

			devCtx := &authcontext.DeviceContext{
				DeviceID:          deviceID,
				UserID:            claims.UserID,
				Status:            "ACTIVE",
				CredentialVersion: claims.CredentialVersion,
			}

			if db != nil {
				var status, ownerUserIDStr string
				q := `SELECT status, user_id FROM devices WHERE id = $1`
				err := db.QueryRowContext(r.Context(), q, deviceID.String()).Scan(&status, &ownerUserIDStr)
				if err == sql.ErrNoRows {
					apierror.Write(w, http.StatusNotFound, apierror.CodeDeviceNotFound, "Device not found in registry", reqID)
					return
				} else if err != nil {
					apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error verifying device", reqID)
					return
				}

				if strings.ToUpper(status) == "REVOKED" {
					apierror.Write(w, http.StatusForbidden, apierror.CodeDeviceRevoked, "This device has been permanently revoked by the account owner", reqID)
					return
				}

				if claims.UserID != uuid.Nil && ownerUserIDStr != claims.UserID.String() {
					apierror.Write(w, http.StatusForbidden, apierror.CodeAuthInvalid, "Device ownership mismatch", reqID)
					return
				}

				var credVersion int
				var revokedAt sql.NullTime
				var expiresAt time.Time
				cq := `SELECT credential_version, revoked_at, expires_at FROM device_credentials WHERE device_id = $1 ORDER BY credential_version DESC LIMIT 1`
				err = db.QueryRowContext(r.Context(), cq, deviceID.String()).Scan(&credVersion, &revokedAt, &expiresAt)
				if err == nil {
					if revokedAt.Valid || time.Now().UTC().After(expiresAt) {
						apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthRevoked, "Device credential has been revoked or expired", reqID)
						return
					}
					if claims.CredentialVersion > 0 && claims.CredentialVersion < credVersion {
						apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthRevoked, "Obsolete credential version", reqID)
						return
					}
				}

				devCtx.Status = status
				devCtx.UserID, _ = uuid.Parse(ownerUserIDStr)
			}

			ctx := authcontext.WithDeviceContext(r.Context(), devCtx)
			if claims.UserID != uuid.Nil {
				ctx = auth.WithUserClaims(ctx, claims)
			}

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// DeviceOrUserAuthMiddleware allows endpoints accessed by either User or Device
func DeviceOrUserAuthMiddleware(db *sql.DB, tokenService *auth.TokenService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			reqID := requestid.FromContext(r.Context())
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Authorization header missing", reqID)
				return
			}

			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Invalid authorization header format", reqID)
				return
			}

			claims, err := tokenService.ValidateToken(parts[1])
			if err != nil {
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthExpired, "Invalid or expired token", reqID)
				return
			}

			ctx := auth.WithUserClaims(r.Context(), claims)

			deviceID := claims.DeviceID
			if deviceID == uuid.Nil {
				if parsed, parseErr := uuid.Parse(claims.Subject); parseErr == nil {
					deviceID = parsed
				}
			}

			if deviceID != uuid.Nil && db != nil {
				var status string
				err := db.QueryRowContext(r.Context(), `SELECT status FROM devices WHERE id = $1`, deviceID.String()).Scan(&status)
				if err == nil && strings.ToUpper(status) == "REVOKED" {
					apierror.Write(w, http.StatusForbidden, apierror.CodeDeviceRevoked, "Device has been revoked", reqID)
					return
				}

				devCtx := &authcontext.DeviceContext{
					DeviceID:          deviceID,
					UserID:            claims.UserID,
					Status:            status,
					CredentialVersion: claims.CredentialVersion,
				}
				ctx = authcontext.WithDeviceContext(ctx, devCtx)
			}

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func GetUserClaims(ctx context.Context) (*auth.Claims, bool) {
	return auth.GetUserClaims(ctx)
}

func GetDeviceClaims(ctx context.Context) (*authcontext.DeviceContext, bool) {
	return authcontext.GetDeviceContext(ctx)
}
