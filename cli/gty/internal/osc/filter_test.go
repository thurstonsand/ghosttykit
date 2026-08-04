package osc

import (
	"bytes"
	"strings"
	"testing"
)

func TestNavigationFilterStripsSentinelAtEveryReadSplit(t *testing.T) {
	prefix := "before\x1b]2;real title\x07mid"
	suffix := "after\x1b]0;another\x1b\\end"
	for _, framing := range []struct {
		name      string
		sentinel  string
		direction string
	}{
		{name: "osc 2 bel", sentinel: "\x1b]2;gty-nav:v1:left\x07", direction: "left"},
		{name: "osc 0 bel", sentinel: "\x1b]0;gty-nav:v1:down\x07", direction: "down"},
		{name: "osc 2 st", sentinel: "\x1b]2;gty-nav:v1:up\x1b\\", direction: "up"},
		{name: "osc 0 st", sentinel: "\x1b]0;gty-nav:v1:right\x1b\\", direction: "right"},
	} {
		t.Run(framing.name, func(t *testing.T) {
			stream := prefix + framing.sentinel + suffix
			wantOutput := prefix + suffix
			wantDirection := framing.direction

			for split := 0; split <= len(stream); split++ {
				output, directions := runFilter(t, stream[:split], stream[split:])
				if output != wantOutput {
					t.Fatalf("split %d output = %q, want %q", split, output, wantOutput)
				}
				if len(directions) != 1 || directions[0] != wantDirection {
					t.Fatalf("split %d directions = %v, want [%s]", split, directions, wantDirection)
				}
			}
		})
	}
}

func TestNavigationFilterPreservesOtherTraffic(t *testing.T) {
	cases := []struct {
		name   string
		stream string
	}{
		{name: "plain text", stream: "hello world\n"},
		{name: "ordinary title", stream: "\x1b]2;herdr — pod042\x07"},
		{name: "unknown direction", stream: "\x1b]2;gty-nav:v1:sideways\x07"},
		{name: "unknown version", stream: "\x1b]2;gty-nav:v2:left\x07"},
		{name: "payload with trailing text", stream: "\x1b]2;gty-nav:v1:left ignored\x07"},
		{name: "wrong selector", stream: "\x1b]1;gty-nav:v1:left\x07"},
		{name: "unterminated sequence", stream: "\x1b]2;gty-nav:v1:left"},
		{name: "malformed terminator", stream: "\x1b]2;gty-nav:v1:left\x1bZtail"},
		{name: "bare escapes", stream: "\x1b\x1b[2J\x1b"},
		{name: "csi sequences", stream: "\x1b[1;32mgreen\x1b[0m"},
		{name: "oversized sequence", stream: "\x1b]2;" + strings.Repeat("x", 512) + "\x07"},
		{name: "sentinel text without escape", stream: "gty-nav:v1:left"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			for split := 0; split <= len(testCase.stream); split++ {
				output, directions := runFilter(t, testCase.stream[:split], testCase.stream[split:])
				if output != testCase.stream {
					t.Fatalf("split %d output = %q, want %q", split, output, testCase.stream)
				}
				if len(directions) != 0 {
					t.Fatalf("split %d directions = %v, want none", split, directions)
				}
			}
		})
	}
}

func TestNavigationFilterReportsConsecutiveSentinelsInOrder(t *testing.T) {
	stream := "\x1b]2;" + NavigationTitle("left") + "\x07\x1b]0;" + NavigationTitle("up") + "\x1b\\tail"
	output, directions := runFilter(t, stream, "")
	if output != "tail" {
		t.Fatalf("output = %q, want %q", output, "tail")
	}
	if len(directions) != 2 || directions[0] != "left" || directions[1] != "up" {
		t.Fatalf("directions = %v, want [left up]", directions)
	}
}

// TestNavigationFilterHandlesRecordedHerdrOutput replays bytes captured from an attached Herdr
// 0.7.5 client: it frames the title as OSC 0 with a BEL, and its clear arrives as the very next
// sequence. The filter must remove the first and pass the second.
func TestNavigationFilterHandlesRecordedHerdrOutput(t *testing.T) {
	stream := "\x1b[?2026l\x1b[4;29H\x1b[?25h\x1b]0;gty-nav:v1:left\x07\x1b]0;herdr\x07"
	wantOutput := "\x1b[?2026l\x1b[4;29H\x1b[?25h\x1b]0;herdr\x07"
	for split := 0; split <= len(stream); split++ {
		output, directions := runFilter(t, stream[:split], stream[split:])
		if output != wantOutput {
			t.Fatalf("split %d output = %q, want %q", split, output, wantOutput)
		}
		if len(directions) != 1 || directions[0] != "left" {
			t.Fatalf("split %d directions = %v, want [left]", split, directions)
		}
	}
}

func TestNavigationFilterWritesByteAtATime(t *testing.T) {
	stream := "log\x1b]2;" + NavigationTitle("right") + "\x07more\x1b]2;title\x07"
	var out bytes.Buffer
	var directions []string
	filter := NewNavigationFilter(&out, func(direction string) { directions = append(directions, direction) })
	for index := range len(stream) {
		if _, err := filter.Write([]byte(stream[index : index+1])); err != nil {
			t.Fatalf("Write() error = %v", err)
		}
	}
	if err := filter.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	if want := "logmore\x1b]2;title\x07"; out.String() != want {
		t.Fatalf("output = %q, want %q", out.String(), want)
	}
	if len(directions) != 1 || directions[0] != "right" {
		t.Fatalf("directions = %v, want [right]", directions)
	}
}

func runFilter(t *testing.T, chunks ...string) (string, []string) {
	t.Helper()
	var out bytes.Buffer
	var directions []string
	filter := NewNavigationFilter(&out, func(direction string) { directions = append(directions, direction) })
	for _, chunk := range chunks {
		written, err := filter.Write([]byte(chunk))
		if err != nil {
			t.Fatalf("Write(%q) error = %v", chunk, err)
		}
		if written != len(chunk) {
			t.Fatalf("Write(%q) = %d, want %d", chunk, written, len(chunk))
		}
	}
	if err := filter.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	return out.String(), directions
}
