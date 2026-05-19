package client

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestCallRejectsStreamRequest(t *testing.T) {
	_, err := Call[protocol.FrameReply](ForSocket("unused.sock"), protocol.PasteRequest{FrameEnvelope: protocol.NewFrameEnvelope("paste")})
	if !errors.Is(err, ErrStreamReplyMode) {
		t.Fatalf("Call(PasteRequest) error = %v, want %v", err, ErrStreamReplyMode)
	}
}

func TestStreamRejectsFrameRequest(t *testing.T) {
	_, _, err := Stream[protocol.PasteStreamFrameHeader](ForSocket("unused.sock"), protocol.PingRequest{FrameEnvelope: protocol.NewFrameEnvelope("ping")})
	if !errors.Is(err, ErrFrameReplyMode) {
		t.Fatalf("Stream(PingRequest) error = %v, want %v", err, ErrFrameReplyMode)
	}
}

func TestStreamRejectsNoReplyRequest(t *testing.T) {
	_, _, err := Stream[protocol.PasteStreamFrameHeader](ForSocket("unused.sock"), protocol.FocusRequest{FrameEnvelope: protocol.NewFrameEnvelope("focus")})
	if !errors.Is(err, ErrNoReplyMode) {
		t.Fatalf("Stream(FocusRequest) error = %v, want %v", err, ErrNoReplyMode)
	}
}

func TestHoldKeepsConnectionOpenUntilCloserClosed(t *testing.T) {
	socketPath := testUnixSocket(t)
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	defer func() { _ = listener.Close() }()

	heldOpen := make(chan error, 1)
	serverDone := make(chan error, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			serverDone <- err
			return
		}
		defer func() { _ = conn.Close() }()

		var request protocol.BridgeLeaseRequest
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			serverDone <- err
			return
		}
		if _, err := conn.Write([]byte(`{"version":1,"code":"ok"}` + "\n")); err != nil {
			serverDone <- err
			return
		}

		if err := conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
			serverDone <- err
			return
		}
		var buf [1]byte
		_, err = conn.Read(buf[:])
		if err == nil {
			heldOpen <- errors.New("hold connection sent unexpected data")
			serverDone <- nil
			return
		}
		if !isTimeout(err) {
			heldOpen <- err
			serverDone <- nil
			return
		}
		heldOpen <- nil

		if err := conn.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
			serverDone <- err
			return
		}
		_, err = conn.Read(buf[:])
		if errors.Is(err, io.EOF) {
			serverDone <- nil
			return
		}
		serverDone <- err
	}()

	_, held, err := Hold[protocol.FrameReply](ForSocket(socketPath), protocol.BridgeLeaseRequest{
		FrameEnvelope: protocol.NewFrameEnvelope("bridge-lease"),
		Token:         "token",
	})
	if err != nil {
		t.Fatalf("Hold() error = %v", err)
	}
	defer func() { _ = held.Close() }()

	if err := <-heldOpen; err != nil {
		t.Fatalf("connection was not held open: %v", err)
	}
	if err := held.Close(); err != nil {
		t.Fatalf("held.Close() error = %v", err)
	}
	if err := <-serverDone; err != nil {
		t.Fatalf("server did not observe close: %v", err)
	}
}

func TestStreamPreservesPayloadBufferedWithHeader(t *testing.T) {
	socketPath := testUnixSocket(t)
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

	header, body, err := Stream[protocol.PasteStreamFrameHeader](ForSocket(socketPath), protocol.PasteRequest{FrameEnvelope: protocol.NewFrameEnvelope("paste")})
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

func testUnixSocket(t *testing.T) string {
	t.Helper()
	testDir, err := os.MkdirTemp("/tmp", "gty-client-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(testDir) })
	return filepath.Join(testDir, "d.sock")
}

func isTimeout(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}
