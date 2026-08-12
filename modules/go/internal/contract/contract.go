package contract

import (
	"errors"
	"path"
	"strings"
)

func Workspace(module string) (string, error) {
	module = strings.TrimSpace(module)
	if module == "" || module == "." {
		return "/src", nil
	}
	cleaned := path.Clean(module)
	if path.IsAbs(cleaned) || cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", errors.New("module must be relative to the source root")
	}
	return path.Join("/src", cleaned), nil
}

func Packages(packages []string) []string {
	if len(packages) == 0 {
		return []string{"./..."}
	}
	return append([]string(nil), packages...)
}

func TestArgs(packages []string, race bool) []string {
	args := []string{"go", "test"}
	if race {
		args = append(args, "-race")
	}
	return append(args, Packages(packages)...)
}

func OutputName(output string) (string, error) {
	output = strings.TrimSpace(output)
	if output == "" || output == "." || output == ".." || strings.ContainsAny(output, `/\\`) || strings.ContainsRune(output, '\x00') || path.Base(output) != output {
		return "", errors.New("output must be a non-empty file name")
	}
	return output, nil
}
