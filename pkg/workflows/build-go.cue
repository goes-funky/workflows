package workflows

import "github.com/goes-funky/workflows/pkg/common"

#step_setup_tools_cache: common.#step & {
    name: "Setup tools cache"
    id:   "tools-cache"
    uses: "actions/cache@v4"
    with: {
        path: "build/"
        key:  "${{ runner.os }}-tools-${{ hashFiles('Makefile', 'makefiles/**') }}"
    }

}

#step_setup_deps_cache: common.#step & {
    name: "Setup Go cache"
    id:   "deps-cache"
    uses: "actions/cache@v4"
    with: {
        path: "~/go/pkg/mod"
        key:  "${{ runner.os }}-deps-${{ inputs.go-version }}-${{ hashFiles('**/go.sum') }}"
    }

}

#step_setup_go: common.#step & {
    name: "Setup go"
    uses: "actions/setup-go@v5"
    with: "go-version": "${{ inputs.go-version }}"
}

common.#workflow & {
    name: "Build Go"
    on: {
        workflow_call: {
            inputs: {
            	"skip-checkout": {
					type:        "boolean"
					description: "Whether to skip checkout"
					default:     false
				}
				"with-submodules": {
					type:        "boolean"
					description: "Whether to fetch git submodules"
					default:     true
				}
                common.#with.ssh_agent.inputs
                "go-version": {
                    type:        "string"
                    description: "Go version"
                    default:     "1.17"
                }
            }

            secrets: {
                common.#with.ssh_agent.secrets
            }
        }
    }
    jobs: {
        tools: {
            name: "Tools"
            steps: [
                common.#with.checkout.step,
                #step_setup_tools_cache,
                {
                    name: "Setup go"
                    uses: "actions/setup-go@v5"
                    with: "go-version": "${{ inputs.go-version }}"
                    if: "!steps.tools-cache.outputs.cache-hit"
                },
                {
                    name: "Download tools"
                    if:   "!steps.tools-cache.outputs.cache-hit"
                    run:  "make tools"
                },
            ]
        }
        deps: {
            name: "Dependencies"
            steps: [
                common.#with.checkout.step,
                #step_setup_deps_cache,
                {
                    name: "Setup go"
                    uses: "actions/setup-go@v5"
                    with: "go-version": "${{ inputs.go-version }}"
                    if: "!steps.deps-cache.outputs.cache-hit"
                },
                common.#with.ssh_agent.step,
                {
                    name: "Download dependencies"
                    if:   "!steps.deps-cache.outputs.cache-hit"
                    run: """
                         git config --global url."git@github.com:".insteadOf "https://github.com/"
                         go mod download
                         """
                },
            ]
        }
        check: {
            needs: ["tools", "deps"]
            "runs-on": "ubuntu-latest"
            name: "Check"
            env: GOLANGCILINT_CONCURRENCY: "4"
            steps: [
                common.#with.checkout.step,
                #step_setup_go,
                #step_setup_tools_cache,
                #step_setup_deps_cache,
                {
                    name: "Ensure code is formatted"
                    run:  "make format && make git-dirty"
                },
                {
                    name: "Lint"
                    run:  "make lint"
                },
            ]
        }
        test: {
            needs: ["tools", "deps"]
            name: "Test"
            steps: [
                common.#with.checkout.step,
                #step_setup_go,
                #step_setup_deps_cache,
                {
                    name: "Unit test"
                    run:  "make test"
                },
                {
                    name: "Integration test with coverage"
                    run:  "make integration-test-cover"
                },
            ]
        }
    }
}
