package workflows

import "github.com/goes-funky/workflows/pkg/common"

// This workflow is intended for this own repo only
common.#workflow & {
    name: "Verify workflows"
    on: {
        push: {
            branches: ["master"]
        }

        pull_request: {}
    }

    jobs: {
        verify: {
            name: "Verify"
            steps: [
                {
                    name: "Checkout"
                    uses: "actions/checkout@v4"
                },
                {
                    name: "Setup tools cache"
                    id: "cache"
                    uses: "actions/cache@v3"
                    with: {
                        path: "bin"
                        key: "${{ runner.os }}-tools-${{ hashFiles('Makefile') }}"
                    }
                },
                {
                    name: "Install tools"
                    if: "!steps.cache.outputs.cache-hit"
                    run: "make tools"
                },
                {
                    name: "Verify that workflows are up to date"
                    run: """
                         make generate
                         git diff --exit-code
                         """
                },
                {
                    name: "Lint workflows"
                    run: "make lint"
                },
        ]
        }
    }
}
