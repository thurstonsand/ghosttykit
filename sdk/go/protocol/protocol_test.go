package protocol

import (
	"errors"
	"testing"
)

func TestNewFrameEnvelopeSetsProtocolVersion(t *testing.T) {
	envelope := NewFrameEnvelope("doctor")
	if envelope.Version != 1 {
		t.Fatalf("Version = %d, want 1", envelope.Version)
	}
	if envelope.Command != "doctor" {
		t.Fatalf("Command = %q, want doctor", envelope.Command)
	}
}

func TestFrameReplyErrReturnsTypedError(t *testing.T) {
	reply := FrameReply{Code: CodeProtocolVersionMismatch, Error: "version mismatch"}
	err := reply.Err()
	if got, want := err.Error(), "protocol_version_mismatch: version mismatch"; got != want {
		t.Fatalf("Err().Error() = %q, want %q", got, want)
	}
	if _, ok := errors.AsType[*VersionMismatchError](err); !ok {
		t.Fatalf("Err() type = %T, want VersionMismatchError", err)
	}
}
