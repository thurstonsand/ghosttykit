// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"fmt"
	"strings"
)

// GoTarget detects the remote Go build target.
func GoTarget(sshOpts SSHOptions, host string) (Target, error) {
	out, err := captureSSH(sshOpts, host, "uname -s; uname -m")
	if err != nil {
		return Target{}, err
	}
	fields := strings.Fields(out)
	if len(fields) < 2 {
		return Target{}, fmt.Errorf("unexpected remote uname output: %q", strings.TrimSpace(out))
	}
	goos, err := goOS(fields[0])
	if err != nil {
		return Target{}, err
	}
	goarch, err := goArch(fields[1])
	if err != nil {
		return Target{}, err
	}
	return Target{GOOS: goos, GOARCH: goarch}, nil
}

func goOS(value string) (string, error) {
	switch strings.ToLower(value) {
	case "darwin":
		return "darwin", nil
	case "linux":
		return "linux", nil
	default:
		return "", fmt.Errorf("unsupported remote OS %q", value)
	}
}

func goArch(value string) (string, error) {
	switch strings.ToLower(value) {
	case "aarch64", "arm64":
		return "arm64", nil
	case "x86_64", "amd64":
		return "amd64", nil
	default:
		return "", fmt.Errorf("unsupported remote architecture %q", value)
	}
}
