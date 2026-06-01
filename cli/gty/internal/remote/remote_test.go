package remote

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManagedSSHArgs(t *testing.T) {
	args := ManagedSSHArgs(SSHOptions{})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"ExitOnForwardFailure=yes",
		"StreamLocalBindUnlink=yes",
		"StreamLocalBindMask=0177",
		"ServerAliveInterval=15",
		"ServerAliveCountMax=3",
		"ControlMaster=no",
		"ControlPath=none",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("ManagedSSHArgs() missing %q in %q", want, joined)
		}
	}
	if got := ManagedSSHArgs(SSHOptions{UnmanagedSSH: true}); len(got) != 0 {
		t.Fatalf("ManagedSSHArgs(unmanaged) = %v, want empty", got)
	}
}

func TestSplitSSHArgsRequiresDelimiterBeforeRemoteCommand(t *testing.T) {
	_, _, err := SplitSSHArgs([]string{"openclaw", "gty", "doctor"}, -1)
	if err == nil {
		t.Fatal("SplitSSHArgs() error = nil, want usage error")
	}

	host, remoteCommand, err := SplitSSHArgs([]string{"openclaw", "gty", "doctor"}, 1)
	if err != nil {
		t.Fatalf("SplitSSHArgs() error = %v", err)
	}
	if host != "openclaw" {
		t.Fatalf("host = %q, want openclaw", host)
	}
	if got, want := strings.Join(remoteCommand, " "), "gty doctor"; got != want {
		t.Fatalf("remote command = %q, want %q", got, want)
	}
}

func TestPlainSSHArgsSeparatesHostFromOptions(t *testing.T) {
	args := PlainSSHArgs(SSHOptions{}, "-oProxyCommand=touch /tmp/pwned", []string{"echo", "ok"})
	dashDash := indexOf(args, "--")
	host := indexOf(args, "-oProxyCommand=touch /tmp/pwned")
	if dashDash < 0 || host < 0 || dashDash > host {
		t.Fatalf("PlainSSHArgs() = %v, want -- before host", args)
	}
}

func indexOf(values []string, target string) int {
	for index, value := range values {
		if value == target {
			return index
		}
	}
	return -1
}

func TestRunCommandQuotesSocketAndArgs(t *testing.T) {
	got := RunCommand("/home/me/bin/gty", "/tmp/gty-501/bridge-a b.sock", []string{"echo", "it's alive"})
	want := "GTY_SOCK='/tmp/gty-501/bridge-a b.sock' '/home/me/bin/gty' ssh remote-run -- 'echo' 'it'\\''s alive'"
	if got != want {
		t.Fatalf("RunCommand() = %q, want %q", got, want)
	}
}

func TestPrepareRuntimeRemovesDeadSocketsAndPreservesLiveSockets(t *testing.T) {
	runtimeDir, err := os.MkdirTemp("/tmp", "gty-test-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	defer func() { _ = os.RemoveAll(runtimeDir) }()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	gtyDir := filepath.Join(runtimeDir, "gty")
	if err := os.Mkdir(gtyDir, 0o700); err != nil {
		t.Fatalf("Mkdir() error = %v", err)
	}

	dead := filepath.Join(gtyDir, "bridge-dead.sock")
	if err := os.WriteFile(dead, nil, 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	live := filepath.Join(gtyDir, "bridge-live.sock")
	listener, err := net.Listen("unix", live)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	defer func() { _ = listener.Close() }()
	accepted := make(chan struct{})
	go func() {
		conn, err := listener.Accept()
		if err == nil {
			_ = conn.Close()
		}
		close(accepted)
	}()

	result, err := PrepareRuntime()
	if err != nil {
		t.Fatalf("PrepareRuntime() error = %v", err)
	}
	if result.RuntimeDir != gtyDir {
		t.Fatalf("RuntimeDir = %q, want %q", result.RuntimeDir, gtyDir)
	}
	if !strings.HasPrefix(result.SocketPath, filepath.Join(gtyDir, "bridge-")) || !strings.HasSuffix(result.SocketPath, ".sock") {
		t.Fatalf("SocketPath = %q, want bridge socket under runtime dir", result.SocketPath)
	}
	if _, err := os.Stat(dead); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("dead socket stat error = %v, want not exist", err)
	}
	if _, err := os.Stat(live); err != nil {
		t.Fatalf("live socket stat error = %v, want preserved", err)
	}
	<-accepted
}

func TestRunCleansSocketAndPreservesExitStatus(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "bridge-test.sock")
	if err := os.WriteFile(socketPath, nil, 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	t.Setenv("GTY_SOCK", socketPath)

	err := Run([]string{"/bin/sh", "-c", "exit 7"}, RunOptions{})
	if err == nil {
		t.Fatal("Run() error = nil, want exit status")
	}
	cliErr, ok := err.(interface{ ExitCode() int })
	if !ok {
		t.Fatalf("Run() error = %T, want ExitCode", err)
	}
	if got, want := cliErr.ExitCode(), 7; got != want {
		t.Fatalf("ExitCode() = %d, want %d", got, want)
	}
	if _, err := os.Stat(socketPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket stat error = %v, want removed", err)
	}
}

func TestRunSSHDoesNotFallbackAfterPreparedSessionStarts(t *testing.T) {
	calls := 0
	runner := Runner{
		CreateBridge: func() (Bridge, error) {
			return Bridge{SocketPath: "/local.sock", Lease: closerFunc(func() error { return nil })}, nil
		},
		RunInteractiveCommand: func(_ string, _ ...string) error {
			calls++
			return nil
		},
	}
	err := runner.RunPreparedSSH(SSHOptions{}, "host", []string{"sh", "-c", "exit 255"}, PreparedBridge{
		RemoteGTY:        "/remote/gty",
		RemoteSocketPath: "/remote.sock",
		LocalBridgePath:  "/local.sock",
	})
	if err != nil {
		t.Fatalf("RunPreparedSSH() error = %v", err)
	}
	if calls != 1 {
		t.Fatalf("RunCommand calls = %d, want 1", calls)
	}
}

type closerFunc func() error

func (f closerFunc) Close() error { return f() }
