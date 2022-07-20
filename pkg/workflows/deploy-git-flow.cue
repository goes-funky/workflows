package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#deploy_workflow & {
	name: "Deploy"
	on: {
		workflow_call: {
			inputs: {
				"development-branch": {
					type:        "string"
					description: "Development branch"
					default:     "develop"
					required:    false
				}
				"production-branch": {
					type:        "string"
					description: "Production branch"
					default:     "master"
					required:    false
				}
			}
		}
	}
	env: {
		SKAFFOLD_PUSH: "$${ github.event.ref == format('refs/heads/{0}', inputs.development-branch) || github.event.ref == format('refs/heads/{0}', inputs.production-branch)}"
	}
	jobs: {
		"deploy-development": {
			if:   "!inputs.skip-deploy && (github.event.ref == format('refs/heads/{0}', inputs.development-branch) || github.event.ref == format('refs/heads/{0}', inputs.production-branch))"
			environment: "${{ inputs.development-environment }}"
		}
		"deploy-production": {
			if:   "!inputs.skip-deploy && github.event.ref == format('refs/heads/{0}', inputs.production-branch)"
			environment: "${{ inputs.production-environment }}"
		}
	}
}
