// Package protocol defines the GhosttyKit JSON contract.
package protocol

import ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"

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

// Envelope contains fields common to every daemon request.
type Envelope struct {
	Version int    `json:"version"`
	Command string `json:"command"`
}

// Request is implemented by every concrete command request.
type Request interface {
	isRequest()
}

// Response is the daemon response.
type Response struct {
	Version int    `json:"version"`
	Code    string `json:"code"`
	Value   string `json:"value,omitempty"`
	Error   string `json:"error,omitempty"`
}

// StreamHeader is implemented by streamed response headers.
type StreamHeader interface {
	Err() error
}

// NewEnvelope returns an envelope for the current GhosttyKit protocol.
func NewEnvelope(command string) Envelope {
	return Envelope{Version: ghosttykit.ProtocolVersion, Command: command}
}

// Err returns nil for success or a typed protocol error for failure.
func (r Response) Err() error {
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
		return &ResponseError{protocolError: base}
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

// ResponseError is a failed protocol response with an unrecognized code.
type ResponseError struct{ protocolError }

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
	Envelope
}

func (PingRequest) isRequest() {}

// TerminalIDRequest asks the daemon to resolve the focused Ghostty terminal id.
type TerminalIDRequest struct {
	Envelope
	TTY     string `json:"tty,omitempty"`
	Refresh bool   `json:"refresh,omitempty"`
}

func (TerminalIDRequest) isRequest() {}

// TabTerminalCountRequest asks for the terminal count in the selected Ghostty tab.
type TabTerminalCountRequest struct {
	Envelope
}

func (TabTerminalCountRequest) isRequest() {}

// ClearCacheRequest removes one TTY mapping, or all mappings when TTY is empty.
type ClearCacheRequest struct {
	Envelope
	TTY string `json:"tty,omitempty"`
	Ack bool   `json:"ack,omitempty"`
}

func (ClearCacheRequest) isRequest() {}

// KeyTableActivateRequest activates a Ghostty key table for the caller TTY.
type KeyTableActivateRequest struct {
	Envelope
	TTY   string `json:"tty"`
	Table string `json:"table"`
	Ack   bool   `json:"ack,omitempty"`
}

func (KeyTableActivateRequest) isRequest() {}

// KeyTableDeactivateRequest deactivates the current Ghostty key table for the caller TTY.
type KeyTableDeactivateRequest struct {
	Envelope
	TTY string `json:"tty"`
	Ack bool   `json:"ack,omitempty"`
}

func (KeyTableDeactivateRequest) isRequest() {}

// FocusRequest moves Ghostty focus in a direction for the caller TTY.
type FocusRequest struct {
	Envelope
	TTY       string `json:"tty"`
	Direction string `json:"direction"`
	Ack       bool   `json:"ack,omitempty"`
}

func (FocusRequest) isRequest() {}

// SplitRequest creates a Ghostty split from the caller TTY terminal.
type SplitRequest struct {
	Envelope
	TTY         string `json:"tty"`
	Direction   string `json:"direction"`
	CWD         string `json:"cwd,omitempty"`
	CommandText string `json:"commandText,omitempty"`
	Focus       string `json:"focus,omitempty"`
	Ack         bool   `json:"ack,omitempty"`
}

func (SplitRequest) isRequest() {}

// ResizeRequest resizes a Ghostty split adjacent to the caller TTY terminal.
type ResizeRequest struct {
	Envelope
	TTY       string       `json:"tty"`
	Direction string       `json:"direction"`
	Amount    ResizeAmount `json:"amount"`
	Ack       bool         `json:"ack,omitempty"`
}

func (ResizeRequest) isRequest() {}

// ResizeAmount represents exactly one resize amount variant.
type ResizeAmount struct {
	Pixels  *int     `json:"pixels,omitempty"`
	Percent *float64 `json:"percent,omitempty"`
}

// ZoomRequest toggles split zoom for the caller TTY terminal.
type ZoomRequest struct {
	Envelope
	TTY string `json:"tty"`
	Ack bool   `json:"ack,omitempty"`
}

func (ZoomRequest) isRequest() {}

// PasteRequest asks the daemon to read the local clipboard for text or file-like content.
type PasteRequest struct {
	Envelope
	TTY string `json:"tty,omitempty"`
}

func (PasteRequest) isRequest() {}

// PasteKind is the paste response variant.
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

// PasteHeader is the JSON header sent before any streamed paste bytes.
type PasteHeader struct {
	Response
	Kind  PasteKind   `json:"kind,omitempty"`
	Files []PasteFile `json:"files,omitempty"`
	Bytes int64       `json:"bytes,omitempty"`
}

// PasteResponse is a validated paste response returned by the client after file materialization.
type PasteResponse interface {
	PasteKind() PasteKind
}

// PasteTextResponse is a text paste response.
type PasteTextResponse struct {
	Text string
}

// PasteKind reports the response variant.
func (PasteTextResponse) PasteKind() PasteKind {
	return PasteKindText
}

// PasteFilesResponse is a file paste response.
type PasteFilesResponse struct {
	Files []PasteFile
	Bytes int64
}

// PasteKind reports the response variant.
func (PasteFilesResponse) PasteKind() PasteKind {
	return PasteKindFiles
}
