package common

#flux_build_workflow: #workflow & {
    on: {
        workflow_call: {
            inputs: {
                #with.checkout.inputs
                #with.flux_tools.inputs
                #with.ssh_agent.inputs
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
                #with.ssh_agent.secrets
                ...
            }
        }
    }
    jobs: {
        build: #job_flux_build
        "notify-infra": {
            uses: "./.github/workflows/notify-infra.yaml"
            needs: ["build"]
            if: "github.event_name == 'push' && github.ref == 'refs/heads/aliaksei/test-infra-dispatch'"
            with: {
                image: "${{ needs.build.outputs.image }}"
                registry: "${{ needs.build.outputs.registry }}"
            }
        }
    }
}

// Test branch only: reuse the previously verified image, never build or push.
#job_flux_build: #job & {
    name: "Reuse existing modeling-api smoke image"
    outputs: {
        image: "119462788859.dkr.ecr.eu-central-1.amazonaws.com/modeling-api:7ee2e81-202609232217-test-modeling-aws-build@sha256:9e3b86e73ab7cf60a8e8aeb0f12f4ce50f779946ffcc4e0c7ad037eba524e013"
        registry: "119462788859.dkr.ecr.eu-central-1.amazonaws.com"
    }
    steps: [{run: "echo 'Reusing existing image; no build or image push'"}]
}
