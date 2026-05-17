package client

import (
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

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
