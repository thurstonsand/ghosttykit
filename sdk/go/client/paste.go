package client

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

// PasteOptions controls clipboard paste retrieval.
type PasteOptions struct {
	TTY       string
	OutputDir string
}

// PasteResult is a received clipboard paste.
type PasteResult interface {
	PasteKind() protocol.PasteKind
	PasteBytes() int64
}

// TextPaste is a text clipboard paste held in memory.
type TextPaste struct {
	Text  string
	Bytes int64
}

// PasteKind reports the result variant.
func (TextPaste) PasteKind() protocol.PasteKind { return protocol.PasteKindText }

// PasteBytes reports the byte count received from the daemon.
func (p TextPaste) PasteBytes() int64 { return p.Bytes }

// FilesPaste is a file clipboard paste materialized to disk.
type FilesPaste struct {
	Files []protocol.PasteFile
	Bytes int64
}

// PasteKind reports the result variant.
func (FilesPaste) PasteKind() protocol.PasteKind { return protocol.PasteKindFiles }

// PasteBytes reports the byte count written to disk.
func (p FilesPaste) PasteBytes() int64 { return p.Bytes }

// NoPasteContentError reports that the clipboard has no supported content.
type NoPasteContentError struct {
	Err error
}

func (e NoPasteContentError) Error() string { return e.Err.Error() }
func (e NoPasteContentError) Unwrap() error { return e.Err }

// Paste receives clipboard content. Text content is held in memory; file content is streamed to OutputDir.
func (c Client) Paste(opts PasteOptions) (PasteResult, error) {
	var builder strings.Builder
	return c.WritePasteText(&builder, opts)
}

// WritePasteText receives clipboard content. Text content streams to out; file content streams to OutputDir.
func (c Client) WritePasteText(out io.Writer, opts PasteOptions) (PasteResult, error) {
	header, body, err := Stream[protocol.PasteStreamFrameHeader](c, protocol.NewPasteRequest(opts.TTY))
	if err != nil {
		return nil, noPasteContentError(err)
	}
	defer func() { _ = body.Close() }()

	switch header.Kind {
	case protocol.PasteKindText:
		return writeTextPaste(out, body, header.Bytes)
	case protocol.PasteKindFiles:
		files, err := receivePasteFiles(body, header.Files, opts.OutputDir)
		if err != nil {
			return nil, err
		}
		return FilesPaste{Files: files, Bytes: sumPasteFileBytes(files)}, nil
	case "":
		return nil, NoPasteContentError{Err: errors.New("clipboard has no supported content")}
	default:
		return nil, fmt.Errorf("unsupported paste result kind: %s", header.Kind)
	}
}

func writeTextPaste(out io.Writer, body io.Reader, bytes int64) (TextPaste, error) {
	if bytes < 0 {
		return TextPaste{}, errors.New("clipboard text has invalid byte count")
	}
	if _, err := io.CopyN(out, body, bytes); err != nil {
		return TextPaste{}, err
	}
	text := ""
	if builder, ok := out.(*strings.Builder); ok {
		text = builder.String()
	}
	return TextPaste{Text: text, Bytes: bytes}, nil
}

func noPasteContentError(err error) error {
	if _, ok := errors.AsType[*protocol.PasteEmptyError](err); ok {
		return NoPasteContentError{Err: err}
	}
	return err
}

func receivePasteFiles(reader io.Reader, files []protocol.PasteFile, outputDir string) ([]protocol.PasteFile, error) {
	if strings.TrimSpace(outputDir) == "" {
		return nil, errors.New("paste output directory is required")
	}
	materializedFiles := make([]protocol.PasteFile, 0, len(files))
	for _, file := range files {
		materialized, err := materializePasteFile(reader, file, outputDir)
		if err != nil {
			return nil, err
		}
		materializedFiles = append(materializedFiles, materialized)
	}
	return materializedFiles, nil
}

func materializePasteFile(reader io.Reader, file protocol.PasteFile, outputDir string) (protocol.PasteFile, error) {
	if file.Bytes < 0 {
		return protocol.PasteFile{}, fmt.Errorf("clipboard file %s has invalid byte count", file.FileName)
	}
	if err := os.MkdirAll(outputDir, 0o700); err != nil {
		return protocol.PasteFile{}, fmt.Errorf("create output directory: %w", err)
	}
	root, err := os.OpenRoot(outputDir)
	if err != nil {
		return protocol.PasteFile{}, fmt.Errorf("open output directory: %w", err)
	}
	defer func() { _ = root.Close() }()

	name := uniquePasteFileName(file)
	out, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return protocol.PasteFile{}, fmt.Errorf("create clipboard file: %w", err)
	}
	_, copyErr := io.CopyN(out, reader, file.Bytes)
	closeErr := out.Close()
	if copyErr != nil {
		_ = root.Remove(name)
		return protocol.PasteFile{}, fmt.Errorf("write clipboard file: %w", copyErr)
	}
	if closeErr != nil {
		_ = root.Remove(name)
		return protocol.PasteFile{}, fmt.Errorf("close clipboard file: %w", closeErr)
	}
	file.Path = filepath.Join(outputDir, name)
	return file, nil
}

func uniquePasteFileName(file protocol.PasteFile) string {
	ext := extensionForPasteFile(file)
	name := strings.TrimSpace(filepath.Base(file.FileName))
	if name != "." && name != string(filepath.Separator) && name != "" {
		base := strings.TrimSuffix(name, filepath.Ext(name))
		if base != "" {
			return fmt.Sprintf("%s-%s%s", sanitizePasteFilenameBase(base), randomPasteSuffix(), ext)
		}
	}
	return fmt.Sprintf("pasted-file-%s%s", randomPasteSuffix(), ext)
}

func extensionForPasteFile(file protocol.PasteFile) string {
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

func sanitizePasteFilenameBase(value string) string {
	var builder strings.Builder
	lastWasDash := false
	for _, r := range strings.TrimSpace(value) {
		if isPasteFilenameRune(r) {
			builder.WriteRune(r)
			lastWasDash = false
			continue
		}
		if !lastWasDash {
			builder.WriteByte('-')
			lastWasDash = true
		}
	}
	result := strings.Trim(builder.String(), ".-")
	if result == "" {
		return "pasted-file"
	}
	return result
}

func isPasteFilenameRune(r rune) bool {
	return r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.'
}

func randomPasteSuffix() string {
	bytes := make([]byte, 6)
	if _, err := rand.Read(bytes); err != nil {
		return "fallback"
	}
	return hex.EncodeToString(bytes)
}

func sumPasteFileBytes(files []protocol.PasteFile) int64 {
	var total int64
	for _, file := range files {
		total += file.Bytes
	}
	return total
}
