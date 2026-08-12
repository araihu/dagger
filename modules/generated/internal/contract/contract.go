package contract

import (
	"fmt"
	"sort"
	"strings"
)

func DriftError(added, modified, removed []string) error {
	paths := make([]string, 0, len(added)+len(modified)+len(removed))
	for _, path := range added {
		paths = append(paths, "+"+path)
	}
	for _, path := range modified {
		paths = append(paths, "~"+path)
	}
	for _, path := range removed {
		paths = append(paths, "-"+path)
	}
	if len(paths) == 0 {
		return nil
	}
	sort.Strings(paths)
	return fmt.Errorf("generated content drifted: %s", strings.Join(paths, ", "))
}
