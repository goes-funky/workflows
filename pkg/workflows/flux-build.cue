package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#flux_build_workflow & {
	name: string | *"Flux Skaffold Build"
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
}

