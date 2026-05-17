package paste

import (
	"testing"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

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
