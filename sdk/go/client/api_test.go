package client

import (
	"encoding/json"
	"errors"
	"io"
	"testing"
	"time"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestBridgeReturnsHandleThatClosesLease(t *testing.T) {
	daemonSocket := testUnixSocket(t)
	bridgeSocket := testUnixSocket(t)
	daemonListener := testUnixListener(t, daemonSocket)
	defer func() { _ = daemonListener.Close() }()
	bridgeListener := testUnixListener(t, bridgeSocket)
	defer func() { _ = bridgeListener.Close() }()

	go func() {
		conn, err := daemonListener.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()
		var request protocol.BridgeCreateRequest
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			return
		}
		_, _ = io.WriteString(conn, `{"version":1,"code":"ok","socketPath":"`+bridgeSocket+`","leaseToken":"lease-token"}`+"\n")
	}()

	leaseClosed := make(chan error, 1)
	go func() {
		conn, err := bridgeListener.Accept()
		if err != nil {
			leaseClosed <- err
			return
		}
		defer func() { _ = conn.Close() }()
		var request protocol.BridgeLeaseRequest
		err = json.NewDecoder(conn).Decode(&request)
		if err != nil {
			leaseClosed <- err
			return
		}
		if request.Token != "lease-token" {
			leaseClosed <- errors.New("unexpected lease token")
			return
		}
		_, err = io.WriteString(conn, `{"version":1,"code":"ok"}`+"\n")
		if err != nil {
			leaseClosed <- err
			return
		}
		err = conn.SetReadDeadline(time.Now().Add(time.Second))
		if err != nil {
			leaseClosed <- err
			return
		}
		var buf [1]byte
		_, err = conn.Read(buf[:])
		if errors.Is(err, io.EOF) {
			leaseClosed <- nil
			return
		}
		leaseClosed <- err
	}()

	bridge, err := ForSocket(daemonSocket).Bridge(BridgeOptions{TerminalOptions: TerminalOptions{TTY: "/dev/ttys001", Focused: true}})
	if err != nil {
		t.Fatalf("Bridge() error = %v", err)
	}
	if bridge.SocketPath != bridgeSocket {
		t.Fatalf("SocketPath = %q, want %q", bridge.SocketPath, bridgeSocket)
	}
	if err := bridge.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	if err := <-leaseClosed; err != nil {
		t.Fatalf("lease did not close cleanly: %v", err)
	}
}

func TestTerminalIDReturnsValue(t *testing.T) {
	client := frameTestClient(t, `{"version":1,"code":"ok","value":"terminal-1"}`+"\n")

	terminalID, err := client.TerminalID(TerminalIDOptions{TerminalOptions: TerminalOptions{TTY: "/dev/ttys001"}})
	if err != nil {
		t.Fatalf("TerminalID() error = %v", err)
	}
	if terminalID != "terminal-1" {
		t.Fatalf("TerminalID() = %q, want terminal-1", terminalID)
	}
}

func TestTabTerminalCountParsesValue(t *testing.T) {
	client := frameTestClient(t, `{"version":1,"code":"ok","value":"3"}`+"\n")

	count, err := client.TabTerminalCount(TerminalOptions{})
	if err != nil {
		t.Fatalf("TabTerminalCount() error = %v", err)
	}
	if count != 3 {
		t.Fatalf("TabTerminalCount() = %d, want 3", count)
	}
}

func frameTestClient(t *testing.T, response string) Client {
	t.Helper()
	socketPath := testUnixSocket(t)
	listener := testUnixListener(t, socketPath)
	t.Cleanup(func() { _ = listener.Close() })

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()
		var request protocol.Request
		_ = json.NewDecoder(conn).Decode(&request)
		_, _ = io.WriteString(conn, response)
	}()

	return ForSocket(socketPath)
}
