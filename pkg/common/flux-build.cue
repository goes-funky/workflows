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
                "push-to-aws-ecr": {
                    type: "boolean"
                    description: "Whether to push to our ECR registry in the AWS Artifacts account"
                    default: false
                }
                ...
            }
            secrets: {
                #with.gcloud_build.secrets
                #with.ssh_agent.secrets
                #with.aws_ecr.secrets
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
    "timeout-minutes": 20
    steps: [
        {
            name: "Checkout"
            if:   "!inputs.skip-checkout"
            uses: "actions/checkout@v4"
            with: {
                path: "./code"
            }
        },
        {
            name: "Setup buildkit"
            id:   "setup-buildkit"
            uses: "docker/setup-buildx-action@v3"
        },
        #with.expose_action_env.step,
        #with.custom_skaffold_build_script.step,
        {
            name: "Configure skaffold to build with buildkit"
            run: "cp ./code/${{ inputs.skaffold-file }} . && yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"../docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"${{ inputs.docker-file }}\"}}}}' ${{ inputs.skaffold-file }}"
        },
        #with.ssh_agent.step,
        #with.gcloud.step,
        #with.docker_artifacts_auth.step,
        {
            if:   "inputs.push-to-aws-ecr"
            name: "Configure AWS Credentials"
            uses: "aws-actions/configure-aws-credentials@v4"
            with: {
                "aws-region": "${{ secrets.aws-ecr-region }}"
                "role-to-assume": "${{ secrets.aws-ecr-role }}"
                "role-session-name": "integrations-push-image-session"
            }
        },
        {
            if:   "inputs.push-to-aws-ecr"
            name: "Login to Amazon ECR"
            id: "login-ecr"
            uses: "aws-actions/amazon-ecr-login@v2"
        },
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
                COMMIT_SHA="$(git -C ./code rev-parse HEAD)" && echo "COMMIT_SHA=$COMMIT_SHA" >> "$GITHUB_ENV"
                """
        },
        {
            name: "Add branch name to image tag on branch builds"
            if: "github.event.ref != 'refs/heads/main'"
            run: """
                BRANCH_NAME="${GITHUB_REF##*/}"
                BRANCH_NAME="${BRANCH_NAME//[^a-zA-Z0-9]/-}"
                yq -i ' .build.tagPolicy.customTemplate.template = "{{.SHORT_SHA}}-{{.DATETIME}}-{{.BRANCH}}"' ${{ inputs.skaffold-file }}
                yq -i ' .build.tagPolicy.customTemplate.components += {"name": "BRANCH","envTemplate": {"template": "{{.BRANCH_NAME}}"}}' ${{ inputs.skaffold-file }}
                echo BRANCH_NAME="${BRANCH_NAME}" >> "$GITHUB_ENV"
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
                COMMIT_SHA: "${{ env.COMMIT_SHA }}"
                BRANCH_NAME: "${{ env.BRANCH_NAME }}"
                PUSH_TO_SECONDARY_REGISTRY: "${{ inputs.push-to-aws-ecr }}"
                SECONDARY_REGISTRY: "${{ secrets.aws-ecr-registry }}"
            }
            run: "cd ./code && skaffold build --filename=../${{ inputs.skaffold-file }}"
        }
    ]
}
