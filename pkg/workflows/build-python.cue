package workflows

import "github.com/goes-funky/workflows/pkg/common"

#step_setup_python: common.#step & {
	name: "Setup python"
	id:   "setup-python"
	uses: "actions/setup-python@v4"
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
	uses: "actions/cache@v3"
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
				"print-logs-for-services": {
					type:        "string"
					description: "Which services logs are shown in integrations tests. All by default"
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
				"skip-integration-tests": {
					type:        "boolean"
					description: "Whether to skip running integration tests"
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
				// include manually to make them optional.
				"gcp-gcr-project-id": {
                	description: "GCP GCR Project ID. Required for integration_tests."
                	required:    false
                }
                "gcp-gcr-service-account": {
                	description: "GCP GCR Service Account Key. Required for integration_tests."
                	required:    false
                }
                // end of manual include
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
		integration_tests: {
			name: "Integration tests"
			if:   "!inputs.skip-integration-tests"
			"runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
			steps: [
				common.#with.checkout.step & {
								with: {
										"fetch-depth": 0
								}
						},
				common.#with.ssh_agent.step,
				common.#with.gcloud.step & {
                	with: {
                		project_id:       "${{ secrets.gcp-gcr-project-id }}"
                		credentials_json: "${{ secrets.gcp-gcr-service-account }}"
                		token_format:     "access_token"
                	}
                },
                common.#with.docker_auth.step,
                common.#with.docker_artifacts_auth.step,
				{
					name: "Update docker-compose"
					uses: "KengoTODA/actions-setup-docker-compose@62da66e273e37258ddfb9ccc55f7934bdd25b57d"
					with: {
						version: "v2.10.2"
					}
				},
				{
					name: "Pull images"
					run: "docker-compose pull"
				},
				{
					name: "Setup cache"
					uses: "jpribyl/action-docker-layer-caching@v0.1.0"
				},
				{
					name: "Build"
					env: {
						DOCKER_BUILDKIT: "1"
					}
					run: "docker-compose build"
				},
				{
					name: "Integration tests"
					run: "docker-compose up -d"
				},
				{
					name: "Stop"
					if: "success() || failure()"
					run: "docker-compose stop"
				},
				{
					name: "Print logs"
					if: "success() || failure()"
					run: "docker-compose logs ${{ inputs.print-logs-for-services }}"
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
