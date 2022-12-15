package common

import "list"

#deploy_integration_workflow: #workflow & {
    on: {
        workflow_call: {
            inputs: {
                #with.checkout.inputs
                #with.kube_tools.inputs
                #with.ssh_agent.inputs
                "environment": {
                    type:        "string"
                    description: "Deployment environment"
                    required:    false
                }
                "development-environment": {
                    type:        "string"
                    description: "Development environment"
                    default:     "dev"
                    required:    false
                }
                "production-environment": {
                    type:        "string"
                    description: "Production environment"
                    default:     "prod"
                    required:    false
                }
                "default-repo": {
                    type:        "string"
                    description: "Default artifact repository"
                    default:     "eu.gcr.io/y42-artifacts-ea47981a"
                    required:    false
                }
                "dist-artifact": {
                    type:        "string"
                    description: "Dist artifact name"
                    required:    false
                }
                "skip-deploy": {
                    type:        "boolean"
                    description: "Skip deployment to cluster"
                    required:    false
                }
                "skip-build": {
                    type:        "boolean"
                    description: "Skip build to cluster"
                    required:    false
                }
                "skip-job-template-build": {
                    type:        "boolean"
                    description: "Job-template configmap building for deploy of tap containers"
                    default:     false
                    required:    false
                }
                "skip-integration-schema-generate": {
                    type:        "boolean"
                    description: "Whether to skip integration json schema generation & upload"
                    default:     false
                    required:    false
                }
                "integration-schema-command": {
                    type:        "string"
                    description: "The command to run to generate the integration schema"
                    default:     "poetry run python -m datos_integrations.commands.generate_schemas --outpath=./integrations --version=0.0.0"
                    required:    false
                }
                "python-version": {
                    type:        "string"
                    description: "Python version"
                    default:     "3.9"
                    required:    false
                }
                "poetry-version": {
                    type:        "string"
                    description: "Poetry version"
                    default:     "1.1.15"
                    required:    false
                }
                // Know issue installing some packages. Resolved past poetry v1.2 which is currently in beta https://github.com/python-poetry/poetry/issues/4511
                "setuptools-version": {
                    type:        "string"
                    description: "Force poetry setuptools version"
                    default:     "57.5.0"
                }
                "skip-checkout": {
                    type:        "boolean"
                    description: "Whether to skip checkout"
                    default:     false
                }
                "use-skaffold-cache": {
                    type: "boolean"
                    required: false
                    default: false
                    description: "Setup skaffold cache before build"
                }
                ...
            }
            secrets: {
                #with.gcloud.secrets
                #with.gke.secrets
                #with.ssh_agent.secrets
                "json-schema-bucket": {
                    description: "Required for json-schema upload. Name of the bucket to write integration schema to."
                    required:    false
                }
                ...
            }
        }

    }

    jobs: {
        "integration-schema-generate-development": {
            name: "Upload Integration Schema to dev"
            needs: ["deps", "build"]
            environment: "${{ inputs.development-environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        "integration-schema-generate-production": {
            name: "Upload Integration Schema to prod"
            needs: ["deps", "build", "integration-schema-generate-development", "deploy-development"]
            if:          string | *"inputs.environment"
            environment: "${{ inputs.production-environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        "deploy-development": {
            name: "Deploy to development"
            needs: ["build"]
            environment: "${{ inputs.development-environment }}"
            steps:       #integration_steps.deploy_integration
        }

        "deploy-production": {
            name: "Deploy to production"
            needs: ["build", "deploy-development"]
            environment: "${{ inputs.production-environment }}"
            steps:       #integration_steps.deploy_integration
        }

        deps: {
            name:  "Dependencies"
            steps: #integration_steps.dependencies
        }

        "integration-schema-generate-environment": {
            name: "Upload Integration Schema to env"
            needs: ["deps", "build"]
            if:          "inputs.environment"
            environment: "${{ inputs.environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        build: {
            name: "Build Docker images"
            steps: [
                {
                    name: "Checkout"
                    if:   "!inputs.skip-checkout"
                    uses: "actions/checkout@v3"
                    with: {
                        path: "./code"
                    }
                },
                {
                    name: "Setup buildkit"
                    id:   "setup-buildkit"
                    uses: "docker/setup-buildx-action@v2"
                },
                #with.expose_action_env.step,
                #with.custom_skaffold_build_script.step,
                {
                    name: "Configure skaffold to build with buildkit"
                    run:  "cp ./code/skaffold.yaml . && yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"../docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"Dockerfile\"}}}}' skaffold.yaml"
                },
                #with.skaffold_cache.step,
                {
                    name: "Download artifact"
                    uses: "actions/download-artifact@v3"
                    if:   "inputs.dist-artifact"
                    with: {
                        name: "${{ inputs.dist-artifact }}"
                        path: "./code/dist"
                    }
                },
                #with.ssh_agent.step,
                #with.gcloud.step & {
                    with: {
                        project_id:       "${{ secrets.gcp-gcr-project-id }}"
                        credentials_json: "${{ secrets.gcp-gcr-service-account }}"
                        token_format:     "access_token"
                    }
                },
                #with.docker_auth.step,
                #with.docker_artifacts_auth.step,
                #with.kube_tools.step,
                {
                    name: "Export git build details"
                    env: REPO: "${{ inputs.default-repo }}"
                    run: """
                        CONTAINER_NAME=$(basename -s .git "$(git remote get-url origin)") && echo "CONTAINER_NAME=$CONTAINER_NAME" >> "$GITHUB_ENV"
                        SHORT_SHA="$(git rev-parse --short HEAD)" && echo "SHORT_SHA=$SHORT_SHA" >> "$GITHUB_ENV"
                        COMMIT_SHA="$(git rev-parse HEAD)" && echo "COMMIT_SHA=$COMMIT_SHA" >> "$GITHUB_ENV"
                        IMAGE_NAME="$REPO/$CONTAINER_NAME:$SHORT_SHA" && echo "IMAGE_NAME=$IMAGE_NAME" >> "$GITHUB_ENV"
                        """
                },
                {
                    name: "Configure Skaffold"
                    // env: REPO: "${{ inputs.default-repo }}"
                    run: "skaffold config set default-repo '${{ inputs.default-repo }}'"
                },
                {
                    name: "Build"
                    if:   "!inputs.skip-build"
                    env: {
                        CONTAINER_NAME: "${{ env.CONTAINER_NAME }}"
                        SHORT_SHA:      "${{ env.SHORT_SHA }}"
                        COMMIT_SHA:     "${{ env.COMMIT_SHA }}"
                        IMAGE_NAME:     "${{ env.IMAGE_NAME }}"
                        SKAFFOLD_DEFAULT_REPO:    "${{ inputs.default-repo }}"
                        SKAFFOLD_CACHE_ARTIFACTS: "${{ inputs.use-skaffold-cache }}"
                        DOCKER_BUILDKIT_BUILDER:  "${{ steps.setup-buildkit.outputs.name }}"
                    }
                    run: "cd ./code && skaffold build --filename=../skaffold.yaml --file-output=build.json"
                },
                {
                    name: "Archive build reference"
                    if:   "!inputs.skip-build"
                    uses: "actions/upload-artifact@v3"
                    with: {
                        name: "build-ref"
                        path: "./code/build.json"
                    }
                },
            ]
        }

        "deploy-environment": {
            name: "Deploy to environment"
            needs: ["build"]
            if:          "inputs.environment"
            environment: "${{ inputs.environment }}"
            steps:       #integration_steps.deploy_integration
        }
    }
}

#integration_steps: {
    dependencies: list.Concat(
            [
                #steps_base,
                [
                    #with.ssh_agent.step,
                    {
                    name: "Configure setup tools for poetry"
                    if:   "inputs.setuptools-version"
                    env: SETUPTOOLS_VERSION: "${{ inputs.setuptools-version }}"
                    run: "poetry run pip install \"setuptools==$SETUPTOOLS_VERSION\""
                },
                {
                    name: "Download dependencies"
                    run: """
                        git config --global url."git@github.com:".insteadOf "https://github.com/"
                        poetry install
                        """
                },
            ],
        ])

    json_scheme_generate: list.Concat(
                [#steps_base,
                    [{
                name: "Generate Integration JSON schema"
                env: {
                    GENERATE_SCHEMA_COMMAND: "${{ inputs.integration-schema-command }}"
                    DEPLOY_ENVIRONMENT:      "${{ inputs.environment }}"
                }
                run: """
                    KAFKA_SERVERS='' export KAFKA_SERVERS
                    KAFKA_SASL_KEY=''  export KAFKA_SASL_KEY
                    KAFKA_SASL_SECRET='' export KAFKA_SASL_SECRET
                    CONTAINER_MODULE=$(basename -s .git "$(git remote get-url origin | sed 's/-/_/g')" ) export CONTAINER_MODULE
                    eval "$GENERATE_SCHEMA_COMMAND"
                    """
            },
                #with.gcloud.step,
                {
                    name: "Upload Integration schema to JSON schema folder"
                    //pinning version till resolved https://github.com/google-github-actions/upload-cloud-storage/issues/248
                    uses: "google-github-actions/upload-cloud-storage@v1"
                    with: {
                        path:        "integrations"
                        destination: "${{ secrets.json-schema-bucket }}"
                        headers:     "cache-control: public, max-age=300"
                    }

                }],
        ])

    deploy_integration: [
        #with.checkout.step,
        #with.ssh_agent.step,
        #with.gcloud.step & {
            with: {
                project_id:       "${{ secrets.gcp-project-id }}"
                credentials_json: "${{ secrets.gcp-service-account }}"
            }
        },
        #with.gke.step,
        {
            name: "Download build reference"
            uses: "actions/download-artifact@v3"
            with: {
                name: "build-ref"
            }
        },
        #with.kube_tools.step &
        {
            with: {
                "setup-tools": "skaffold"
                skaffold:      "${{ inputs.skaffold }}"
            }
        },
        {
            name: "Deploy"
            if:   "inputs.skip-job-template-build"
            run:  "skaffold deploy --force --build-artifacts=build.json"
        },
        {
            name: "Deploy tap container with job-template"
            if:   "!inputs.skip-job-template-build"
            run: """
                skaffold render --offline=true --build-artifacts=build.json > rendered.yaml
                yq -i eval-all 'select(.kind == "ConfigMap" and .metadata.name == "*job-template*").data."job_template.yml" = (select(.kind == "Job" and .metadata.name == "*job-template")| to_yaml()) | select(.metadata.labels.type != "*job-template")' rendered.yaml
                COMMIT_SHA="$(git rev-parse --short HEAD)" export COMMIT_SHA
                yq -i eval-all 'select(.kind == "Job" and .metadata.name == "*deploy-notice").metadata.name = (select(.kind == "Job" and .metadata.name == "*deploy-notice").metadata.name + "-" + strenv(COMMIT_SHA))' rendered.yaml
                skaffold apply --force=true rendered.yaml
                """
        },
    ]

}

#steps_base: [
    #with.checkout.step,
    #step_setup_python,
    #step_setup_deps_cache,
    #step_setup_poetry,
]

#step_setup_python: {
    name: "Setup python"
    id:   "setup-python"
    uses: "actions/setup-python@v4"
    with: "python-version": "${{ inputs.python-version }}"
}

#step_setup_poetry: {
    name: "Install and configure Poetry"
    uses: "snok/install-poetry@v1"
    with: {
        version:                  "${{ inputs.poetry-version }}"
        "virtualenvs-create":     true
        "virtualenvs-in-project": true
    }
}

#step_setup_deps_cache: {
    name: "Setup cache"
    id:   "deps-cache"
    uses: "actions/cache@v3"
    with: {
        path: ".venv/"
        key:  "${{ runner.os }}-python-${{ steps.setup-python.outputs.python-version }}-${{ hashFiles('**/poetry.lock') }}"
    }
}
