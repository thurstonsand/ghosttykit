// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/osc"
)

// Runner orchestrates bridged SSH execution.
type Runner struct {
	CreateBridge          func() (Bridge, error)
	BootstrapSource       BootstrapSource
	RunInteractiveCommand func(name string, args ...string) error
	ResetTerminal         func() error
	Stderr                io.Writer
	Session               SessionOptions
}

// SessionOptions are transport behaviors one caller can require of its SSH session. gty ssh
// leaves them unset; gty herdr attach needs a remote pty around its remote command, an stdout it
// can filter, a remote gty at the path Herdr's keybindings name, and signals delivered to OpenSSH
// so its own cleanup runs before this process exits.
type SessionOptions struct {
	ForcePTY          bool
	RequireManagedGTY bool
	Stdout            io.Writer
	ForwardSignals    []os.Signal
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
		return r.runSSHSession(len(remoteCommand) == 0, PlainSSHArgs(sshOpts, host, remoteCommand))
	}
	defer func() { _ = prepared.Close() }()

	return r.RunPreparedSSH(sshOpts, host, remoteCommand, prepared)
}

// Prepare creates all local and remote bridge state before the final SSH session.
func (r Runner) Prepare(sshOpts SSHOptions, host string) (PreparedBridge, error) {
	remoteGTY, initResult, err := prepareRemote(sshOpts, r.Session.RequireManagedGTY, host, r.bootstrapSource(), r.stderr())
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

func prepareRemote(sshOpts SSHOptions, requireManagedGTY bool, host string, source BootstrapSource, progress io.Writer) (string, InitResult, error) {
	var remoteGTY string
	var err error
	if requireManagedGTY {
		remoteGTY, err = ensureManagedRemoteGTY(sshOpts, host, source, progress)
	} else {
		remoteGTY, err = ensureRemoteGTY(sshOpts, host, source, progress)
	}
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
	usePTY := len(remoteCommand) == 0 || r.Session.ForcePTY
	args := ManagedSSHArgs(sshOpts)
	if usePTY {
		args = append(args, "-t")
	}
	args = append(args, "-R", prepared.RemoteSocketPath+":"+prepared.LocalBridgePath, "--", host)
	args = append(args, RunCommand(prepared.RemoteGTY, prepared.RemoteSocketPath, remoteCommand))
	return r.runSSHSession(usePTY, args)
}

// runSSHSession runs SSH and, for sessions that carried a remote pty, unwinds terminal modes a
// remote full-screen application may have left set when the connection died under it.
func (r Runner) runSSHSession(usePTY bool, args []string) error {
	err := r.runInteractiveCommand("ssh", args...)
	if usePTY {
		_ = r.resetTerminal()
	}
	return err
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
	if r.Session.Stdout != nil {
		cmd.Stdout = r.Session.Stdout
	}
	cmd.Stderr = os.Stderr
	if len(r.Session.ForwardSignals) == 0 {
		return cmd.Run()
	}
	return runForwardingSignals(cmd, r.Session.ForwardSignals)
}

// runForwardingSignals hands signals to the SSH child instead of letting them end this process,
// so the caller's own cleanup still runs once OpenSSH is gone.
func runForwardingSignals(cmd *exec.Cmd, signals []os.Signal) error {
	// Notified before the child exists: a signal arriving in the start window must not end this
	// process with its default disposition and skip the caller's cleanup.
	received := make(chan os.Signal, 1)
	signal.Notify(received, signals...)
	defer signal.Stop(received)
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			select {
			case incoming := <-received:
				_ = cmd.Process.Signal(incoming)
			case <-done:
				return
			}
		}
	}()
	return cmd.Wait()
}

func (r Runner) resetTerminal() error {
	if r.ResetTerminal != nil {
		return r.ResetTerminal()
	}
	return osc.ResetInteractiveModes()
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
