package common

import "list"

#deploy_workflow: #workflow & {
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
                }
                "dist-artifact": {
                    type:        "string"
                    description: "Dist artifact name"
                    required:    false
                }
                "untar-artifact-name": {
                    type:        "string"
                    description: "Name of the input artifact to untar"
                    required:    false
                }
                "skip-deploy": {
                    type:        "boolean"
                    description: "Skip deployment to cluster"
                    required:    false
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
                "use-skaffold-cache": {
                    type: "boolean"
                    required: false
                    default: true
                    description: "Setup skaffold cache before build"
                }
                ...
            }
            secrets: {
                #with.gcloud.secrets
                #with.gke.secrets
                #with.ssh_agent.secrets
                ...
            }
        }
    }
    jobs: {

        "deploy-development": #job_deploy_nonprod & {
            name: "Deploy to development"
            needs: ["build"]
        }

        "deploy-production": #job_deploy_prod & {
            name: "Deploy to production"
            needs: ["build", "deploy-development"]
        }

        build: #job_build

        "deploy-environment": #job_deploy_nonprod & {
            name:        "Deploy to environment"
            if:          "inputs.environment"
            environment: "${{ inputs.environment }}"
            needs: ["build"]
        }
    }
}

#job_build: #job & {
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
        #with.skaffold_cache.step,
        {
            uses: "actions/download-artifact@v3"
            if:   "inputs.dist-artifact"
            with: {
                name: "${{ inputs.dist-artifact }}"
                path: "./code/dist"
            }
        },
        #with.expose_action_env.step,
        {
            name: "Download docker-buildx"
            run:  "curl -LsO https://raw.githubusercontent.com/goes-funky/makefiles/master/scripts/skaffold/docker-buildx && chmod +x docker-buildx"
        },
        {
            name: "Configure skaffold to build with buildkit"
            run: "cp ./code/${{ inputs.skaffold-file }} . && yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"../docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"${{ inputs.docker-file }}\"}}}}' ${{ inputs.skaffold-file }}"
        },
        {
            name: "Untar build artifact"
            if: "inputs.untar-artifact-name"
            run: "tar -xf ./code/dist/${{ inputs.untar-artifact-name }} -C ./code/dist"
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
            name: "Build"
            env: {
                SKAFFOLD_DEFAULT_REPO:    "${{ inputs.default-repo }}"
                SKAFFOLD_CACHE_ARTIFACTS: "${{ inputs.use-skaffold-cache }}"
                DOCKER_BUILDKIT_BUILDER:  "${{ steps.setup-buildkit.outputs.name }}"
                CONTAINER_NAME: "${{ env.CONTAINER_NAME }}"
                SHORT_SHA:      "${{ env.SHORT_SHA }}"
            }
            run:  "cd ./code && skaffold build --filename=../${{ inputs.skaffold-file }} --file-output=build.json"
        },
        {
            name: "Archive build reference"
            uses: "actions/upload-artifact@v3"
            with: {
                name: "build-${{ inputs.skaffold-file }}"
                path: "./code/build.json"
            }
        },
    ]
}

#job_deploy_nonprod: #job & {
    steps: list.Concat(
        [
            #steps_deploy, [
                {
                    name: "Deploy"
                    env: {
                        SKAFFOLD_PROFILE: "${{ (inputs.environment == inputs.production-environment) && 'prod' || 'nonprod' }}"
                    }
                    run: "skaffold deploy --filename=${{ inputs.skaffold-file }} --force --build-artifacts=build.json"
                },
            ]])
}

#job_deploy_prod: #job & {
    steps: list.Concat(
        [
            #steps_deploy, [
                {
                    name: "Deploy"
                    run:  "skaffold deploy --filename=${{ inputs.skaffold-file }} --profile prod --force --build-artifacts=build.json"
                },
            ]])
}

#steps_deploy: [...#step] & [
        #with.checkout.step,
        #with.gcloud.step,
        #with.gke.step,
        {
        name: "Download build reference"
        uses: "actions/download-artifact@v3"
        with: {
            name: "build-${{ inputs.skaffold-file }}"
        }
    },
    #with.kube_tools.step &
    {
        with: {
            "setup-tools": "skaffold"
            skaffold:      "${{ inputs.skaffold }}"
        }
    },
]
