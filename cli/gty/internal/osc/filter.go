package osc

import (
	"bytes"
	"io"
	"strings"
)

// NavigationTitle returns the window title a remote Herdr pane sets to carry an outward
// navigation direction to the local gty herdr attach process. ghosttykit.nvim builds the same
// title in nvim/lua/ghosttykit/nvim/herdr.lua; the two spellings must stay in sync.
func NavigationTitle(direction string) string {
	return navigationSentinelPrefix + direction
}

// NewNavigationFilter returns a filter that copies stream bytes to out, calling onDirection for
// every navigation sentinel title instead of writing it. Callbacks run inline, so they are
// serialized against each other and against surrounding output.
func NewNavigationFilter(out io.Writer, onDirection func(direction string)) *NavigationFilter {
	return &NavigationFilter{out: out, onDirection: onDirection}
}

// NavigationFilter removes navigation sentinel titles from a terminal stream. Terminal sequences
// split across reads, so the filter carries an incomplete sequence between writes; every byte that
// is not part of a sentinel reaches out unchanged.
type NavigationFilter struct {
	out         io.Writer
	onDirection func(direction string)
	state       filterState
	buffered    []byte
}

// Write copies chunk to the underlying writer, holding back navigation sentinels.
func (f *NavigationFilter) Write(chunk []byte) (int, error) {
	for index := 0; index < len(chunk); {
		next, err := f.step(chunk, index)
		if err != nil {
			return len(chunk), err
		}
		index = next
	}
	return len(chunk), nil
}

// Close flushes an escape sequence left incomplete when the stream ended.
func (f *NavigationFilter) Close() error {
	state := f.state
	f.state = stateText
	switch state {
	case stateEscape:
		return f.emit([]byte{escape})
	case stateSequenceTerminator:
		f.buffered = append(f.buffered, escape)
		return f.flushBuffered()
	case stateSequence:
		return f.flushBuffered()
	default:
		return nil
	}
}

// step consumes bytes starting at index and reports where the next step resumes.
func (f *NavigationFilter) step(chunk []byte, index int) (int, error) {
	switch f.state {
	case stateText:
		found := bytes.IndexByte(chunk[index:], escape)
		if found < 0 {
			return len(chunk), f.emit(chunk[index:])
		}
		f.state = stateEscape
		return index + found + 1, f.emit(chunk[index : index+found])
	case stateEscape:
		return f.stepEscape(chunk, index)
	case stateSequence:
		return f.stepSequence(chunk, index)
	default:
		return f.stepSequenceTerminator(chunk, index)
	}
}

func (f *NavigationFilter) stepEscape(chunk []byte, index int) (int, error) {
	switch current := chunk[index]; current {
	case ']':
		f.buffered = append(f.buffered[:0], escape, ']')
		f.state = stateSequence
		return index + 1, nil
	case escape:
		return index + 1, f.emit([]byte{escape})
	default:
		f.state = stateText
		return index + 1, f.emit([]byte{escape, current})
	}
}

func (f *NavigationFilter) stepSequence(chunk []byte, index int) (int, error) {
	switch current := chunk[index]; current {
	case bell:
		f.buffered = append(f.buffered, current)
		f.state = stateText
		return index + 1, f.complete()
	case escape:
		f.state = stateSequenceTerminator
		return index + 1, nil
	default:
		f.buffered = append(f.buffered, current)
		if len(f.buffered) > maxBufferedSequence {
			f.state = stateText
			return index + 1, f.flushBuffered()
		}
		return index + 1, nil
	}
}

// stepSequenceTerminator resolves the escape byte inside a buffered sequence. Anything but a
// backslash makes the buffered sequence malformed, and that escape byte begins a new sequence.
func (f *NavigationFilter) stepSequenceTerminator(chunk []byte, index int) (int, error) {
	if chunk[index] == '\\' {
		f.buffered = append(f.buffered, escape, '\\')
		f.state = stateText
		return index + 1, f.complete()
	}
	f.state = stateEscape
	return index, f.flushBuffered()
}

func (f *NavigationFilter) complete() error {
	direction, found := navigationDirection(f.buffered)
	if !found {
		return f.flushBuffered()
	}
	f.buffered = f.buffered[:0]
	f.onDirection(direction)
	return nil
}

func (f *NavigationFilter) flushBuffered() error {
	err := f.emit(f.buffered)
	f.buffered = f.buffered[:0]
	return err
}

func (f *NavigationFilter) emit(chunk []byte) error {
	if len(chunk) == 0 {
		return nil
	}
	_, err := f.out.Write(chunk)
	return err
}

// navigationDirection reports the direction a complete OSC sequence carries, accepting either
// title selector and either standard terminator. The payload must match exactly: the sentinel is
// remote input, and a match moves a local Ghostty split.
func navigationDirection(sequence []byte) (string, bool) {
	payload, found := strings.CutPrefix(string(sequence), "\x1b]0;")
	if !found {
		payload, found = strings.CutPrefix(string(sequence), "\x1b]2;")
	}
	if !found {
		return "", false
	}
	payload, found = cutTerminator(payload)
	if !found {
		return "", false
	}
	direction, found := strings.CutPrefix(payload, navigationSentinelPrefix)
	if !found || !navigationDirections[direction] {
		return "", false
	}
	return direction, true
}

func cutTerminator(payload string) (string, bool) {
	if cut, found := strings.CutSuffix(payload, "\x07"); found {
		return cut, true
	}
	return strings.CutSuffix(payload, "\x1b\\")
}

type filterState int

const (
	stateText filterState = iota
	stateEscape
	stateSequence
	stateSequenceTerminator
)

const (
	escape                   = 0x1b
	bell                     = 0x07
	navigationSentinelPrefix = "gty-nav:v1:"
	// maxBufferedSequence bounds how much of a stream the filter holds back for an OSC sequence
	// that may never terminate.
	maxBufferedSequence = 256
)

var navigationDirections = map[string]bool{
	"left":  true,
	"down":  true,
	"up":    true,
	"right": true,
}
