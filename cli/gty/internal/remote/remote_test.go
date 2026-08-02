package remote

import (
	"archive/zip"
	"bytes"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
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

func TestControlSSHArgsRefuseATerminal(t *testing.T) {
	for _, sshOpts := range []SSHOptions{{}, {UnmanagedSSH: true}} {
		if indexOf(controlSSHArgs(sshOpts), "-T") == -1 {
			t.Fatalf("controlSSHArgs(%+v) = %v, want -T", sshOpts, controlSSHArgs(sshOpts))
		}
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

// TestRunCommandSurvivesEveryLoginShell runs the final SSH command the way sshd does, through the
// account's login shell, which is not required to parse POSIX syntax.
func TestRunCommandSurvivesEveryLoginShell(t *testing.T) {
	for _, shell := range loginShells(t) {
		t.Run(filepath.Base(shell), func(t *testing.T) {
			directory := t.TempDir()
			record := filepath.Join(directory, "argv")
			gty := writeScript(t, filepath.Join(directory, "gty"),
				"#!/bin/sh\nprintf '%s\\n' \"$GTY_SOCK\" \"$@\" > "+ShellQuote(record)+"\n")

			command := RunCommand(gty, "/tmp/gty-501/bridge-a b.sock", []string{"echo", "it's alive"})
			if output, err := exec.Command(shell, "-c", command).CombinedOutput(); err != nil {
				t.Fatalf("%s -c RunCommand() error = %v, output = %s", shell, err, output)
			}

			want := "/tmp/gty-501/bridge-a b.sock\nssh\nremote-run\n--\necho\nit's alive\n"
			if got := readFile(t, record); got != want {
				t.Fatalf("remote gty received %q, want %q", got, want)
			}
		})
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
	err = os.Mkdir(gtyDir, 0o700)
	if err != nil {
		t.Fatalf("Mkdir() error = %v", err)
	}

	dead := filepath.Join(gtyDir, "bridge-dead.sock")
	err = os.WriteFile(dead, nil, 0o600)
	if err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	live := filepath.Join(gtyDir, "bridge-live.sock")
	listener, err := net.Listen("unix", live)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	defer func() { _ = listener.Close() }()
	accepted := make(chan struct{})
	go acceptAndClose(listener, accepted)

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

func acceptAndClose(listener net.Listener, accepted chan<- struct{}) {
	conn, err := listener.Accept()
	if err == nil {
		_ = conn.Close()
	}
	close(accepted)
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

func TestRunPreparedSSHResetsTerminalOnlyForPtySessions(t *testing.T) {
	cases := []struct {
		name          string
		remoteCommand []string
		resets        int
	}{
		{name: "interactive session", remoteCommand: nil, resets: 1},
		{name: "remote command", remoteCommand: []string{"gty", "focus", "left"}, resets: 0},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			resets := 0
			runner := Runner{
				RunInteractiveCommand: func(_ string, _ ...string) error { return errors.New("connection timed out") },
				ResetTerminal:         func() error { resets++; return nil },
			}
			err := runner.RunPreparedSSH(SSHOptions{}, "host", testCase.remoteCommand, PreparedBridge{
				RemoteGTY:        "/remote/gty",
				RemoteSocketPath: "/remote.sock",
				LocalBridgePath:  "/local.sock",
			})
			if err == nil {
				t.Fatal("RunPreparedSSH() error = nil, want ssh failure")
			}
			if resets != testCase.resets {
				t.Fatalf("ResetTerminal calls = %d, want %d", resets, testCase.resets)
			}
		})
	}
}

// TestGTYCandidatesScriptReportsUsableInstalls runs the remote lookup script for real, since its
// quoting, XDG default, and exit-status handling only exist inside the shell.
func TestGTYCandidatesScriptReportsUsableInstalls(t *testing.T) {
	home := t.TempDir()
	managed := filepath.Join(home, ".local/share/ghosttykit/bin/gty")
	pathDirectory := filepath.Join(home, "path bin")
	if err := os.MkdirAll(filepath.Dir(managed), 0o755); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.MkdirAll(pathDirectory, 0o755); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	writeScript(t, managed, "#!/bin/sh\necho 'gty 1.2.3 protocol=1'\n")

	cases := []struct {
		name       string
		pathGTY    string
		candidates []remoteGTY
	}{
		{
			name:       "managed install only",
			candidates: []remoteGTY{{Path: managed, Version: "gty 1.2.3 protocol=1"}},
		},
		{
			name:    "path install first",
			pathGTY: "#!/bin/sh\necho 'gty 1.2.3 protocol=1'\n",
			candidates: []remoteGTY{
				{Path: filepath.Join(pathDirectory, "gty"), Version: "gty 1.2.3 protocol=1"},
				{Path: managed, Version: "gty 1.2.3 protocol=1"},
			},
		},
		{
			name:       "failing path install is skipped",
			pathGTY:    "#!/bin/sh\necho 'gty 1.2.3 protocol=1'\nexit 1\n",
			candidates: []remoteGTY{{Path: managed, Version: "gty 1.2.3 protocol=1"}},
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			path := filepath.Join(pathDirectory, "gty")
			if testCase.pathGTY == "" {
				if err := os.RemoveAll(path); err != nil {
					t.Fatalf("RemoveAll() error = %v", err)
				}
			} else {
				writeScript(t, path, testCase.pathGTY)
			}

			got := parseGTYCandidates(runRemoteScript(t, home, pathDirectory, gtyCandidatesScript, nil))
			if !slices.Equal(got, testCase.candidates) {
				t.Fatalf("candidates = %v, want %v", got, testCase.candidates)
			}
		})
	}
}

// TestManagedInstallScriptStagesThenRenames pins the install contract: nothing is left behind, and
// the binary arrives executable at the XDG location.
func TestManagedInstallScriptStagesThenRenames(t *testing.T) {
	home := t.TempDir()
	runRemoteScript(t, home, os.Getenv("PATH"), managedInstallScript, strings.NewReader("#!/bin/sh\necho installed\n"))

	managed := filepath.Join(home, ".local/share/ghosttykit/bin/gty")
	info, err := os.Stat(managed)
	if err != nil {
		t.Fatalf("Stat(managed) error = %v", err)
	}
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("managed install mode = %v, want 0755", info.Mode().Perm())
	}
	if got := readFile(t, managed); got != "#!/bin/sh\necho installed\n" {
		t.Fatalf("managed install = %q, want the uploaded binary", got)
	}

	entries, err := os.ReadDir(filepath.Dir(managed))
	if err != nil {
		t.Fatalf("ReadDir() error = %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("install directory = %v, want only gty", entries)
	}
}

func TestDefaultBootstrapSourceFollowsBuildProvenance(t *testing.T) {
	sourceRoot, releaseTag := SourceRoot, ReleaseTag
	t.Cleanup(func() { SourceRoot, ReleaseTag = sourceRoot, releaseTag })

	SourceRoot, ReleaseTag = "/checkout", ""
	if source, ok := DefaultBootstrapSource(nil).(LocalBuildBootstrapSource); !ok || source.SourceRoot != "/checkout" {
		t.Fatalf("DefaultBootstrapSource(source build) = %#v, want the checkout", DefaultBootstrapSource(nil))
	}

	SourceRoot, ReleaseTag = "", "v1.2.3"
	if source, ok := DefaultBootstrapSource(nil).(ReleaseDownloadBootstrapSource); !ok || source.Tag != "v1.2.3" {
		t.Fatalf("DefaultBootstrapSource(release build) = %#v, want the release tag", DefaultBootstrapSource(nil))
	}

	SourceRoot, ReleaseTag = "/checkout", "v1.2.3"
	if _, ok := DefaultBootstrapSource(nil).(LocalBuildBootstrapSource); !ok {
		t.Fatalf("DefaultBootstrapSource(source build of a release) = %T, want LocalBuildBootstrapSource", DefaultBootstrapSource(nil))
	}

	SourceRoot, ReleaseTag = "", ""
	if source, ok := DefaultBootstrapSource(nil).(LocalBuildBootstrapSource); !ok || source.SourceRoot != "" {
		t.Fatalf("DefaultBootstrapSource(unstamped build) = %#v, want a rootless local build", DefaultBootstrapSource(nil))
	}
}

// TestUnstampedBuildBootstrapsOnlyMatchingHosts keeps a bare `go build` usable against hosts it can
// serve by copying itself, and explicit about the ones it cannot.
func TestUnstampedBuildBootstrapsOnlyMatchingHosts(t *testing.T) {
	source := LocalBuildBootstrapSource{Executable: "/proc/self/exe"}
	path, _, err := source.BinaryFor(Target{GOOS: runtime.GOOS, GOARCH: runtime.GOARCH})
	if err != nil || path != "/proc/self/exe" {
		t.Fatalf("BinaryFor(matching target) = %q, %v, want the current executable", path, err)
	}

	_, _, err = source.BinaryFor(Target{GOOS: "plan9", GOARCH: "mips"})
	if err == nil || !strings.Contains(err.Error(), "just build-go") {
		t.Fatalf("BinaryFor(cross target) error = %v, want rebuild guidance", err)
	}
}

func TestReleaseDownloadBootstrapSourceExtractsGTYAndReportsProgress(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1.2.3/ghosttykit_1.2.3_linux_amd64.zip" {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(releaseArchive(t, "#!/bin/sh\necho bootstrapped\n"))
	}))
	t.Cleanup(server.Close)

	progress := &bytes.Buffer{}
	source := ReleaseDownloadBootstrapSource{BaseURL: server.URL, Tag: "v1.2.3", Version: "1.2.3", Progress: progress}
	path, cleanup, err := source.BinaryFor(Target{GOOS: "linux", GOARCH: "amd64"})
	if err != nil {
		t.Fatalf("BinaryFor() error = %v", err)
	}
	t.Cleanup(cleanup)

	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	if !strings.Contains(string(contents), "echo bootstrapped") {
		t.Fatalf("extracted binary = %q, want the archived gty", contents)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("extracted binary mode = %v, want 0755", info.Mode().Perm())
	}
	if !strings.Contains(progress.String(), "downloading ghosttykit_1.2.3_linux_amd64.zip") {
		t.Fatalf("progress = %q, want a download notice", progress.String())
	}
}

func TestReleaseDownloadBootstrapSourceReportsMissingAsset(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	t.Cleanup(server.Close)

	source := ReleaseDownloadBootstrapSource{BaseURL: server.URL, Tag: "v1.2.3", Version: "1.2.3"}
	_, _, err := source.BinaryFor(Target{GOOS: "linux", GOARCH: "arm64"})
	if err == nil || !strings.Contains(err.Error(), "404") {
		t.Fatalf("BinaryFor() error = %v, want a 404 report", err)
	}
}

// TestReleaseDownloadBootstrapSourceRejectsForeignArchiveLayout guards the archive contract, so a
// stray file named gty cannot be installed in place of the release binary.
func TestReleaseDownloadBootstrapSourceRejectsForeignArchiveLayout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(zipWithEntry(t, "ghosttykit_1.2.3_linux_amd64/docs/gty", "not the binary"))
	}))
	t.Cleanup(server.Close)

	source := ReleaseDownloadBootstrapSource{BaseURL: server.URL, Tag: "v1.2.3", Version: "1.2.3"}
	_, _, err := source.BinaryFor(Target{GOOS: "linux", GOARCH: "amd64"})
	if err == nil || !strings.Contains(err.Error(), "ghosttykit_1.2.3_linux_amd64/bin/gty") {
		t.Fatalf("BinaryFor() error = %v, want the expected archive entry named", err)
	}
}

func releaseArchive(t *testing.T, gty string) []byte {
	t.Helper()
	return zipWithEntry(t, "ghosttykit_1.2.3_linux_amd64/bin/gty", gty)
}

func zipWithEntry(t *testing.T, name string, contents string) []byte {
	t.Helper()
	buffer := &bytes.Buffer{}
	writer := zip.NewWriter(buffer)
	entry, err := writer.Create(name)
	if err != nil {
		t.Fatalf("zip Create() error = %v", err)
	}
	if _, err := entry.Write([]byte(contents)); err != nil {
		t.Fatalf("zip Write() error = %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("zip Close() error = %v", err)
	}
	return buffer.Bytes()
}

// runRemoteScript runs a bootstrap script the way sshd would, under a login shell that hands it to
// /bin/sh, against a throwaway HOME.
func runRemoteScript(t *testing.T, home string, path string, script string, stdin io.Reader) string {
	t.Helper()
	cmd := exec.Command("/bin/sh", "-c", posixShellCommand(script))
	cmd.Env = []string{"HOME=" + home, "PATH=" + path}
	cmd.Stdin = stdin
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("remote script error = %v", err)
	}
	return string(out)
}

func loginShells(t *testing.T) []string {
	t.Helper()
	shells := []string{"/bin/sh"}
	for _, candidate := range []string{"/bin/csh", "/bin/tcsh", "/opt/homebrew/bin/fish", "/usr/bin/fish"} {
		if _, err := os.Stat(candidate); err == nil {
			shells = append(shells, candidate)
		}
	}
	return shells
}

func writeScript(t *testing.T, path string, contents string) string {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o755); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	return string(contents)
}

type closerFunc func() error

func (f closerFunc) Close() error { return f() }
