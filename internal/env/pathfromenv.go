package env

import (
	"fmt"
	"os"
	"path/filepath"
)

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
