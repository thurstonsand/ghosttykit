// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// SSHOptions configures gty ssh behavior.
type SSHOptions struct {
	RequireBridge bool
	UnmanagedSSH  bool
	NoBootstrap   bool
}

// SplitSSHArgs separates the SSH host from an optional remote command.
func SplitSSHArgs(args []string, dashIndex int) (string, []string, error) {
	if len(args) == 0 {
		return "", nil, errors.New("missing host")
	}
	if dashIndex == -1 {
		if len(args) != 1 {
			return "", nil, errors.New("remote command must follow --")
		}
		return args[0], nil, nil
	}
	if dashIndex != 1 {
		return "", nil, errors.New("gty ssh accepts exactly one host before --")
	}
	return args[0], args[1:], nil
}

// ManagedSSHArgs returns OpenSSH options owned by GhosttyKit.
func ManagedSSHArgs(sshOpts SSHOptions) []string {
	if sshOpts.UnmanagedSSH {
		return nil
	}
	options := []string{
		"ExitOnForwardFailure=yes",
		"StreamLocalBindUnlink=yes",
		"StreamLocalBindMask=0177",
		"ServerAliveInterval=15",
		"ServerAliveCountMax=3",
		"ControlMaster=no",
		"ControlPath=none",
	}
	args := make([]string, 0, len(options)*2)
	for _, option := range options {
		args = append(args, "-o", option)
	}
	return args
}

// PlainSSHArgs returns arguments for a non-bridged SSH invocation.
func PlainSSHArgs(sshOpts SSHOptions, host string, remoteCommand []string) []string {
	args := ManagedSSHArgs(sshOpts)
	args = append(args, "--", host)
	args = append(args, remoteCommand...)
	return args
}

// controlSSHArgs configures GhosttyKit's own SSH commands. `-T` overrides a host configured with
// RequestTTY, whose pty would rewrite these machine-read replies with terminal echo and CRLF.
func controlSSHArgs(sshOpts SSHOptions) []string {
	args := ManagedSSHArgs(sshOpts)
	args = append(args, "-o", "ClearAllForwardings=yes", "-T")
	return args
}

func captureSSH(sshOpts SSHOptions, host string, script string) (string, error) {
	args := controlSSHArgs(sshOpts)
	args = append(args, "--", host, posixShellCommand(script))
	cmd := exec.Command("ssh", args...)
	out, err := cmd.Output()
	if err != nil {
		exitErr, ok := errors.AsType[*exec.ExitError](err)
		if ok && len(exitErr.Stderr) > 0 {
			return "", fmt.Errorf("ssh %s: %s", host, strings.TrimSpace(string(exitErr.Stderr)))
		}
		return "", err
	}
	return string(out), nil
}
