package authcontext

import (
	"context"

	"github.com/google/uuid"
)

type ContextKey string

const (
	UserClaimsKey    ContextKey = "fg_user_claims"
	DeviceContextKey ContextKey = "fg_device_context"
)

type DeviceContext struct {
	DeviceID          uuid.UUID
	UserID            uuid.UUID
	Status            string
	CredentialVersion int
}

func WithUserClaims(ctx context.Context, claims interface{}) context.Context {
	return context.WithValue(ctx, UserClaimsKey, claims)
}

func GetUserClaims(ctx context.Context) (interface{}, bool) {
	val := ctx.Value(UserClaimsKey)
	return val, val != nil
}

func WithDeviceContext(ctx context.Context, devCtx *DeviceContext) context.Context {
	return context.WithValue(ctx, DeviceContextKey, devCtx)
}

func GetDeviceContext(ctx context.Context) (*DeviceContext, bool) {
	devCtx, ok := ctx.Value(DeviceContextKey).(*DeviceContext)
	return devCtx, ok
}
