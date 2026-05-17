package client

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestDoRejectsStreamRequest(t *testing.T) {
	_, err := ForSocket("unused.sock").Do(protocol.PasteRequest{FrameEnvelope: protocol.NewFrameEnvelope("paste")})
	if !errors.Is(err, ErrStreamReplyMode) {
		t.Fatalf("Do(PasteRequest) error = %v, want %v", err, ErrStreamReplyMode)
	}
}

func TestStreamRejectsFrameRequest(t *testing.T) {
	_, _, err := Stream[protocol.PasteFrameHeader](ForSocket("unused.sock"), protocol.PingRequest{FrameEnvelope: protocol.NewFrameEnvelope("ping")})
	if !errors.Is(err, ErrFrameReplyMode) {
		t.Fatalf("Stream(PingRequest) error = %v, want %v", err, ErrFrameReplyMode)
	}
}

func TestStreamRejectsNoReplyRequest(t *testing.T) {
	_, _, err := Stream[protocol.PasteFrameHeader](ForSocket("unused.sock"), protocol.FocusRequest{FrameEnvelope: protocol.NewFrameEnvelope("focus")})
	if !errors.Is(err, ErrNoReplyMode) {
		t.Fatalf("Stream(FocusRequest) error = %v, want %v", err, ErrNoReplyMode)
	}
}

func TestStreamPreservesPayloadBufferedWithHeader(t *testing.T) {
	testDir, err := os.MkdirTemp("/tmp", "gty-client-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	defer func() { _ = os.RemoveAll(testDir) }()
	socketPath := filepath.Join(testDir, "d.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	defer func() { _ = listener.Close() }()

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()

		var request protocol.PasteRequest
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			return
		}
		_, _ = conn.Write([]byte(`{"version":1,"code":"ok","kind":"text","bytes":11}` + "\nhello world"))
	}()

	header, body, err := Stream[protocol.PasteFrameHeader](ForSocket(socketPath), protocol.PasteRequest{FrameEnvelope: protocol.NewFrameEnvelope("paste")})
	if err != nil {
		t.Fatalf("Stream() error = %v", err)
	}
	defer func() { _ = body.Close() }()

	if header.Bytes != 11 {
		t.Fatalf("header.Bytes = %d, want 11", header.Bytes)
	}
	payload, err := io.ReadAll(body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}
	if got, want := string(payload), "hello world"; got != want {
		t.Fatalf("payload = %q, want %q", got, want)
	}
}
