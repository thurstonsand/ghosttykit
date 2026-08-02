// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
)

// Runner orchestrates bridged SSH execution.
type Runner struct {
	CreateBridge          func() (Bridge, error)
	BootstrapSource       BootstrapSource
	RunInteractiveCommand func(name string, args ...string) error
	Stderr                io.Writer
}

// Bridge is a local daemon bridge and its lease.
type Bridge struct {
	SocketPath string
	Lease      io.Closer
}

// PreparedBridge contains local and remote bridge state for the final SSH session.
type PreparedBridge struct {
	RemoteGTY        string
	RemoteSocketPath string
	LocalBridgePath  string
	Lease            io.Closer
}

// RunSSH prepares a bridge and runs SSH, falling back only on preparation failure.
func (r Runner) RunSSH(sshOpts SSHOptions, args []string, dashIndex int) error {
	host, remoteCommand, err := SplitSSHArgs(args, dashIndex)
	if err != nil {
		return err
	}

	prepared, err := r.Prepare(sshOpts, host)
	if err != nil {
		unavailable := BridgeUnavailableError{Err: err}
		if sshOpts.RequireBridge {
			return unavailable
		}
		warnBridgeUnavailable(r.stderr(), unavailable)
		return r.runInteractiveCommand("ssh", PlainSSHArgs(sshOpts, host, remoteCommand)...)
	}
	defer func() { _ = prepared.Close() }()

	return r.RunPreparedSSH(sshOpts, host, remoteCommand, prepared)
}

// Prepare creates all local and remote bridge state before the final SSH session.
func (r Runner) Prepare(sshOpts SSHOptions, host string) (PreparedBridge, error) {
	remoteGTY, initResult, err := prepareRemote(sshOpts, host, r.bootstrapSource(), r.stderr())
	if err != nil {
		return PreparedBridge{}, err
	}
	if r.CreateBridge == nil {
		return PreparedBridge{}, errors.New("create bridge function is required")
	}
	bridge, err := r.CreateBridge()
	if err != nil {
		return PreparedBridge{}, err
	}
	return PreparedBridge{
		RemoteGTY:        remoteGTY,
		RemoteSocketPath: initResult.SocketPath,
		LocalBridgePath:  bridge.SocketPath,
		Lease:            bridge.Lease,
	}, nil
}

func prepareRemote(sshOpts SSHOptions, host string, source BootstrapSource, progress io.Writer) (string, InitResult, error) {
	remoteGTY, err := ensureRemoteGTY(sshOpts, host, source, progress)
	if err != nil {
		return "", InitResult{}, err
	}
	initResult, err := remoteInit(sshOpts, host, remoteGTY)
	if err != nil {
		return "", InitResult{}, err
	}
	return remoteGTY, initResult, nil
}

func remoteInit(sshOpts SSHOptions, host string, remoteGTY string) (InitResult, error) {
	var result InitResult
	out, err := captureSSH(sshOpts, host, ShellQuote(remoteGTY)+" ssh remote-init")
	if err != nil {
		return result, err
	}
	if err := decodeInitResult(out, &result); err != nil {
		return result, err
	}
	return result, nil
}

// RunPreparedSSH runs the final SSH session without soft fallback.
func (r Runner) RunPreparedSSH(sshOpts SSHOptions, host string, remoteCommand []string, prepared PreparedBridge) error {
	args := ManagedSSHArgs(sshOpts)
	if len(remoteCommand) == 0 {
		args = append(args, "-t")
	}
	args = append(args, "-R", prepared.RemoteSocketPath+":"+prepared.LocalBridgePath, "--", host)
	args = append(args, RunCommand(prepared.RemoteGTY, prepared.RemoteSocketPath, remoteCommand))
	return r.runInteractiveCommand("ssh", args...)
}

// Close releases the local bridge lease.
func (p PreparedBridge) Close() error {
	if p.Lease == nil {
		return nil
	}
	return p.Lease.Close()
}

func (r Runner) bootstrapSource() BootstrapSource {
	if r.BootstrapSource != nil {
		return r.BootstrapSource
	}
	return DefaultBootstrapSource(r.stderr())
}

func (r Runner) runInteractiveCommand(name string, args ...string) error {
	if r.RunInteractiveCommand != nil {
		return r.RunInteractiveCommand(name, args...)
	}
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (r Runner) stderr() io.Writer {
	if r.Stderr != nil {
		return r.Stderr
	}
	return os.Stderr
}

// BridgeUnavailableError marks setup failures eligible for soft fallback.
type BridgeUnavailableError struct {
	Err error
}

func (e BridgeUnavailableError) Error() string { return e.Err.Error() }
func (e BridgeUnavailableError) Unwrap() error { return e.Err }

func warnBridgeUnavailable(w io.Writer, err error) {
	_, _ = fmt.Fprintf(w, "gty: Ghostty bridge unavailable: %v\n", err)
	_, _ = fmt.Fprintln(w, "gty: continuing with plain SSH")
}
