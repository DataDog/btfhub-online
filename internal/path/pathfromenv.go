package path

import (
	"os"
	"path/filepath"
)

// GetAbsolutePath tries to get a full local path from the input argument.
// If the path does not exist locally - we return an error.
func GetAbsolutePath(dir string) (string, error) {
	dirPath, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	_, err = os.Stat(dirPath)
	if err != nil {
		return "", err
	}

	return dirPath, nil
}
