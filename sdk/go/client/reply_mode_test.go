package client

import (
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestReplyModeOf(t *testing.T) {
	if got := protocol.ReplyModeOf(protocol.PingRequest{FrameEnvelope: protocol.NewFrameEnvelope("ping")}); got != protocol.ReplyModeFrame {
		t.Fatalf("ping reply mode = %v, want frame", got)
	}
	if got := protocol.ReplyModeOf(protocol.FocusRequest{FrameEnvelope: protocol.NewFrameEnvelope("focus")}); got != protocol.ReplyModeNone {
		t.Fatalf("focus without ack reply mode = %v, want none", got)
	}
	if got := protocol.ReplyModeOf(protocol.FocusRequest{FrameEnvelope: protocol.NewFrameEnvelope("focus"), Ack: true}); got != protocol.ReplyModeFrame {
		t.Fatalf("focus with ack reply mode = %v, want frame", got)
	}
	if got := protocol.ReplyModeOf(protocol.SplitRequest{FrameEnvelope: protocol.NewFrameEnvelope("split")}); got != protocol.ReplyModeNone {
		t.Fatalf("split without ack reply mode = %v, want none", got)
	}
	if got := protocol.ReplyModeOf(protocol.PasteRequest{FrameEnvelope: protocol.NewFrameEnvelope("paste")}); got != protocol.ReplyModeStream {
		t.Fatalf("paste reply mode = %v, want stream", got)
	}
}
