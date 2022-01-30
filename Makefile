.PHONY: all build clean test lint

all: build

lint: update-dependencies ## Lint the files
	@echo Running lint
	golangci-lint run --fix

update-dependencies: ## Uses go get -u to update all the dependencies while holding back any that require it.
	@echo Updating Dependencies
	go get -v -d -t ./...
	go mod tidy

build: update-dependencies ## Build the binary file
	@echo Running build
	go build -v ./...

help: ## Display this help screen
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
