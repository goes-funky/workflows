package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#deploy_integration_workflow & {
    name: "Deploy Integration"
    on: {
        workflow_call: {
            inputs: {
                "development-branch": {
                    type:        "string"
                    description: "Development branch"
                    default:     "${{ github.event.repository.default_branch }}"
                    required:    false
                }
            }
        }
    }
    env: {
        SKAFFOLD_PUSH: "$${ github.event.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.event.ref, 'refs/tags/v') }"
    }
    jobs: {
        "integration-schema-generate-development": {
            if:   "!inputs.skip-integration-schema-generate && (github.event.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.event.ref, 'refs/tags/v'))"
        }
        "integration-schema-generate-production": {
            if:   "!inputs.skip-integration-schema-generate && startsWith(github.event.ref, 'refs/tags/v')"
        }
        "deploy-development": {
            if:   "!inputs.skip-deploy && (github.event.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.event.ref, 'refs/tags/v'))"
        }
        "deploy-production": {
            if:   "!inputs.skip-deploy && startsWith(github.event.ref, 'refs/tags/v')"
        }
    }
}
