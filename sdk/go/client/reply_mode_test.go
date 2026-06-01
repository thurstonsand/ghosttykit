package client

import (
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestReplyModeOf(t *testing.T) {
	if got := protocol.ReplyModeOf(protocol.NewDoctorRequest()); got != protocol.ReplyModeFrame {
		t.Fatalf("doctor reply mode = %v, want frame", got)
	}
	if got := protocol.ReplyModeOf(protocol.NewFocusRequest("", "", false, false)); got != protocol.ReplyModeNone {
		t.Fatalf("focus without ack reply mode = %v, want none", got)
	}
	focusRequest := protocol.NewFocusRequest("", "", false, true)
	if got := protocol.ReplyModeOf(focusRequest); got != protocol.ReplyModeFrame {
		t.Fatalf("focus with ack reply mode = %v, want frame", got)
	}
	if got := protocol.ReplyModeOf(protocol.NewSplitRequest("", "", "", "", "", false, false)); got != protocol.ReplyModeNone {
		t.Fatalf("split without ack reply mode = %v, want none", got)
	}
	if got := protocol.ReplyModeOf(protocol.NewPasteRequest("")); got != protocol.ReplyModeStream {
		t.Fatalf("paste reply mode = %v, want stream", got)
	}
	if got := protocol.ReplyModeOf(protocol.NewBridgeLeaseRequest("")); got != protocol.ReplyModeHold {
		t.Fatalf("bridge lease reply mode = %v, want hold", got)
	}
}
