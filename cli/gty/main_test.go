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
	go serveOneRequest(listener, requestCh, errorCh)

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

func TestSpawnClaimCommandSendsTokenAndTTY(t *testing.T) {
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

	requestCh := make(chan protocol.SpawnClaimRequest, 1)
	errorCh := make(chan error, 1)
	go serveOneRequest(listener, requestCh, errorCh)

	cmd := newRootCmd()
	cmd.SetArgs([]string{"spawn-claim", "token-1"})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}

	request := <-requestCh
	if request.Command != "spawn-claim" {
		t.Fatalf("request.Command = %q, want spawn-claim", request.Command)
	}
	if request.TTY != "/dev/ttys001" {
		t.Fatalf("request.TTY = %q, want /dev/ttys001", request.TTY)
	}
	if request.SpawnToken != "token-1" {
		t.Fatalf("request.SpawnToken = %q, want token-1", request.SpawnToken)
	}
	if err := <-errorCh; err != nil {
		t.Fatalf("server error = %v", err)
	}
}

func TestInputCommandSendsTextAndSubmit(t *testing.T) {
	testDir, err := os.MkdirTemp("/tmp", "gty-cli-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	defer func() { _ = os.RemoveAll(testDir) }()
	socketPath := filepath.Join(testDir, "d.sock")
	listener := testUnixListener(t, socketPath)
	defer func() { _ = listener.Close() }()
	t.Setenv("GTY_SOCK", socketPath)
	t.Setenv("GTY_TTY", "/dev/ttys002")

	requestCh := make(chan protocol.InputRequest, 1)
	errorCh := make(chan error, 1)
	go serveOneRequest(listener, requestCh, errorCh)

	cmd := newRootCmd()
	cmd.SetArgs([]string{"input", "--tty", "/dev/ttys001", "--submit", "--wait", "nvim", "."})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}

	request := <-requestCh
	if request.Command != "input" {
		t.Fatalf("request.Command = %q, want input", request.Command)
	}
	if request.TTY != "/dev/ttys001" {
		t.Fatalf("request.TTY = %q, want /dev/ttys001", request.TTY)
	}
	if request.Text != "nvim ." {
		t.Fatalf("request.Text = %q, want nvim .", request.Text)
	}
	if !request.Submit {
		t.Fatal("request.Submit = false, want true")
	}
	if !request.Ack {
		t.Fatal("request.Ack = false, want true")
	}
	if err := <-errorCh; err != nil {
		t.Fatalf("server error = %v", err)
	}
}

func serveOneRequest[T any](listener net.Listener, requestCh chan<- T, errorCh chan<- error) {
	conn, err := listener.Accept()
	if err != nil {
		errorCh <- err
		return
	}
	defer func() { _ = conn.Close() }()

	var request T
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
