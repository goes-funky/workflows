package common

#build_workflow: #workflow & {
	name: string
	on: {
		workflow_call: {
			inputs: {
				"skip-checkout": {
					type:        "boolean"
					description: "Whether to skip checkout"
					default:     false
				}
				...
			}
			secrets: {
				"ssh-private-key": {
					description: "SSH private key used to authenticate to GitHub with, in order to fetch private dependencies"
					required:    false
				}
				...
			}
		}
	}
}

#step_checkout: #step & {
	name: "Checkout"
	if:   "!inputs.skip-checkout"
	uses: "actions/checkout@v2"
}

#step_setup_ssh_agent: #step & {
	name: "Setup SSH Agent"
	uses: "webfactory/ssh-agent@v0.5.4"
	with: {
		"ssh-private-key": "${{ secrets.ssh-private-key }}"
	}
	if: "${{ secrets.ssh-private-key != '' }}"
}
