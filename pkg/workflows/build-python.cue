package workflows

import "github.com/goes-funky/workflows/pkg/common"

#step_setup_python: common.#step & {
	name: "Setup python"
	id:   "setup-python"
	uses: "actions/setup-python@v2"
	with: {
		"python-version": "${{ inputs.python-version }}"
	}
}

#step_setup_poetry: common.#step & {
	name: "Install and configure Poetry"
	uses: "snok/install-poetry@v1"
	with: {
		version:                  "${{ inputs.poetry-version }}"
		"virtualenvs-create":     true
		"virtualenvs-in-project": true
	}
}

#step_setup_deps_cache: common.#step & {
	name: "Setup cache"
	id:   "deps-cache"
	uses: "actions/cache@v2"
	with: {
		path: ".venv/"
		key:  "${{ runner.os }}-python-${{ steps.setup-python.outputs.python-version }}-${{ hashFiles('**/poetry.lock') }}"
	}
}

common.#build_workflow & {
	name: "Build Python"
	on: {
		workflow_call: {
			inputs: {
				"python-version": {
					type:        "string"
					description: "Python version"
					default:     "3.9"
				}
				"ubuntu-version": {
					type:        "string"
					description: "Ubuntu version"
					default:     "latest"
				}
				"poetry-version": {
					type:        "string"
					description: "Poetry version"
					default:     "1.1.12"
				}
				// Know issue installing some packages. Resolved past poetry v1.2 which is
				// currently in beta https://github.com/python-poetry/poetry/issues/4511
				"setuptools-version": {
					type:        "string"
					description: "Force poetry setuptools version"
					default:    ""
					required: false
				}
				"skip-lint": {
					type:        "boolean"
					description: "Whether to skip code linting with flake8"
					default:    false
				}
				"skip-isort": {
					type:        "boolean"
					description: "Whether to skip code linting with isort"
					default:     true
				}
				"skip-format": {
					type:        "boolean"
					description: "Whether to skip code formatting"
					default:     false
				}
				"skip-tests": {
					type:        "boolean"
					description: "Whether to skip running tests"
					default:     true
				}
				"skip-mypy": {
					type:        "boolean"
					description: "Whether to skip checking type hints with mypy"
					default:     true
				}
			}
			secrets: {
				"codecov-token": {
					description: "Token to upload coverage reports to codecov"
					required:    false
				}
			}
		}
	}
	jobs: {
		deps: {
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			name:      "Dependencies"
			steps: [
				common.#step_checkout,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				common.#step_setup_ssh_agent,
				{
					name: "Configure setup tools for poetry"
					//if: "!steps.deps-cache.outputs.cache-hit  && inputs.setuptools-version"
					if: "inputs.setuptools-version"
					env: {
						SETUPTOOLS_VERSION: "${{ inputs.setuptools-version }}"
					}
					run: """
						poetry run pip install "setuptools==$SETUPTOOLS_VERSION"
						"""
				},
				{
					name: "Download dependencies"
					//if: "!steps.deps-cache.outputs.cache-hit"
					run: """
						git config --global url."git@github.com:".insteadOf "https://github.com/"
						poetry install
						"""
				},
			]
		}
		black: {
			name: "Black"
			if:   "!inputs.skip-format"
			needs: ["deps"]
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#step_checkout,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				{
					name: "Ensure code is formatted"
					run:  "poetry run black --check ."
				},
			]
		}
		lint: {
			name: "Lint"
			if:   "!inputs.skip-lint"
			needs: ["deps"]
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#step_checkout,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				{
					name: "Flake8"
					run:  "poetry run flake8"
				},
				{
					name: "Isort"
					if:   "!inputs.skip-isort"
					run:  "poetry run isort --profile black --check ."
				},
			]
		}
		tests: {
			name: "Tests"
			if:   "!inputs.skip-tests"
			needs: ["deps"]
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#step_checkout,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				{
					name: "Tests"
					run: """
						poetry run coverage run -m pytest
						poetry run coverage xml
						"""
				},
				{
					name: "Upload Coverage to Codecov"
					env: CODECOV_TOKEN: "${{ secrets.codecov-token }}"
					if:   "env.CODECOV_TOKEN != null"
					uses: "codecov/codecov-action@v2"
					with: token: "${{ secrets.codecov-token }}"
				},
			]
		}
		mypy: {
			name: "Mypy"
			if:   "!inputs.skip-mypy"
			needs: ["deps"]
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#step_checkout,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				{
					name: "Mypy"
					run:  "poetry run mypy ."
				},
			]
		}
	}
}
