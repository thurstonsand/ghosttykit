package osc

import "testing"

func TestSanitizeTitleRemovesControlCharacters(t *testing.T) {
	got := sanitizeTitle("ok\x00\x1fbell\x7fc1\u009bbad世界")
	want := "okbellc1bad世界"
	if got != want {
		t.Fatalf("sanitizeTitle() = %q, want %q", got, want)
	}
}
