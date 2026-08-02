// Package ghosttykit contains shared client and protocol code for GhosttyKit.
package ghosttykit

import (
	"regexp"
	"runtime/debug"
	"strings"
)

// ProtocolVersion is the current GhosttyKit wire protocol version.
const ProtocolVersion = 1

// Version is replaced by release builds when available.
var Version = devVersion

const (
	devVersion = "0.0.0-dev"
	modulePath = "github.com/thurstonsand/ghosttykit"
)

func init() {
	if tag, ok := ModuleReleaseTag(); ok && Version == devVersion {
		Version = strings.TrimPrefix(tag, "v")
	}
}

// ModuleReleaseTag reports the release tag this binary was built from, which the Go toolchain
// records for `go install <module>@vX.Y.Z` builds. Builds from a working tree report a pseudo
// version or carry build metadata, and are reported as no tag.
func ModuleReleaseTag() (string, bool) {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "", false
	}
	return releaseTagFrom(info)
}

func releaseTagFrom(info *debug.BuildInfo) (string, bool) {
	version := moduleVersion(info)
	if !strings.HasPrefix(version, "v") || strings.Contains(version, "+") || pseudoVersion.MatchString(version) {
		return "", false
	}
	return version, true
}

// pseudoVersion matches the timestamp and commit suffix Go appends when a module version names a
// commit rather than a tag.
var pseudoVersion = regexp.MustCompile(`[-.][0-9]{14}-[0-9a-f]{12}$`)

func moduleVersion(info *debug.BuildInfo) string {
	if info.Main.Path == modulePath {
		return info.Main.Version
	}
	for _, dependency := range info.Deps {
		if dependency.Path == modulePath {
			return dependency.Version
		}
	}
	return ""
}
