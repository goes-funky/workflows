package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#deploy_workflow & {
	name: string | *"Deploy"
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
		"deploy-development": {
			if:   "!inputs.skip-deploy && (github.event.ref == format('refs/heads/{0}', inputs.development-branch) || startsWith(github.event.ref, 'refs/tags/v'))"
			environment: "${{ inputs.development-environment }}"
		}
		"deploy-production": {
			if:   "!inputs.skip-deploy && startsWith(github.event.ref, 'refs/tags/v')"
			environment: "${{ inputs.production-environment }}"
		}
	}
}

