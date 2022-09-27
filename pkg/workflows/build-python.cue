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

common.#workflow & {
	name: "Build Python"
	on: {
		workflow_call: {
			inputs: {
				common.#with.checkout.inputs
				common.#with.ssh_agent.inputs
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
				"skip-docker-compose-up": {
					type:        "boolean"
					description: "Whether to skip starting containers"
					default:     true
				}
				"skip-mypy": {
					type:        "boolean"
					description: "Whether to skip checking type hints with mypy"
					default:     true
				}
				"skip-sonar": {
					type:        "boolean"
					description: "Whether to skip sonarcloud scans"
					default:     true
				}
			}
			secrets: {
				common.#with.ssh_agent.secrets
				"sonar_token": {
					description: "Token for sonarcloud.io scans"
					required:    false
				}
				"codecov-token": {
					description: "Keep around until all workflows are migrated"
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
				common.#with.checkout.step,
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				common.#with.ssh_agent.step,
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
				common.#with.checkout.step,
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
				common.#with.checkout.step,
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
				common.#with.checkout.step & {
                    with: {
                        "fetch-depth": 0
                    }
                },
				#step_setup_python,
				#step_setup_deps_cache,
				#step_setup_poetry,
				{
					name: "Start containers"
					if: "!inputs.skip-docker-compose-up"
					env: {
						DOCKER_BUILDKIT: "1"
					}
					run: "docker-compose up -d"
				},
				{
					name: "Tests"
					run: """
						poetry run coverage run -m pytest
						poetry run coverage xml
						sed -i "s/<source>.*<\\/source>/<source>\\/github\\/workspace<\\/source>/g" coverage.xml
						"""
				},
				{
					name: "Sonarcloud check Push"
					env: {
						GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
						SONAR_TOKEN: "${{ secrets.SONAR_TOKEN }}"
					}
					if: "!inputs.skip-sonar && github.event_name != 'pull_request'"
					uses: "SonarSource/sonarcloud-github-action@master"
					with: {
						args: """
							-Dsonar.python.coverage.reportPaths=coverage.xml
							-Dsonar.projectKey=${{github.repository_owner}}_${{github.event.repository.name}}
							-Dsonar.organization=${{github.repository_owner}}
							-Dsonar.projectVersion=${{github.sha}}
							"""
					}
				},
				{
                	name: "Sonarcloud check PR"
                	env: {
                		GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
                		SONAR_TOKEN: "${{ secrets.SONAR_TOKEN }}"
                	}
                	if: "!inputs.skip-sonar && github.event_name != 'push'"
                	uses: "SonarSource/sonarcloud-github-action@master"
                	with: {
                		args: """
                			-Dsonar.python.coverage.reportPaths=coverage.xml
                			-Dsonar.projectKey=${{github.repository_owner}}_${{github.event.repository.name}}
                			-Dsonar.organization=${{github.repository_owner}}
                			"""
                	}
                },
			]
		}
		mypy: {
			name: "Mypy"
			if:   "!inputs.skip-mypy"
			needs: ["deps"]
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#with.checkout.step,
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
