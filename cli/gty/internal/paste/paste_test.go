package paste

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func TestPrintJSONIncludesTextPayload(t *testing.T) {
	var out bytes.Buffer
	if err := PrintJSON(&out, protocol.PasteTextResult{Text: "hello"}); err != nil {
		t.Fatalf("PrintJSON() error = %v", err)
	}

	var got jsonResult
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("unmarshal PrintJSON output: %v", err)
	}
	if got.Kind != protocol.PasteKindText {
		t.Fatalf("kind = %q, want %q", got.Kind, protocol.PasteKindText)
	}
	if got.Text != "hello" {
		t.Fatalf("text = %q, want %q", got.Text, "hello")
	}
}

func TestTextShellQuotesFilePaths(t *testing.T) {
	response := protocol.PasteFilesResult{Files: []protocol.PasteFile{
		{Path: "/tmp/pi paste/one.txt"},
		{Path: "/tmp/pi'paste/two.txt"},
	}}

	got := Text(response)
	want := "'/tmp/pi paste/one.txt' '/tmp/pi'\\''paste/two.txt'"
	if got != want {
		t.Fatalf("Text() = %q, want %q", got, want)
	}
}
