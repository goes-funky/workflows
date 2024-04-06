package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#workflow & {
    name: "Draft Release"
    on: {
        workflow_call: {
            inputs: {
                "type": {
                    type:        "string"
                    description: "Type"
                    required:    true
                }
            }

            secrets: {
                "github-token": {
                    description: "Github Token with repository write permissions"
                    required:    true
                }
            }
        }
    }

    jobs: {
        "create": {
            name: "Create draft release"
            steps: [
                {
                    uses: "actions/checkout@v4"
                    with: "fetch-depth": 0
                },
                {
                    name: "Determine previous tag"
                    id: "previous-tag"
                    uses: "WyriHaximus/github-action-get-previous-tag@v1"
                    with: fallback: "v0.0.0"
                },
                {
                    name: "Generate semvers"
                    id: "generate-semver"
                    uses: "WyriHaximus/github-action-next-semvers@v1"
                    with: version: "${{ steps.previous-tag.outputs.tag }}"
                },
                {
                    name: "Create draft release"
                    uses: "softprops/action-gh-release@master"
                    with: {
                        token: "${{ secrets.github-token }}"
                        draft: true
                        "tag_name": "${{ steps.generate-semver.outputs[format('v_{0}', github.event.inputs.type)] }}"
                        generate_release_notes: true
                    }
                },
            ]
        }
    }
}
