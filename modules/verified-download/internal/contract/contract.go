package contract

import (
	"encoding/hex"
	"errors"
	"net/url"
	"path"
	"strings"
)

func Request(rawURL, digest, name string) (string, string, string, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil {
		return "", "", "", errors.New("url must be an absolute https URL")
	}
	digest = strings.ToLower(strings.TrimSpace(digest))
	digest = strings.TrimPrefix(digest, "sha256:")
	decoded, err := hex.DecodeString(digest)
	if err != nil || len(decoded) != 32 {
		return "", "", "", errors.New("sha256 must contain exactly 64 hexadecimal characters")
	}
	name = strings.TrimSpace(name)
	if name != "" && (name == "." || name == ".." || strings.ContainsAny(name, `/\\`) || strings.ContainsRune(name, '\x00') || path.Base(name) != name) {
		return "", "", "", errors.New("name must be a file name without path separators")
	}
	return parsed.String(), "sha256:" + digest, name, nil
}
