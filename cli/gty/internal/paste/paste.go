// Package paste receives and materializes clipboard content from GhosttyKit.
package paste

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"os"
	"path/filepath"
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

// Receive sends request and materializes streamed files into outputDir.
func Receive(gtyClient client.Client, request protocol.PasteRequest, outputDir string) (protocol.PasteResult, error) {
	header, body, err := client.Stream[protocol.PasteStreamFrameHeader](gtyClient, request)
	if err != nil {
		return nil, noContentError(err)
	}
	defer func() { _ = body.Close() }()

	return receive(body, header, outputDir)
}

// Write sends request and writes text content directly to out.
func Write(out io.Writer, gtyClient client.Client, request protocol.PasteRequest, outputDir string) error {
	header, body, err := client.Stream[protocol.PasteStreamFrameHeader](gtyClient, request)
	if err != nil {
		return noContentError(err)
	}
	defer func() { _ = body.Close() }()

	switch header.Kind {
	case protocol.PasteKindText:
		return copyText(out, body, header.Bytes)
	case protocol.PasteKindFiles:
		files, err := receiveFiles(body, header.Files, outputDir)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(out, Text(protocol.PasteFilesResult{Files: files, Bytes: sumFileBytes(files)}))
		return err
	case "":
		return NoContentError{Err: errors.New("clipboard has no supported content")}
	default:
		return fmt.Errorf("unsupported paste result kind: %s", header.Kind)
	}
}

func receive(body io.Reader, header protocol.PasteStreamFrameHeader, outputDir string) (protocol.PasteResult, error) {
	switch header.Kind {
	case protocol.PasteKindText:
		var builder strings.Builder
		if err := copyText(&builder, body, header.Bytes); err != nil {
			return nil, err
		}
		return protocol.PasteTextResult{Text: builder.String()}, nil
	case protocol.PasteKindFiles:
		files, err := receiveFiles(body, header.Files, outputDir)
		if err != nil {
			return nil, err
		}
		return protocol.PasteFilesResult{Files: files, Bytes: sumFileBytes(files)}, nil
	case "":
		return nil, NoContentError{Err: errors.New("clipboard has no supported content")}
	default:
		return nil, fmt.Errorf("unsupported paste result kind: %s", header.Kind)
	}
}

func copyText(out io.Writer, body io.Reader, bytes int64) error {
	if bytes < 0 {
		return errors.New("clipboard text has invalid byte count")
	}
	_, err := io.CopyN(out, body, bytes)
	return err
}

func noContentError(err error) error {
	if _, ok := errors.AsType[*protocol.PasteEmptyError](err); ok {
		return NoContentError{Err: err}
	}
	return err
}

func receiveFiles(reader io.Reader, files []protocol.PasteFile, outputDir string) ([]protocol.PasteFile, error) {
	materializedFiles := make([]protocol.PasteFile, 0, len(files))
	for _, file := range files {
		materialized, err := materializeFile(reader, file, outputDir)
		if err != nil {
			return nil, err
		}
		materializedFiles = append(materializedFiles, materialized)
	}
	return materializedFiles, nil
}

func materializeFile(reader io.Reader, file protocol.PasteFile, outputDir string) (protocol.PasteFile, error) {
	if file.Bytes < 0 {
		return protocol.PasteFile{}, fmt.Errorf("clipboard file %s has invalid byte count", file.FileName)
	}
	if err := os.MkdirAll(outputDir, 0o700); err != nil {
		return protocol.PasteFile{}, fmt.Errorf("create output directory: %w", err)
	}
	path := filepath.Join(outputDir, uniqueFileName(file))
	out, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return protocol.PasteFile{}, fmt.Errorf("create clipboard file: %w", err)
	}
	_, copyErr := io.CopyN(out, reader, file.Bytes)
	closeErr := out.Close()
	if copyErr != nil {
		_ = os.Remove(path)
		return protocol.PasteFile{}, fmt.Errorf("write clipboard file: %w", copyErr)
	}
	if closeErr != nil {
		_ = os.Remove(path)
		return protocol.PasteFile{}, fmt.Errorf("close clipboard file: %w", closeErr)
	}
	file.Path = path
	return file, nil
}

func uniqueFileName(file protocol.PasteFile) string {
	ext := extensionForFile(file)
	name := strings.TrimSpace(filepath.Base(file.FileName))
	if name != "." && name != string(filepath.Separator) && name != "" {
		base := strings.TrimSuffix(name, filepath.Ext(name))
		if base != "" {
			return fmt.Sprintf("%s-%s%s", sanitizeFilenameBase(base), randomSuffix(), ext)
		}
	}
	return fmt.Sprintf("pi-paste-%s%s", randomSuffix(), ext)
}

func extensionForFile(file protocol.PasteFile) string {
	if ext := filepath.Ext(file.FileName); ext != "" {
		return ext
	}
	if file.FileName != "" {
		return ""
	}
	if exts, err := mime.ExtensionsByType(file.MediaType); err == nil && len(exts) > 0 {
		return exts[0]
	}
	return ""
}

func sanitizeFilenameBase(value string) string {
	var builder strings.Builder
	for _, r := range value {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_', r == '.':
			builder.WriteRune(r)
		default:
			builder.WriteRune('-')
		}
	}
	result := strings.Trim(builder.String(), ".-")
	if result == "" {
		return "pi-paste"
	}
	return result
}

func randomSuffix() string {
	bytes := make([]byte, 6)
	if _, err := rand.Read(bytes); err != nil {
		return "fallback"
	}
	return hex.EncodeToString(bytes)
}

// Text returns the shell-friendly text representation of a paste result.
func Text(result protocol.PasteResult) string {
	switch typed := result.(type) {
	case protocol.PasteTextResult:
		return typed.Text
	case protocol.PasteFilesResult:
		paths := make([]string, 0, len(typed.Files))
		for _, file := range typed.Files {
			paths = append(paths, shellQuote(file.Path))
		}
		return strings.Join(paths, " ")
	default:
		return ""
	}
}

// PrintJSON writes a structured paste result as one JSON line.
func PrintJSON(out io.Writer, result protocol.PasteResult) error {
	encoded, err := json.Marshal(toJSONResult(result))
	if err != nil {
		return fmt.Errorf("encode paste result: %w", err)
	}
	_, err = fmt.Fprintln(out, string(encoded))
	return err
}

type jsonResult struct {
	protocol.FrameReply
	Kind  protocol.PasteKind   `json:"kind,omitempty"`
	Text  string               `json:"text,omitempty"`
	Files []protocol.PasteFile `json:"files,omitempty"`
	Bytes int64                `json:"bytes,omitempty"`
}

func toJSONResult(result protocol.PasteResult) jsonResult {
	switch typed := result.(type) {
	case protocol.PasteTextResult:
		return jsonResult{FrameReply: protocol.FrameReply{Version: ghosttykit.ProtocolVersion, Code: protocol.CodeOK}, Kind: protocol.PasteKindText, Text: typed.Text, Bytes: int64(len(typed.Text))}
	case protocol.PasteFilesResult:
		return jsonResult{FrameReply: protocol.FrameReply{Version: ghosttykit.ProtocolVersion, Code: protocol.CodeOK}, Kind: protocol.PasteKindFiles, Files: typed.Files, Bytes: typed.Bytes}
	default:
		return jsonResult{}
	}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func sumFileBytes(files []protocol.PasteFile) int64 {
	var total int64
	for _, file := range files {
		total += file.Bytes
	}
	return total
}
