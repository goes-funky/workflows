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
        SKAFFOLD_PUSH: "${{ github.event_name != 'pull_request' && (github.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.ref, 'refs/tags/v') || inputs.environment != '') }}"
    }
    jobs: {
        "integration-schema-generate-development": {
            if:   "!inputs.environment && !inputs.skip-integration-schema-generate && (github.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.ref, 'refs/tags/v'))"
        }
        "integration-schema-generate-production": {
            if:   "!inputs.environment && !inputs.skip-integration-schema-generate && startsWith(github.ref, 'refs/tags/v')"
        }
        "deploy-development": {
            if:   "!inputs.environment && !inputs.skip-deploy && (github.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.ref, 'refs/tags/v'))"
        }
        "deploy-production": {
            if:   "!inputs.environment && !inputs.skip-deploy && startsWith(github.ref, 'refs/tags/v')"
        }
    }
}
