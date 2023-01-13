package common

#flux_build_workflow: #workflow & {
    on: {
        workflow_call: {
            inputs: {
                #with.checkout.inputs
                #with.flux_tools.inputs
                #with.ssh_agent.inputs
                "default-repo": {
                    type:        "string"
                    description: "Default artifact repository"
                    default:     "europe-west3-docker.pkg.dev/y42-artifacts-ea47981a/main"
                }
                "skaffold-file": {
                    type:        "string"
                    description: "Skaffold file to use"
                    default:    "skaffold.yaml"
                }
                "docker-file": {
                    type:        "string"
                    description: "Docker file to use"
                    default:    "Dockerfile"
                }
                ...
            }
            secrets: {
                #with.gcloud_flux.secrets
                #with.ssh_agent.secrets
                ...
            }
        }
    }
    jobs: {
        build: #job_flux_build
    }
}

#job_flux_build: #job & {
    name: "Build Docker images"
    "timeout-minutes": 10
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
            run: "cp ./code/${{ inputs.skaffold-file }} . && yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"../docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"${{ inputs.docker-file }}\"}}}}' ${{ inputs.skaffold-file }}"
        },
        #with.ssh_agent.step,
        #with.gcloud.step & {
            with: {
                project_id:       "${{ secrets.gcp-project-id }}"
                credentials_json: "${{ secrets.gcp-service-account }}"
                token_format:     "access_token"
            }
        },
        #with.docker_artifacts_auth.step,
        #with.flux_tools.step,
        {
            name: "Configure Skaffold"
            run:  "skaffold config set default-repo \"${{ inputs.default-repo }}\""
        },
        {
            name: "Export git build details"
            run: """
                CONTAINER_NAME=$(cd ./code && basename -s .git "$(git remote get-url origin)") && echo "CONTAINER_NAME=$CONTAINER_NAME" >> "$GITHUB_ENV"
                SHORT_SHA="$(git -C ./code rev-parse --short HEAD)" && echo "SHORT_SHA=$SHORT_SHA" >> "$GITHUB_ENV"
                """
        },
        {
            name: "Add prefix to image tag on branch builds"
            if: "github.event.ref != 'refs/heads/main'"
            run: """
                TAG_PREFIX="${GITHUB_REF##*/}-"
                TAG_PREFIX="${TAG_PREFIX//[^a-zA-Z0-9]/-}"
                yq -i ' .build.tagPolicy.customTemplate.template = "{{.PREFIX}}{{.SHORT_SHA}}-{{.DATETIME}}"' ${{ inputs.skaffold-file }}
                yq -i ' .build.tagPolicy.customTemplate.components += {"name": "PREFIX","envTemplate": {"template": "{{.TAG_PREFIX}}"}}' ${{ inputs.skaffold-file }}
                echo TAG_PREFIX="${TAG_PREFIX}" >> "$GITHUB_ENV"
                """
        },
        {
            name: "Build"
            env: {
                SKAFFOLD_DEFAULT_REPO:    "${{ inputs.default-repo }}"
                SKAFFOLD_CACHE_ARTIFACTS: "false"
                DOCKER_BUILDKIT_BUILDER:  "${{ steps.setup-buildkit.outputs.name }}"
                CONTAINER_NAME: "${{ env.CONTAINER_NAME }}"
                SHORT_SHA: "${{ env.SHORT_SHA }}"
                TAG_PREFIX: "${{ env.TAG_PREFIX }}"
            }
            run:  "cd ./code && skaffold build --filename=../${{ inputs.skaffold-file }}"
        }
    ]
}
