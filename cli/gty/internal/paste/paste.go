// Package paste formats clipboard content received from GhosttyKit.
package paste

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

const noContentExitCode = 2

// NoContentError reports that the clipboard has no supported content.
type NoContentError struct {
	Err error
}

func (e NoContentError) Error() string { return e.Err.Error() }

// ExitCode returns the conventional process exit code for no paste content.
func (NoContentError) ExitCode() int { return noContentExitCode }

// Text returns the shell-friendly text representation of a paste result.
func Text(result client.PasteResult) string {
	switch typed := result.(type) {
	case client.TextPaste:
		return typed.Text
	case client.FilesPaste:
		paths := make([]string, 0, len(typed.Files))
		for _, file := range typed.Files {
			paths = append(paths, shellQuote(file.Path))
		}
		return strings.Join(paths, " ")
	default:
		return ""
	}
}

// PrintText writes the shell-friendly representation of a paste result.
func PrintText(out io.Writer, result client.PasteResult) error {
	if _, ok := result.(client.TextPaste); ok {
		return nil
	}
	_, err := fmt.Fprintln(out, Text(result))
	return err
}

// PrintJSON writes a structured paste result as one JSON line.
func PrintJSON(out io.Writer, result client.PasteResult) error {
	encoded, err := json.Marshal(toJSONResult(result))
	if err != nil {
		return fmt.Errorf("encode paste result: %w", err)
	}
	_, err = fmt.Fprintln(out, string(encoded))
	return err
}

// MapNoContentError maps SDK no-content errors to the CLI exit-code convention.
func MapNoContentError(err error) error {
	if err == nil {
		return nil
	}
	if _, ok := errors.AsType[client.NoPasteContentError](err); ok {
		return NoContentError{Err: err}
	}
	return err
}

type jsonResult struct {
	protocol.FrameReply
	Kind  protocol.PasteKind   `json:"kind,omitempty"`
	Text  string               `json:"text,omitempty"`
	Files []protocol.PasteFile `json:"files,omitempty"`
	Bytes int64                `json:"bytes,omitempty"`
}

func toJSONResult(result client.PasteResult) jsonResult {
	switch typed := result.(type) {
	case client.TextPaste:
		return jsonResult{FrameReply: protocol.FrameReply{Version: ghosttykit.ProtocolVersion, Code: protocol.CodeOK}, Kind: protocol.PasteKindText, Text: typed.Text, Bytes: typed.Bytes}
	case client.FilesPaste:
		return jsonResult{FrameReply: protocol.FrameReply{Version: ghosttykit.ProtocolVersion, Code: protocol.CodeOK}, Kind: protocol.PasteKindFiles, Files: typed.Files, Bytes: typed.Bytes}
	default:
		return jsonResult{}
	}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
