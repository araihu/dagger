package contract

import (
	"errors"
	"path"
	"strings"
)

func Workspace(input string) (string, error) {
	input = strings.TrimSpace(input)
	if input == "" || input == "." {
		return "/src", nil
	}
	cleaned := path.Clean(input)
	if path.IsAbs(cleaned) || cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", errors.New("workspace must be relative to the source root")
	}
	return path.Join("/src", cleaned), nil
}

func InstallArgs(ignoreScripts bool) []string {
	args := []string{"npm", "ci"}
	if ignoreScripts {
		args = append(args, "--ignore-scripts")
	}
	return args
}

func RunArgs(script string, args []string) ([]string, error) {
	script = strings.TrimSpace(script)
	if script == "" || strings.HasPrefix(script, "-") {
		return nil, errors.New("script must be a non-empty npm script name")
	}
	command := []string{"npm", "run", script}
	if len(args) > 0 {
		command = append(command, "--")
		command = append(command, args...)
	}
	return command, nil
}
