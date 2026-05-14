package client

import (
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestExpectsResponse(t *testing.T) {
	if !expectsResponse(protocol.PingRequest{Envelope: protocol.NewEnvelope("ping")}) {
		t.Fatal("ping should expect response")
	}
	if expectsResponse(protocol.FocusRequest{Envelope: protocol.NewEnvelope("focus")}) {
		t.Fatal("focus without ack should not expect response")
	}
	if !expectsResponse(protocol.FocusRequest{Envelope: protocol.NewEnvelope("focus"), Ack: true}) {
		t.Fatal("focus with ack should expect response")
	}
	if expectsResponse(protocol.SplitRequest{Envelope: protocol.NewEnvelope("split")}) {
		t.Fatal("split without ack should not expect response")
	}
}
