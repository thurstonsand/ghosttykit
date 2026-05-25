// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"syscall"
)

// RunOptions configures remote command execution.
type RunOptions struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
	Env    []string
}

// Run executes the remote-run helper under GTY_SOCK.
func Run(args []string, opts RunOptions) error {
	socketPath := os.Getenv("GTY_SOCK")
	if socketPath == "" {
		return errors.New("GTY_SOCK is required")
	}
	defer func() { _ = os.Remove(socketPath) }()

	name, childArgs := child(args)
	cmd := exec.Command(name, childArgs...)
	cmd.Stdin = opts.Stdin
	if cmd.Stdin == nil {
		cmd.Stdin = os.Stdin
	}
	cmd.Stdout = opts.Stdout
	if cmd.Stdout == nil {
		cmd.Stdout = os.Stdout
	}
	cmd.Stderr = opts.Stderr
	if cmd.Stderr == nil {
		cmd.Stderr = os.Stderr
	}
	cmd.Env = opts.Env
	if cmd.Env == nil {
		cmd.Env = os.Environ()
	}
	if err := cmd.Run(); err != nil {
		return exitStatusFromError(err)
	}
	return nil
}

func child(args []string) (string, []string) {
	if len(args) > 0 {
		return args[0], args[1:]
	}
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}
	return shell, []string{"-l"}
}

// ExitStatusError preserves a child process exit code.
type ExitStatusError struct {
	Code int
	Err  error
}

func (e ExitStatusError) Error() string { return e.Err.Error() }
func (e ExitStatusError) Unwrap() error { return e.Err }

// ExitCode returns the child process exit code.
func (e ExitStatusError) ExitCode() int { return e.Code }

func exitStatusFromError(err error) error {
	if code, ok := execExitCodeOK(err); ok {
		return ExitStatusError{Code: code, Err: err}
	}
	return err
}

func execExitCodeOK(err error) (int, bool) {
	exitErr, ok := errors.AsType[*exec.ExitError](err)
	if !ok {
		return 0, false
	}
	status, ok := exitErr.Sys().(syscall.WaitStatus)
	if !ok {
		return 0, false
	}
	return status.ExitStatus(), true
}
