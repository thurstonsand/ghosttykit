package protocol

import (
	"errors"
	"testing"
)

func TestNewEnvelopeSetsProtocolVersion(t *testing.T) {
	envelope := NewEnvelope("ping")
	if envelope.Version != 1 {
		t.Fatalf("Version = %d, want 1", envelope.Version)
	}
	if envelope.Command != "ping" {
		t.Fatalf("Command = %q, want ping", envelope.Command)
	}
}

func TestResponseErrReturnsTypedError(t *testing.T) {
	response := Response{Code: CodeProtocolVersionMismatch, Error: "version mismatch"}
	err := response.Err()
	if got, want := err.Error(), "protocol_version_mismatch: version mismatch"; got != want {
		t.Fatalf("Err().Error() = %q, want %q", got, want)
	}
	if _, ok := errors.AsType[*VersionMismatchError](err); !ok {
		t.Fatalf("Err() type = %T, want VersionMismatchError", err)
	}
}
