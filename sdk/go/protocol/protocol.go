// Package protocol defines the GhosttyKit JSON contract.
package protocol

import (
	"errors"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

const (
	// CodeOK means the request succeeded.
	CodeOK = "ok"
	// CodeProtocolVersionMismatch means the request protocol version is unsupported.
	CodeProtocolVersionMismatch = "protocol_version_mismatch"
	// CodeUnknownCommand means the request command is not recognized.
	CodeUnknownCommand = "unknown_command"
	// CodeInvalidRequest means the request shape or field value is invalid.
	CodeInvalidRequest = "invalid_request"
	// CodeTerminalNotFound means no Ghostty terminal matches the request target.
	CodeTerminalNotFound = "terminal_not_found"
	// CodeGhosttyUnavailable means Ghostty cannot be reached or controlled.
	CodeGhosttyUnavailable = "ghostty_unavailable"
	// CodePasteEmpty means the clipboard has no supported paste content.
	CodePasteEmpty = "paste_empty"
	// CodePasteUnsupported means clipboard content exists but has no supported representation.
	CodePasteUnsupported = "paste_unsupported"
	// CodeStreamFailed means streamed content could not be sent completely.
	CodeStreamFailed = "stream_failed"
	// CodeInternalError means the daemon hit an unexpected failure.
	CodeInternalError = "internal_error"
)

// FrameEnvelope contains fields common to every daemon request.
type FrameEnvelope struct {
	Version int    `json:"version"`
	Command string `json:"command"`
}

// Request is implemented by every concrete command request.
type Request interface {
	isRequest()
}

// ValidatableRequest is implemented by requests with client-side invariants.
type ValidatableRequest interface {
	Validate() error
}

// ReplyMode describes how a command returns data over the daemon connection.
type ReplyMode int

const (
	// ReplyModeFrame means the command returns one JSON reply frame.
	ReplyModeFrame ReplyMode = iota
	// ReplyModeNone means the command closes the connection without a reply.
	ReplyModeNone
	// ReplyModeStream means the command returns a JSON header frame followed by raw bytes.
	ReplyModeStream
)

type replyModeRequest interface {
	replyMode() ReplyMode
}

// FrameReply is the daemon's JSON reply frame.
type FrameReply struct {
	Version int    `json:"version"`
	Code    string `json:"code"`
	Value   string `json:"value,omitempty"`
	Error   string `json:"error,omitempty"`
}

// FrameHeader is implemented by streamed reply headers.
type FrameHeader interface {
	Err() error
}

// NewFrameEnvelope returns a frame envelope for the current GhosttyKit protocol.
func NewFrameEnvelope(command string) FrameEnvelope {
	return FrameEnvelope{Version: ghosttykit.ProtocolVersion, Command: command}
}

// ReplyModeOf reports how request returns data over the daemon connection.
func ReplyModeOf(request Request) ReplyMode {
	if request, ok := request.(replyModeRequest); ok {
		return request.replyMode()
	}
	return ReplyModeFrame
}

// Err returns nil for success or a typed protocol error for failure.
func (r FrameReply) Err() error {
	if r.Code == CodeOK {
		return nil
	}
	base := protocolError{code: r.Code, message: r.Error}
	switch r.Code {
	case CodeProtocolVersionMismatch:
		return &VersionMismatchError{protocolError: base}
	case CodeUnknownCommand:
		return &UnknownCommandError{protocolError: base}
	case CodeInvalidRequest:
		return &InvalidRequestError{protocolError: base}
	case CodeTerminalNotFound:
		return &TerminalNotFoundError{protocolError: base}
	case CodeGhosttyUnavailable:
		return &GhosttyUnavailableError{protocolError: base}
	case CodePasteEmpty:
		return &PasteEmptyError{protocolError: base}
	case CodePasteUnsupported:
		return &PasteUnsupportedError{protocolError: base}
	case CodeStreamFailed:
		return &StreamFailedError{protocolError: base}
	case CodeInternalError:
		return &InternalError{protocolError: base}
	default:
		return &ReplyError{protocolError: base}
	}
}

type protocolError struct {
	code    string
	message string
}

func (e protocolError) Error() string {
	if e.message == "" {
		return e.code
	}
	return e.code + ": " + e.message
}

func (e protocolError) Code() string {
	return e.code
}

// ReplyError is a failed reply frame with an unrecognized code.
type ReplyError struct{ protocolError }

// VersionMismatchError means the request protocol version is unsupported.
type VersionMismatchError struct{ protocolError }

// UnknownCommandError means the request command is not recognized.
type UnknownCommandError struct{ protocolError }

// InvalidRequestError means the request shape or field value is invalid.
type InvalidRequestError struct{ protocolError }

// TerminalNotFoundError means no Ghostty terminal matches the request target.
type TerminalNotFoundError struct{ protocolError }

// GhosttyUnavailableError means Ghostty cannot be reached or controlled.
type GhosttyUnavailableError struct{ protocolError }

// PasteEmptyError means the clipboard has no supported paste content.
type PasteEmptyError struct{ protocolError }

// PasteUnsupportedError means clipboard content exists but has no supported representation.
type PasteUnsupportedError struct{ protocolError }

// StreamFailedError means streamed content could not be sent completely.
type StreamFailedError struct{ protocolError }

// InternalError means the daemon hit an unexpected failure.
type InternalError struct{ protocolError }

// PingRequest checks daemon reachability.
type PingRequest struct {
	FrameEnvelope
}

func (PingRequest) isRequest() {}

// TerminalIDRequest asks the daemon to resolve the focused Ghostty terminal id.
type TerminalIDRequest struct {
	FrameEnvelope
	TTY     string `json:"tty,omitempty"`
	Focused bool   `json:"focused,omitempty"`
	Refresh bool   `json:"refresh,omitempty"`
}

func (TerminalIDRequest) isRequest() {}

// Validate checks terminal-id request invariants.
func (r TerminalIDRequest) Validate() error {
	if r.Refresh && r.TTY != "" && !r.Focused {
		return errors.New("cannot refresh terminal-id if it is not the focused window")
	}
	return nil
}

// TabTerminalCountRequest asks for the terminal count in the selected Ghostty tab.
type TabTerminalCountRequest struct {
	FrameEnvelope
	TTY     string `json:"tty,omitempty"`
	Focused bool   `json:"focused,omitempty"`
}

func (TabTerminalCountRequest) isRequest() {}

// ClearCacheRequest removes one TTY mapping, or all mappings when TTY is empty.
type ClearCacheRequest struct {
	FrameEnvelope
	TTY string `json:"tty,omitempty"`
	Ack bool   `json:"ack,omitempty"`
}

func (ClearCacheRequest) isRequest() {}

func (r ClearCacheRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// KeyTableActivateRequest activates a Ghostty key table for the caller TTY.
type KeyTableActivateRequest struct {
	FrameEnvelope
	TTY     string `json:"tty"`
	Focused bool   `json:"focused,omitempty"`
	Table   string `json:"table"`
	Ack     bool   `json:"ack,omitempty"`
}

func (KeyTableActivateRequest) isRequest() {}

func (r KeyTableActivateRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// KeyTableDeactivateRequest deactivates the current Ghostty key table for the caller TTY.
type KeyTableDeactivateRequest struct {
	FrameEnvelope
	TTY     string `json:"tty"`
	Focused bool   `json:"focused,omitempty"`
	Ack     bool   `json:"ack,omitempty"`
}

func (KeyTableDeactivateRequest) isRequest() {}

func (r KeyTableDeactivateRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// FocusRequest moves Ghostty focus in a direction for the caller TTY.
type FocusRequest struct {
	FrameEnvelope
	TTY       string `json:"tty"`
	Focused   bool   `json:"focused,omitempty"`
	Direction string `json:"direction"`
	Ack       bool   `json:"ack,omitempty"`
}

func (FocusRequest) isRequest() {}

func (r FocusRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// SplitRequest creates a Ghostty split from the caller TTY terminal.
type SplitRequest struct {
	FrameEnvelope
	TTY         string `json:"tty"`
	Focused     bool   `json:"focused,omitempty"`
	Direction   string `json:"direction"`
	CWD         string `json:"cwd,omitempty"`
	CommandText string `json:"commandText,omitempty"`
	Focus       string `json:"focus,omitempty"`
	Ack         bool   `json:"ack,omitempty"`
}

func (SplitRequest) isRequest() {}

func (r SplitRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// ResizeRequest resizes a Ghostty split adjacent to the caller TTY terminal.
type ResizeRequest struct {
	FrameEnvelope
	TTY       string       `json:"tty"`
	Focused   bool         `json:"focused,omitempty"`
	Direction string       `json:"direction"`
	Amount    ResizeAmount `json:"amount"`
	Ack       bool         `json:"ack,omitempty"`
}

func (ResizeRequest) isRequest() {}

func (r ResizeRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// ResizeAmount represents exactly one resize amount variant.
type ResizeAmount struct {
	Pixels  *int     `json:"pixels,omitempty"`
	Percent *float64 `json:"percent,omitempty"`
}

// ZoomRequest toggles split zoom for the caller TTY terminal.
type ZoomRequest struct {
	FrameEnvelope
	TTY     string `json:"tty"`
	Focused bool   `json:"focused,omitempty"`
	Ack     bool   `json:"ack,omitempty"`
}

func (ZoomRequest) isRequest() {}

func (r ZoomRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// PasteRequest asks the daemon to read the local clipboard for text or file-like content.
type PasteRequest struct {
	FrameEnvelope
	TTY string `json:"tty,omitempty"`
}

func (PasteRequest) isRequest() {}

func (PasteRequest) replyMode() ReplyMode { return ReplyModeStream }

func ackReplyMode(ack bool) ReplyMode {
	if ack {
		return ReplyModeFrame
	}
	return ReplyModeNone
}

// PasteKind is the paste result variant.
type PasteKind string

const (
	// PasteKindText carries plain clipboard text after the header.
	PasteKindText PasteKind = "text"
	// PasteKindFiles carries one or more materialized file entries in Files.
	PasteKindFiles PasteKind = "files"
)

// PasteFile is one file-like clipboard item returned by the daemon or written by the client.
type PasteFile struct {
	Path      string `json:"path,omitempty"`
	FileName  string `json:"fileName,omitempty"`
	MediaType string `json:"mediaType,omitempty"`
	Bytes     int64  `json:"bytes,omitempty"`
	Source    string `json:"source,omitempty"`
}

// PasteFrameHeader is the JSON header sent before any streamed paste bytes.
type PasteFrameHeader struct {
	FrameReply
	Kind  PasteKind   `json:"kind,omitempty"`
	Files []PasteFile `json:"files,omitempty"`
	Bytes int64       `json:"bytes,omitempty"`
}

// PasteResult is a validated paste result returned by the client after file materialization.
type PasteResult interface {
	PasteKind() PasteKind
}

// PasteTextResult is a text paste result.
type PasteTextResult struct {
	Text string
}

// PasteKind reports the result variant.
func (PasteTextResult) PasteKind() PasteKind {
	return PasteKindText
}

// PasteFilesResult is a file paste result.
type PasteFilesResult struct {
	Files []PasteFile
	Bytes int64
}

// PasteKind reports the result variant.
func (PasteFilesResult) PasteKind() PasteKind {
	return PasteKindFiles
}
