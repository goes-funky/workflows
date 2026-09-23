package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#flux_build_aws_workflow & {
	name: string | *"Flux Skaffold AWS Build"
}
