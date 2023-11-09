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

#step_install_poetry_packages: common.#step & {
        name: "Download poetry packages"
        run: """
            git config --global url."git@github.com:".insteadOf "https://github.com/"
            poetry install
            """
}

#step_set_custom_environment_variables: common.#step & {
        name: "Set custom environment variables"
        if: "inputs.environment-variables != '{}'"
        run: """
            jq -r 'to_entries|map("\\(.key)=\\(.value|tostring)")|.[]' <<< "${{ inputs.environment-variables }}" >> "$GITHUB_ENV"
        """
}

#step_install_custom_setup_tools: common.#step & {
    name: "Configure setup tools for poetry"
    if: "inputs.setuptools-version"
    env: {
        SETUPTOOLS_VERSION: "${{ inputs.setuptools-version }}"
    }
    run: """
        poetry run pip install "setuptools==$SETUPTOOLS_VERSION"
        """
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
                common.#with.load_artifact.inputs
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
                "environment-variables": {
                    type:        "string"
                    description: "Custom environment variables made available during the tests and integration tests."
                    required:    false
                    default:     "{}"
                }
            }
            secrets: {
                common.#with.ssh_agent.secrets
                // include manually to make them optional.
                "gcp-gcr-service-account": {
                    description: "GCP GCR Service Account e-mail"
                    required: false
                }
                "gcp-gcr-workload-identity-provider": {
                    description: "GCP GCR Workload Identity provider"
                    required: false
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
        "pre-job": {
             outputs: should_skip: "${{ steps.skip_check.outputs.should_skip }}"
             steps: [{
                 id:   "skip_check"
                 uses: "fkirc/skip-duplicate-actions@v5"
             }]
         }
        deps: {
            "runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
            name:      "Dependencies"
            needs: ["pre-job"]
            if: "needs.pre-job.outputs.should_skip != 'true'"
            steps: [
                common.#with.checkout.step,
                common.#with.load_artifact.step,
                #step_setup_python,
                #step_setup_deps_cache,
                #step_setup_poetry,
                common.#with.ssh_agent.step,
                #step_install_custom_setup_tools,
                #step_install_poetry_packages,
            ]
        }
        black: {
            name: "Black"
            if:   "!inputs.skip-format"
            needs: ["deps"]
            "runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
            steps: [
                common.#with.checkout.step,
                common.#with.load_artifact.step,
                #step_setup_python,
                #step_setup_deps_cache,
                #step_setup_poetry,
                common.#with.ssh_agent.step,
                #step_install_custom_setup_tools,
                #step_install_poetry_packages,
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
                common.#with.checkout.step & {
                    with: {
                        "fetch-depth": 0
                    }
                },
                common.#with.load_artifact.step,
                common.#with.trufflehog.step,
                #step_setup_python,
                #step_setup_deps_cache,
                #step_setup_poetry,
                common.#with.ssh_agent.step,
                #step_install_custom_setup_tools,
                #step_install_poetry_packages,
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
                common.#with.load_artifact.step,
                #step_setup_python,
                #step_setup_deps_cache,
                #step_setup_poetry,
                common.#with.ssh_agent.step,
                #step_install_custom_setup_tools,
                #step_install_poetry_packages,
                #step_set_custom_environment_variables,
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
            if:   "!inputs.skip-integration-tests && needs.pre-job.outputs.should_skip != 'true'"
            "runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
            needs: ["pre-job"]
            steps: [
                common.#with.checkout.step & {
                    with: {
                       "fetch-depth": 0
                    }
                },
                common.#with.load_artifact.step,
                common.#with.ssh_agent.step,
                common.#with.gcloud.step & {
                    with: {
                        service_account: "${{ secrets.gcp-gcr-service-account }}"
                        workload_identity_provider: "${{ secrets.gcp-gcr-workload-identity-provider }}"
                        token_format: "access_token"
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
                #step_set_custom_environment_variables,
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
                    if: "always()"
                    run: "docker-compose stop"
                },
                {
                    name: "Print logs"
                    if: "always()"
                    run: "docker-compose logs"
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
                common.#with.load_artifact.step,
                #step_setup_python,
                #step_setup_deps_cache,
                #step_setup_poetry,
                common.#with.ssh_agent.step,
                #step_install_custom_setup_tools,
                #step_install_poetry_packages,
                {
                    name: "Mypy"
                    run:  "poetry run mypy ."
                },
            ]
        }
        diff_poetry: {
            name: "Diff Poetry lockfile"
            if: "${{ github.event_name == 'pull_request' }}"
            "runs-on": "ubuntu-${{ inputs.ubuntu-version }}"
            steps: [
                {
                    name: "Diff poetry.lock"
			        uses: "goes-funky/diff-poetry-lock@main"
                },
            ]
        }
    }
}
