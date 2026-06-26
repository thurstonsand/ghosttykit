package main

import (
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestWaitCommandUsesCall(t *testing.T) {
	testDir, err := os.MkdirTemp("/tmp", "gty-cli-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	defer func() { _ = os.RemoveAll(testDir) }()
	socketPath := filepath.Join(testDir, "d.sock")
	listener := testUnixListener(t, socketPath)
	defer func() { _ = listener.Close() }()
	t.Setenv("GTY_SOCK", socketPath)
	t.Setenv("GTY_TTY", "/dev/ttys001")

	requestCh := make(chan protocol.FocusRequest, 1)
	errorCh := make(chan error, 1)
	go serveFocusRequest(listener, requestCh, errorCh)

	cmd := newRootCmd()
	cmd.SetArgs([]string{"focus", "left", "--wait"})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}

	request := <-requestCh
	if !request.Ack {
		t.Fatal("request.Ack = false, want true")
	}
	if request.Command != "focus" {
		t.Fatalf("request.Command = %q, want focus", request.Command)
	}
	if err := <-errorCh; err != nil {
		t.Fatalf("server error = %v", err)
	}
}

func serveFocusRequest(listener net.Listener, requestCh chan<- protocol.FocusRequest, errorCh chan<- error) {
	conn, err := listener.Accept()
	if err != nil {
		errorCh <- err
		return
	}
	defer func() { _ = conn.Close() }()

	var request protocol.FocusRequest
	err = json.NewDecoder(conn).Decode(&request)
	if err != nil {
		errorCh <- err
		return
	}
	requestCh <- request
	_, err = conn.Write([]byte(`{"version":1,"code":"ok"}` + "\n"))
	errorCh <- err
}

func testUnixListener(t *testing.T, socketPath string) net.Listener {
	t.Helper()
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	return listener
}

func TestArgumentErrorUsesUsageExitCode(t *testing.T) {
	cmd := newRootCmd()
	cmd.SetArgs([]string{"focus"})
	err := cmd.Execute()
	if err == nil {
		t.Fatal("Execute() error = nil, want usage error")
	}
	cliErr, ok := errors.AsType[cliError](err)
	if !ok {
		t.Fatalf("Execute() error = %T, want cliError", err)
	}
	if got, want := cliErr.ExitCode(), exitUsage; got != want {
		t.Fatalf("ExitCode() = %d, want %d", got, want)
	}
}
