package client

import "testing"

func TestResolveTTYPrefersExplicitValue(t *testing.T) {
	t.Setenv("GTY_TTY", "/dev/ttys999")

	got, err := ResolveTTY("ttys001")
	if err != nil {
		t.Fatalf("ResolveTTY() error = %v", err)
	}
	if got != "/dev/ttys001" {
		t.Fatalf("ResolveTTY() = %q, want %q", got, "/dev/ttys001")
	}
}

func TestResolveTTYUsesEnvironment(t *testing.T) {
	t.Setenv("GTY_TTY", "ttys002")

	got, err := ResolveTTY("")
	if err != nil {
		t.Fatalf("ResolveTTY() error = %v", err)
	}
	if got != "/dev/ttys002" {
		t.Fatalf("ResolveTTY() = %q, want %q", got, "/dev/ttys002")
	}
}
