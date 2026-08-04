// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"archive/zip"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

// SourceRoot is the checkout path stamped into builds made from a source checkout.
var SourceRoot = ""

// ReleaseTag is the release tag stamped into release builds.
var ReleaseTag = ""

// managedInstallShellVar assigns the bootstrap install path, and prefixes every script below.
const managedInstallShellVar = `gty_managed="${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty"
`

// gtyCandidatesScript prints every usable remote gty as a path and version line pair, preferring
// the host owner's own install over the one bootstrap manages.
const gtyCandidatesScript = managedInstallShellVar + `for candidate in "$(command -v gty || true)" "$gty_managed"; do
	[ -n "$candidate" ] && [ -x "$candidate" ] || continue
	version="$("$candidate" version 2>/dev/null)" || continue
	printf '%s\t%s\n' "$candidate" "$version"
done`

// managedGTYScript prints the bootstrap install and the version line it reports, leaving the
// version empty when that path holds nothing runnable.
const managedGTYScript = managedInstallShellVar + `version="$("$gty_managed" version 2>/dev/null || true)"
printf '%s\t%s\n' "$gty_managed" "$version"`

// managedInstallScript writes stdin to the bootstrap install path. The unique temporary sibling
// keeps concurrent sessions from sharing a half-written file, and the rename replaces a remote
// gty that is currently executing instead of overwriting it.
const managedInstallScript = managedInstallShellVar + `directory="$(dirname "$gty_managed")"
mkdir -p "$directory" || exit 1
staged="$(mktemp "$directory/gty.XXXXXX")" || exit 1
trap 'rm -f "$staged"' EXIT INT TERM
cat > "$staged" || exit 1
chmod 755 "$staged" || exit 1
mv -f "$staged" "$gty_managed"`

// remoteGTY is a remote gty binary and the version line it reports.
type remoteGTY struct {
	Path    string
	Version string
}

// Target identifies a remote Go build target.
type Target struct {
	GOOS   string
	GOARCH string
}

// BootstrapSource provides a gty binary for a remote target.
type BootstrapSource interface {
	BinaryFor(target Target) (path string, cleanup func(), err error)
}

// LocalBuildBootstrapSource copies the current executable or builds one from a source checkout.
type LocalBuildBootstrapSource struct {
	SourceRoot string
	Executable string
	Progress   io.Writer
}

// ReleaseDownloadBootstrapSource downloads the release asset matching this executable.
type ReleaseDownloadBootstrapSource struct {
	BaseURL  string
	Tag      string
	Version  string
	Progress io.Writer
}

const releaseDownloadBaseURL = "https://github.com/thurstonsand/ghosttykit/releases/download"

// DefaultBootstrapSource selects the bootstrap source matching how this gty was built. A build
// carrying neither stamp, such as a bare go build, can still copy itself to a matching host.
func DefaultBootstrapSource(progress io.Writer) BootstrapSource {
	if SourceRoot != "" {
		return LocalBuildBootstrapSource{SourceRoot: SourceRoot, Progress: progress}
	}
	if tag := releaseTag(); tag != "" {
		return ReleaseDownloadBootstrapSource{Tag: tag, Version: ghosttykit.Version, Progress: progress}
	}
	return LocalBuildBootstrapSource{Progress: progress}
}

// releaseTag reports the release holding assets this gty can bootstrap from, whether it was built
// by the release pipeline or installed with `go install <module>@vX.Y.Z`.
func releaseTag() string {
	if ReleaseTag != "" {
		return ReleaseTag
	}
	tag, _ := ghosttykit.ModuleReleaseTag()
	return tag
}

func ensureRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource, progress io.Writer) (string, error) {
	candidates, err := remoteGTYCandidates(sshOpts, host)
	if err != nil {
		return "", err
	}
	if path := compatibleGTY(candidates); path != "" {
		return path, nil
	}
	if sshOpts.NoBootstrap {
		if len(candidates) == 0 {
			return "", errors.New("remote gty not found")
		}
		return "", fmt.Errorf("remote gty version mismatch at %s: %s", candidates[0].Path, candidates[0].Version)
	}
	return installManagedRemoteGTY(sshOpts, host, source, progress)
}

// ensureManagedRemoteGTY guarantees this version at the one remote path a caller can name ahead
// of time, whatever else the host has on PATH.
func ensureManagedRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource, progress io.Writer) (string, error) {
	managed, err := managedGTY(sshOpts, host)
	if err != nil {
		return "", err
	}
	if managed.Version == localVersionLine() {
		return managed.Path, nil
	}
	if sshOpts.NoBootstrap {
		return "", fmt.Errorf("managed remote gty at %s reports %s, want %q", managed.Path, describeVersion(managed.Version), localVersionLine())
	}
	return installManagedRemoteGTY(sshOpts, host, source, progress)
}

func installManagedRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource, progress io.Writer) (string, error) {
	if err := bootstrapRemoteGTY(sshOpts, host, source, progress); err != nil {
		return "", err
	}
	installed, err := managedGTY(sshOpts, host)
	if err != nil {
		return "", fmt.Errorf("verify bootstrapped remote gty: %w", err)
	}
	if installed.Version != localVersionLine() {
		return "", fmt.Errorf("bootstrapped remote gty reports %s, want %q", describeVersion(installed.Version), localVersionLine())
	}
	return installed.Path, nil
}

func describeVersion(version string) string {
	if version == "" {
		return "nothing runnable"
	}
	return strconv.Quote(version)
}

func remoteGTYCandidates(sshOpts SSHOptions, host string) ([]remoteGTY, error) {
	out, err := captureSSH(sshOpts, host, gtyCandidatesScript)
	if err != nil {
		return nil, err
	}
	return parseGTYCandidates(out), nil
}

func parseGTYCandidates(out string) []remoteGTY {
	var candidates []remoteGTY
	for line := range strings.Lines(out) {
		path, version, found := strings.Cut(strings.TrimRight(line, "\n"), "\t")
		if !found || path == "" {
			continue
		}
		candidates = append(candidates, remoteGTY{Path: path, Version: version})
	}
	return candidates
}

func compatibleGTY(candidates []remoteGTY) string {
	for _, candidate := range candidates {
		if candidate.Version == localVersionLine() {
			return candidate.Path
		}
	}
	return ""
}

func managedGTY(sshOpts SSHOptions, host string) (remoteGTY, error) {
	out, err := captureSSH(sshOpts, host, managedGTYScript)
	if err != nil {
		return remoteGTY{}, err
	}
	installed := parseGTYCandidates(out)
	if len(installed) != 1 {
		return remoteGTY{}, fmt.Errorf("unexpected bootstrapped remote gty report: %q", strings.TrimSpace(out))
	}
	return installed[0], nil
}

func localVersionLine() string {
	return fmt.Sprintf("gty %s protocol=%d", ghosttykit.Version, ghosttykit.ProtocolVersion)
}

func bootstrapRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource, progress io.Writer) error {
	target, err := GoTarget(sshOpts, host)
	if err != nil {
		return err
	}
	executable, cleanup, err := source.BinaryFor(target)
	if cleanup != nil {
		defer cleanup()
	}
	if err != nil {
		return err
	}
	file, err := os.Open(executable)
	if err != nil {
		return fmt.Errorf("open bootstrap gty: %w", err)
	}
	defer func() { _ = file.Close() }()
	reportProgress(progress, "gty: installing gty on %s", host)
	args := controlSSHArgs(sshOpts)
	args = append(args, "--", host, posixShellCommand(managedInstallScript))
	cmd := exec.Command("ssh", args...)
	cmd.Stdin = file
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("copy gty to remote: %w", err)
	}
	return nil
}

// BinaryFor returns a local gty binary compatible with target.
func (s LocalBuildBootstrapSource) BinaryFor(target Target) (string, func(), error) {
	if target.GOOS == runtime.GOOS && target.GOARCH == runtime.GOARCH {
		if s.Executable != "" {
			return s.Executable, nil, nil
		}
		executable, err := os.Executable()
		if err != nil {
			return "", nil, fmt.Errorf("locate local gty: %w", err)
		}
		return executable, nil, nil
	}
	built, err := s.build(target)
	if err != nil {
		return "", nil, err
	}
	return built, func() { _ = os.Remove(built) }, nil
}

func (s LocalBuildBootstrapSource) build(target Target) (string, error) {
	if s.SourceRoot == "" {
		return "", fmt.Errorf("this gty was built by neither a release nor `just build-go`, so it can only bootstrap a %s/%s host; rebuild with `just build-go` to bootstrap %s/%s",
			runtime.GOOS, runtime.GOARCH, target.GOOS, target.GOARCH)
	}
	packageDir := filepath.Join(s.SourceRoot, "cli", "gty")
	if _, err := os.Stat(packageDir); err != nil {
		return "", fmt.Errorf("gty source checkout is no longer at %s: %w", s.SourceRoot, err)
	}
	output, err := os.CreateTemp("", "gty-bootstrap-*")
	if err != nil {
		return "", err
	}
	path := output.Name()
	_ = output.Close()
	reportProgress(s.Progress, "gty: building %s/%s gty from %s", target.GOOS, target.GOARCH, s.SourceRoot)
	cmd := exec.Command("go", "build", "-o", path, ".")
	cmd.Dir = packageDir
	cmd.Env = append(os.Environ(), "GOOS="+target.GOOS, "GOARCH="+target.GOARCH)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("build %s/%s bootstrap gty: %w", target.GOOS, target.GOARCH, err)
	}
	return path, nil
}

// BinaryFor downloads the release asset holding a gty binary compatible with target.
func (s ReleaseDownloadBootstrapSource) BinaryFor(target Target) (string, func(), error) {
	asset := fmt.Sprintf("ghosttykit_%s_%s_%s.zip", s.Version, target.GOOS, target.GOARCH)
	archive, err := s.download(asset)
	if err != nil {
		return "", nil, err
	}
	defer func() { _ = os.Remove(archive) }()
	binary, err := extractGTY(archive, strings.TrimSuffix(asset, ".zip")+"/bin/gty")
	if err != nil {
		return "", nil, err
	}
	return binary, func() { _ = os.Remove(binary) }, nil
}

func (s ReleaseDownloadBootstrapSource) download(asset string) (string, error) {
	base := s.BaseURL
	if base == "" {
		base = releaseDownloadBaseURL
	}
	url := base + "/" + s.Tag + "/" + asset
	reportProgress(s.Progress, "gty: downloading %s", asset)
	client := &http.Client{Timeout: 5 * time.Minute}
	response, err := client.Get(url)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", asset, err)
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download %s: %s", asset, response.Status)
	}
	file, err := os.CreateTemp("", "gty-bootstrap-*.zip")
	if err != nil {
		return "", err
	}
	defer func() { _ = file.Close() }()
	tracker := &downloadProgress{total: response.ContentLength, progress: s.Progress}
	if _, err := io.Copy(file, io.TeeReader(response.Body, tracker)); err != nil {
		_ = os.Remove(file.Name())
		return "", fmt.Errorf("download %s: %w", asset, err)
	}
	tracker.finish()
	return file.Name(), nil
}

func extractGTY(archive string, entryName string) (string, error) {
	reader, err := zip.OpenReader(archive)
	if err != nil {
		return "", fmt.Errorf("read release archive: %w", err)
	}
	defer func() { _ = reader.Close() }()
	for _, entry := range reader.File {
		if entry.Name == entryName && !entry.FileInfo().IsDir() {
			return copyZipEntry(entry)
		}
	}
	return "", fmt.Errorf("release archive contains no %s", entryName)
}

func copyZipEntry(entry *zip.File) (string, error) {
	source, err := entry.Open()
	if err != nil {
		return "", fmt.Errorf("read gty from release archive: %w", err)
	}
	defer func() { _ = source.Close() }()
	output, err := os.CreateTemp("", "gty-bootstrap-*")
	if err != nil {
		return "", err
	}
	defer func() { _ = output.Close() }()
	if _, err := io.Copy(output, source); err != nil {
		_ = os.Remove(output.Name())
		return "", fmt.Errorf("read gty from release archive: %w", err)
	}
	if err := output.Chmod(0o755); err != nil {
		_ = os.Remove(output.Name())
		return "", err
	}
	return output.Name(), nil
}

// downloadProgress reports transfer progress on a single rewritten line.
type downloadProgress struct {
	total     int64
	written   int64
	reported  bool
	lastPrint time.Time
	progress  io.Writer
}

func (d *downloadProgress) Write(chunk []byte) (int, error) {
	d.written += int64(len(chunk))
	if time.Since(d.lastPrint) >= 250*time.Millisecond {
		d.lastPrint = time.Now()
		d.print("\r")
	}
	return len(chunk), nil
}

func (d *downloadProgress) finish() {
	if d.reported {
		d.print("\n")
	}
}

func (d *downloadProgress) print(terminator string) {
	if d.progress == nil {
		return
	}
	d.reported = true
	if d.total > 0 {
		_, _ = fmt.Fprintf(d.progress, "gty:   %.1f MiB of %.1f MiB (%d%%)%s",
			mib(d.written), mib(d.total), 100*d.written/d.total, terminator)
		return
	}
	_, _ = fmt.Fprintf(d.progress, "gty:   %.1f MiB%s", mib(d.written), terminator)
}

func mib(bytes int64) float64 {
	return float64(bytes) / (1 << 20)
}

func reportProgress(progress io.Writer, format string, args ...any) {
	if progress == nil {
		return
	}
	_, _ = fmt.Fprintf(progress, format+"\n", args...)
}
