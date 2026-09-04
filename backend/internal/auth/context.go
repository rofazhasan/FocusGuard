package auth

import (
	"context"

	"github.com/focusguard/focusguard/backend/pkg/authcontext"
)

func WithUserClaims(ctx context.Context, claims *Claims) context.Context {
	return authcontext.WithUserClaims(ctx, claims)
}

func GetUserClaims(ctx context.Context) (*Claims, bool) {
	val, ok := authcontext.GetUserClaims(ctx)
	if !ok || val == nil {
		return nil, false
	}
	claims, ok := val.(*Claims)
	return claims, ok
}
