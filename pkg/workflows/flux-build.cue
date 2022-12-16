package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#flux_build_workflow & {
	name: string | *"Flux Skaffold Build"
}

