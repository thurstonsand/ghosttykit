//go:build integration

package client

import (
	"bytes"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestIntegrationDryRunDaemonE2E(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("ghosttykitd is macOS-only")
	}

	repoRoot := repositoryRoot(t)
	daemonPath := buildDaemon(t, filepath.Join(repoRoot, "daemon", "ghosttykitd"))
	socketDir, err := os.MkdirTemp("/tmp", "gty-it-")
	if err != nil {
		t.Fatalf("create socket temp dir: %v", err)
	}
	defer func() { _ = os.RemoveAll(socketDir) }()
	socketPath := filepath.Join(socketDir, "d.sock")
	pasteText := "ghosttykit sdk integration paste\n"
	stopDaemon := startDryRunDaemon(t, daemonPath, socketPath, pasteText)
	defer stopDaemon()

	c := ForSocket(socketPath)

	doctorReply, err := Call[protocol.DoctorReply](c, protocol.NewDoctorRequest())
	if err != nil {
		t.Fatalf("doctor Call() error = %v", err)
	}
	if !doctorReply.Healthy {
		t.Fatalf("doctor healthy = false, checks = %#v", doctorReply.Checks)
	}

	tty := "/dev/ghosttykit-sdk-integration"
	terminalIDRequest := protocol.NewTerminalIDRequest(tty, true, true)
	reply, err := Call[protocol.FrameReply](c, terminalIDRequest)
	if err != nil {
		t.Fatalf("terminal-id Call() error = %v", err)
	}
	if got, want := reply.Value, "dry-run-terminal"; got != want {
		t.Fatalf("terminal-id value = %q, want %q", got, want)
	}

	tabTerminalCountRequest := protocol.NewTabTerminalCountRequest(tty, false)
	reply, err = Call[protocol.FrameReply](c, tabTerminalCountRequest)
	if err != nil {
		t.Fatalf("tab-terminal-count Call() error = %v", err)
	}
	if got, want := reply.Value, "1"; got != want {
		t.Fatalf("tab-terminal-count value = %q, want %q", got, want)
	}

	focusRequest := protocol.NewFocusRequest(tty, "left", false, true)
	reply, err = Call[protocol.FrameReply](c, focusRequest)
	if err != nil {
		t.Fatalf("ack focus Call() error = %v", err)
	}
	if got, want := reply.Code, protocol.CodeOK; got != want {
		t.Fatalf("ack focus code = %q, want %q", got, want)
	}

	notifyRequest := protocol.NewFocusRequest(tty, "right", false, false)
	if err := Notify(c, notifyRequest); err != nil {
		t.Fatalf("no-ack focus Notify() error = %v", err)
	}

	header, body, err := Stream[protocol.PasteStreamFrameHeader](
		c,
		protocol.NewPasteRequest(""),
	)
	if err != nil {
		t.Fatalf("paste Stream() error = %v", err)
	}
	defer func() { _ = body.Close() }()

	if got, want := header.Kind, protocol.PasteKindText; got != want {
		t.Fatalf("paste kind = %q, want %q", got, want)
	}
	if got, want := header.Bytes, int64(len(pasteText)); got != want {
		t.Fatalf("paste bytes = %d, want %d", got, want)
	}
	payload, err := io.ReadAll(body)
	if err != nil {
		t.Fatalf("read paste body error = %v", err)
	}
	if got := string(payload); got != pasteText {
		t.Fatalf("paste body = %q, want %q", got, pasteText)
	}
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate test file")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", ".."))
}

func buildDaemon(t *testing.T, daemonDir string) string {
	t.Helper()
	cmd := exec.Command("just", "build")
	cmd.Dir = daemonDir
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Run(); err != nil {
		t.Fatalf("build ghosttykitd: %v\n%s", err, output.String())
	}
	return filepath.Join(daemonDir, "ghosttykitd")
}

func startDryRunDaemon(t *testing.T, daemonPath, socketPath, pasteText string) func() {
	t.Helper()
	cmd := exec.Command(daemonPath, "--dry-run")
	cmd.Env = append(os.Environ(), "GTY_SOCK="+socketPath, "GTY_DRY_RUN_PASTE_TEXT="+pasteText)
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Start(); err != nil {
		t.Fatalf("start ghosttykitd: %v", err)
	}

	waitCh := make(chan error, 1)
	go func() { waitCh <- cmd.Wait() }()

	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		_ = cmd.Process.Kill()
		select {
		case <-waitCh:
		case <-time.After(5 * time.Second):
			t.Fatalf("ghosttykitd did not exit after kill\n%s", output.String())
		}
		_ = os.Remove(socketPath)
	}

	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case err := <-waitCh:
			stopped = true
			t.Fatalf("ghosttykitd exited before accepting connections: %v\n%s", err, output.String())
		default:
		}

		conn, err := net.DialTimeout("unix", socketPath, 100*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return stop
		}
		time.Sleep(50 * time.Millisecond)
	}

	stop()
	t.Fatalf("ghosttykitd did not create a usable socket at %s\n%s", socketPath, output.String())
	return func() {}
}
