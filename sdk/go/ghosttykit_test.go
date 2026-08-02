package ghosttykit

import (
	"runtime/debug"
	"testing"
)

func TestReleaseTagFromBuildInfo(t *testing.T) {
	cases := []struct {
		name string
		info *debug.BuildInfo
		tag  string
	}{
		{
			name: "module installed at a tag",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.4.0"}},
			tag:  "v0.4.0",
		},
		{
			name: "module installed at a prerelease tag",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.5.0-rc.1"}},
			tag:  "v0.5.0-rc.1",
		},
		{
			name: "built from a checkout",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "(devel)"}},
		},
		{
			name: "built from a modified checkout",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.4.1-0.20260718114517-af7b50a7659b+dirty"}},
		},
		{
			name: "built from a modified checkout at a tag",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.4.0+dirty"}},
		},
		{
			name: "installed at a commit after a tag",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.4.1-0.20260801183000-6f6de24abcde"}},
		},
		{
			name: "installed at a commit with no tag",
			info: &debug.BuildInfo{Main: debug.Module{Path: modulePath, Version: "v0.0.0-20260801183000-6f6de24abcde"}},
		},
		{
			name: "embedded in another program",
			info: &debug.BuildInfo{
				Main: debug.Module{Path: "example.com/app", Version: "v2.0.0"},
				Deps: []*debug.Module{{Path: modulePath, Version: "v0.4.0"}},
			},
			tag: "v0.4.0",
		},
		{
			name: "absent from another program",
			info: &debug.BuildInfo{Main: debug.Module{Path: "example.com/app", Version: "v2.0.0"}},
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			tag, ok := releaseTagFrom(testCase.info)
			if ok != (testCase.tag != "") || tag != testCase.tag {
				t.Fatalf("releaseTagFrom() = %q, %v, want %q", tag, ok, testCase.tag)
			}
		})
	}
}
