###  Developer Guidelines

``btfhub-online`` welcomes your contribution. To make the process as seamless as possible, we ask for the following:

* Go ahead and fork the project and make your changes. We encourage pull requests to discuss code changes.
    - Fork it
    - Create your feature branch (`git checkout -b my-new-feature`)
    - Commit your changes (`git commit -am 'Add some feature'`)
    - Push to the branch (`git push origin my-new-feature`)
    - Create new Pull Request

* When you're ready to create a pull request, be sure to:
    - Have test cases for the new code. If you have questions about how to do it, please ask in your pull request.
    - Run `make lint`
      - Alternatively you can run `golangci-lint run --fix`
      - Requires [golangci-linter](https://github.com/golangci/golangci-lint)
    - Squash your commits into a single commit. `git rebase -i`. It's okay to force update your pull request.
    - Make sure `make build` and `make test` are running without failing
      - Can run `go build -v ./...` and `go test -v ./...`

* Read [Effective Go](https://github.com/golang/go/wiki/CodeReviewComments) article from Golang project
    - `btfhub-online` project is strictly conformant with Golang style
    - if you happen to observe offending code, please feel free to send a pull request
