package common

import "list"

#deploy_workflow: #workflow & {
	on: {
		workflow_call: {
			inputs: {
				#with.checkout.inputs
				#with.kube_tools.inputs
				#with.ssh_agent.inputs
				"environment": {
					type:        "string"
					description: "Deployment environment"
					required:    false
				}
				"development-environment": {
					type:        "string"
					description: "Development environment"
					default:     "dev"
					required:    false
				}
				"production-environment": {
					type:        "string"
					description: "Production environment"
					default:     "prod"
					required:    false
				}
				"default-repo": {
					type:        "string"
					description: "Default artifact repository"
					default:     "eu.gcr.io/y42-artifacts-ea47981a"
				}
				"dist-artifact": {
					type:        "string"
					description: "Dist artifact name"
					required:    false
				}
				"skip-deploy": {
					type:        "boolean"
					description: "Skip deployment to cluster"
					required:    false
				}
				...
			}
			secrets: {
				#with.gcloud.secrets
				#with.gke.secrets
				#with.ssh_agent.secrets
				...
			}
		}
	}
	jobs: {

		"deploy-development": #job_deploy_nonprod & {
			name: "Deploy to development"
			needs: ["build"]
		}

		"deploy-production": #job_deploy_prod & {
			name: "Deploy to production"
			needs: ["build", "deploy-development"]
		}

		build: #job_build

		"deploy-environment": #job_deploy_nonprod & {
			name:        "Deploy to environment"
			if:          "inputs.environment"
			environment: "${{ inputs.environment }}"
			needs: ["build"]
		}
	}
}

#job_build: #job & {
	name: "Build Docker images"
	steps: [
		#with.checkout.step,
		{
			name: "Setup buildkit"
			id:   "setup-buildkit"
			uses: "docker/setup-buildx-action@v1"
		},
		{
			name: "Expose Github Action runtime"
			uses: "crazy-max/ghaction-github-runtime@v2"
		},
		{
			name: "Download docker-buildx"
			run:  "curl -LsO https://raw.githubusercontent.com/goes-funky/makefiles/master/scripts/skaffold/docker-buildx && chmod +x docker-buildx"
		},
		{
			name: "Configure skaffold to build with buildkit"
			run: "yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"./docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"Dockerfile\"}}}}' skaffold.yaml"
		},
		{
			uses: "actions/download-artifact@master"
			if:   "inputs.dist-artifact"
			with: {
				name: "${{ inputs.dist-artifact }}"
				path: "dist"
			}
		},
		#with.ssh_agent.step,
		#with.gcloud.step & {
			with: {
				project_id:                 "${{ secrets.gcp-gcr-project-id }}"
				service_account_key:        "${{ secrets.gcp-gcr-service-account }}"
				export_default_credentials: true
				credentials_file_path:      "/tmp/2143f99e-4ec1-11ec-9d55-cbf168cabc9e"
			}
		},
		#with.docker_auth.step,
		#with.kube_tools.step,
		{
			name: "Build"
			env: {
				SKAFFOLD_DEFAULT_REPO:    "${{ inputs.default-repo }}"
				SKAFFOLD_CACHE_ARTIFACTS: "false"
				DOCKER_BUILDKIT_BUILDER:  "${{ steps.setup-buildkit.outputs.name }}"
			}
			run: "skaffold build --file-output=build.json"
		},
		{
			name: "Archive build reference"
			uses: "actions/upload-artifact@v2"
			with: {
				name: "build-ref"
				path: "build.json"
			}
		},
	]
}

#job_deploy_nonprod: #job & {
	steps: list.Concat(
		[
			#steps_deploy, [
				{
					name: "Deploy"
					env: {
						SKAFFOLD_PROFILE: "${{ (inputs.environment == inputs.production-environment && github.event.ref != format('refs/heads/{0}', inputs.development-branch)) && 'prod' || 'nonprod' }}"
					}
					run: "skaffold deploy --force --build-artifacts=build.json"
				},
			]])
}

#job_deploy_prod: #job & {
	steps: list.Concat(
		[
			#steps_deploy, [
				{
					name: "Deploy"
					run:  "skaffold deploy --profile prod --force --build-artifacts=build.json"
				},
			]])
}

#steps_deploy: [...#step] & [
		#with.checkout.step,
		#with.gcloud.step,
		#with.gke.step,
		{
		name: "Download build reference"
		uses: "actions/download-artifact@v2"
		with: {
			name: "build-ref"
		}
	},
	#with.kube_tools.step &
	{
		with: {
			"setup-tools": "skaffold"
			skaffold:      "${{ inputs.skaffold }}"
		}
	},
]
