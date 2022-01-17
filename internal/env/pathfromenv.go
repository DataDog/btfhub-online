package env

import (
	"fmt"
	"os"
	"path/filepath"
)

// GetAbsolutePathFromEnv gets an environment variable name, and tries to get a full local path from it.
// If the environment variable does not exist, or the path does not exist locally - we return an error.
func GetAbsolutePathFromEnv(env string) (string, error) {
	dirEnv := os.Getenv(env)
	if dirEnv == "" {
		return "", fmt.Errorf("%s is empty", env)
	}
	var err error
	dirPath, err := filepath.Abs(dirEnv)
	if err != nil {
		return "", err
	}
	_, err = os.Stat(dirPath)
	if err != nil {
		return "", err
	}

	return dirPath, nil
}
