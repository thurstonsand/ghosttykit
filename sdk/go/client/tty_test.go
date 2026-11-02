package client

import (
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestResolveTargetPrefersExplicitValue(t *testing.T) {
	t.Setenv("GTY_TTY", "/dev/ttys999")

	got := ResolveTarget("ttys001")
	if want := (protocol.Target{TTY: "/dev/ttys001"}); got != want {
		t.Fatalf("ResolveTarget() = %+v, want %+v", got, want)
	}
}

func TestResolveTargetTreatsEnvironmentAsExplicit(t *testing.T) {
	t.Setenv("GTY_TTY", "ttys002")

	got := ResolveTarget("")
	if want := (protocol.Target{TTY: "/dev/ttys002"}); got != want {
		t.Fatalf("ResolveTarget() = %+v, want %+v", got, want)
	}
}
