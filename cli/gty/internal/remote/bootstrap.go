// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

// GTYLookup selects which remote gty locations are accepted.
type GTYLookup int

// Remote gty lookup modes.
const (
	GTYLookupAny GTYLookup = iota
	GTYLookupManagedInstall
)

// Target identifies a remote Go build target.
type Target struct {
	GOOS   string
	GOARCH string
}

// BootstrapSource provides a gty binary for a remote target.
type BootstrapSource interface {
	BinaryFor(target Target) (path string, cleanup func(), err error)
}

// LocalBuildBootstrapSource uses the current executable or source checkout for bootstrap.
type LocalBuildBootstrapSource struct {
	Executable string
}

func ensureRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource) (string, error) {
	path, pathErr := remoteGTYPath(sshOpts, host, GTYLookupAny)
	if pathErr == nil && remoteGTYCompatible(sshOpts, host, path) {
		return path, nil
	}
	if sshOpts.NoBootstrap {
		if pathErr != nil {
			return "", errors.New("remote gty not found")
		}
		return "", fmt.Errorf("remote gty version mismatch at %s", path)
	}
	if err := bootstrapRemoteGTY(sshOpts, host, source); err != nil {
		return "", err
	}
	return remoteGTYPath(sshOpts, host, GTYLookupManagedInstall)
}

func remoteGTYPath(sshOpts SSHOptions, host string, lookup GTYLookup) (string, error) {
	command := "command -v gty || { test -x ~/.local/bin/gty && printf %s ~/.local/bin/gty; }"
	missingMessage := "remote gty not found"
	if lookup == GTYLookupManagedInstall {
		command = "test -x ~/.local/bin/gty && printf %s ~/.local/bin/gty"
		missingMessage = "bootstrapped remote gty not found"
	}
	out, err := captureSSH(sshOpts, host, command)
	if err != nil {
		return "", err
	}
	path := strings.TrimSpace(out)
	if path == "" {
		return "", errors.New(missingMessage)
	}
	return path, nil
}

func remoteGTYCompatible(sshOpts SSHOptions, host string, path string) bool {
	out, err := captureSSH(sshOpts, host, ShellQuote(path)+" version")
	return err == nil && strings.TrimSpace(out) == localVersionLine()
}

func localVersionLine() string {
	return fmt.Sprintf("gty %s protocol=%d", ghosttykit.Version, ghosttykit.ProtocolVersion)
}

func bootstrapRemoteGTY(sshOpts SSHOptions, host string, source BootstrapSource) error {
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
	args := controlSSHArgs(sshOpts)
	args = append(args, "--", host, "mkdir -p ~/.local/bin && cat > ~/.local/bin/gty && chmod 755 ~/.local/bin/gty")
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
	executable := s.Executable
	if executable == "" {
		var err error
		executable, err = os.Executable()
		if err != nil {
			return "", nil, fmt.Errorf("locate local gty: %w", err)
		}
	}
	if target.GOOS == runtime.GOOS && target.GOARCH == runtime.GOARCH {
		return executable, nil, nil
	}
	built, err := s.build(target, filepath.Dir(executable))
	if err != nil {
		return "", nil, err
	}
	return built, func() { _ = os.Remove(built) }, nil
}

func (s LocalBuildBootstrapSource) build(target Target, sourceDir string) (string, error) {
	if _, err := os.Stat(filepath.Join(sourceDir, "go.mod")); err != nil {
		return "", fmt.Errorf("cross-platform bootstrap requires gty source next to the executable: %w", err)
	}
	output, err := os.CreateTemp("", "gty-bootstrap-*")
	if err != nil {
		return "", err
	}
	path := output.Name()
	_ = output.Close()
	cmd := exec.Command("go", "build", "-o", path, ".")
	cmd.Dir = sourceDir
	cmd.Env = append(os.Environ(), "GOOS="+target.GOOS, "GOARCH="+target.GOARCH)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("build %s/%s bootstrap gty: %w", target.GOOS, target.GOARCH, err)
	}
	return path, nil
}
