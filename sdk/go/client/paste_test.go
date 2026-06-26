package client

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestPasteReceivesTextInMemory(t *testing.T) {
	client := pasteTestClient(t, `{"version":1,"code":"ok","kind":"text","bytes":5}`+"\nhello")

	result, err := client.Paste(PasteOptions{})
	if err != nil {
		t.Fatalf("Paste() error = %v", err)
	}
	text, ok := result.(TextPaste)
	if !ok {
		t.Fatalf("Paste() result = %T, want TextPaste", result)
	}
	if text.Text != "hello" {
		t.Fatalf("Text = %q, want hello", text.Text)
	}
	if text.Bytes != 5 {
		t.Fatalf("Bytes = %d, want 5", text.Bytes)
	}
}

func TestWritePasteTextStreamsTextToWriter(t *testing.T) {
	client := pasteTestClient(t, `{"version":1,"code":"ok","kind":"text","bytes":5}`+"\nhello")
	var out bytes.Buffer

	result, err := client.WritePasteText(&out, PasteOptions{})
	if err != nil {
		t.Fatalf("WritePasteText() error = %v", err)
	}
	if out.String() != "hello" {
		t.Fatalf("written text = %q, want hello", out.String())
	}
	text, ok := result.(TextPaste)
	if !ok {
		t.Fatalf("WritePasteText() result = %T, want TextPaste", result)
	}
	if text.Text != "" {
		t.Fatalf("streamed Text = %q, want empty", text.Text)
	}
}

func TestPasteMaterializesFilesToDisk(t *testing.T) {
	header := `{"version":1,"code":"ok","kind":"files","bytes":11,"files":[{"fileName":"../bad name.txt","mediaType":"text/plain","bytes":5},{"mediaType":"text/plain; charset=utf-8","bytes":6}]}`
	client := pasteTestClient(t, header+"\nhelloworld!")
	outputDir := t.TempDir()

	result, err := client.Paste(PasteOptions{OutputDir: outputDir})
	if err != nil {
		t.Fatalf("Paste() error = %v", err)
	}
	filesPaste, ok := result.(FilesPaste)
	if !ok {
		t.Fatalf("Paste() result = %T, want FilesPaste", result)
	}
	if filesPaste.Bytes != 11 {
		t.Fatalf("Bytes = %d, want 11", filesPaste.Bytes)
	}
	if len(filesPaste.Files) != 2 {
		t.Fatalf("len(Files) = %d, want 2", len(filesPaste.Files))
	}
	assertFile(t, filesPaste.Files[0].Path, "hello")
	assertFile(t, filesPaste.Files[1].Path, "world!")
	if strings.Contains(filepath.Base(filesPaste.Files[0].Path), "bad name") {
		t.Fatalf("file name was not sanitized: %s", filesPaste.Files[0].Path)
	}
}

func TestPasteRemovesIncompleteFileOnCopyFailure(t *testing.T) {
	header := `{"version":1,"code":"ok","kind":"files","bytes":10,"files":[{"fileName":"broken.txt","bytes":10}]}`
	client := pasteTestClient(t, header+"\nshort")
	outputDir := t.TempDir()

	_, err := client.Paste(PasteOptions{OutputDir: outputDir})
	if err == nil {
		t.Fatal("Paste() error = nil, want copy failure")
	}
	entries, err := os.ReadDir(outputDir)
	if err != nil {
		t.Fatalf("ReadDir() error = %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("output dir entries = %d, want 0", len(entries))
	}
}

func TestPasteRejectsNegativeByteCounts(t *testing.T) {
	client := pasteTestClient(t, `{"version":1,"code":"ok","kind":"text","bytes":-1}`+"\n")

	_, err := client.Paste(PasteOptions{})
	if err == nil {
		t.Fatal("Paste() error = nil, want invalid byte count")
	}
}

func TestPasteMapsEmptyClipboardToNoPasteContentError(t *testing.T) {
	client := pasteTestClient(t, `{"version":1,"code":"paste_empty","error":"empty"}`+"\n")

	_, err := client.Paste(PasteOptions{})
	if _, ok := errors.AsType[NoPasteContentError](err); !ok {
		t.Fatalf("Paste() error = %T %[1]v, want NoPasteContentError", err)
	}
}

func pasteTestClient(t *testing.T, response string) Client {
	t.Helper()
	socketPath := testUnixSocket(t)
	listener := testUnixListener(t, socketPath)
	t.Cleanup(func() { _ = listener.Close() })

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()

		var request protocol.PasteRequest
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			return
		}
		_, _ = io.WriteString(conn, response)
	}()

	return ForSocket(socketPath)
}

func assertFile(t *testing.T, path string, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s) error = %v", path, err)
	}
	if string(got) != want {
		t.Fatalf("ReadFile(%s) = %q, want %q", path, got, want)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat(%s) error = %v", path, err)
	}
	if gotMode := info.Mode().Perm(); gotMode != 0o600 {
		t.Fatalf("mode = %o, want 600", gotMode)
	}
}
