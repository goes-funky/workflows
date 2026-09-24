package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#notify_infra_workflow & {
    name: "Notify infra of published image"
}
