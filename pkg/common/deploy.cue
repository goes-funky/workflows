package common

import "list"

#deploy_workflow: #workflow & {
	on: {
		workflow_call: {
			inputs: {
				"skaffold": {
					type:        "string"
					description: "Skaffold version"
					default:     "1.33.0"
				}
				"kubeval": {
					type:        "string"
					description: "Kubeval version"
					default:     "0.16.1"
				}
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
			}
			secrets: {
				"gcp-project-id": {
					description: "GCP Project ID"
					required:    true
				}
				"gcp-service-account": {
					description: "GCP Service Account Key"
					required:    true
				}
				"gke-cluster": {
					description: "GKE Cluster Name"
					required:    true
				}
				"gcp-gcr-project-id": {
					description: "GCP GCR Project ID"
					required:    true
				}
				"gcp-gcr-service-account": {
					description: "GCP GCR Service Account Key"
					required:    true
				}
				"gke-location": {
					description: "GKE Cluster Location (ignored in lieu of fully-qualified cluster ID)"
					required:    false
				}
				"ssh-private-key": {
					description: "SSH private key used to authenticate to GitHub with, in order to fetch private dependencies"
					required:    true
				}
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
		build:                #job_build
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
		{
			uses: "actions/checkout@v2"
		},
		{
			name: "Setup skaffold cache"
			uses: "actions/cache@v2"
			with: {
				path: "~/.skaffold/cache"
				key:  "${{ runner.os }}-skaffold"
			}
		},
		{
			uses: "actions/download-artifact@master"
			if:   "inputs.dist-artifact"
			with: {
				name: "${{ inputs.dist-artifact }}"
				path: "dist"
			}
		},
		#step_setup_ssh_agent,
		#step_auth_gcp & {
			with: {

				project_id:       "${{ secrets.gcp-gcr-project-id }}"
				credentials_json: "${{ secrets.gcp-gcr-service-account }}"
				token_format:     "access_token"
			}
		},
		#step_auth_gcr,
		{
			name: "Setup Kubernetes tools"
			uses: "yokawasa/action-setup-kube-tools@v0.7.1"

			with: {
				"setup-tools": """
					skaffold
					kubeval
					"""
				skaffold: "${{ inputs.skaffold }}"
				kubeval:  "${{ inputs.kubeval }}"
			}
		},
		{
			name: "Configure Skaffold"
			run:  "skaffold config set default-repo \"${{ inputs.default-repo }}\""
		},
		{
			name: "Build"
			run:  "skaffold build --file-output=build.json"
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
		{
		uses: "actions/checkout@v2"
	},
	#step_auth_gcp & {
		with: {
			project_id:       "${{ secrets.gcp-project-id }}"
			credentials_json: "${{ secrets.gcp-service-account }}"
		}
	},
	{
		uses: "google-github-actions/get-gke-credentials@v0.8.0"
		with: {
			cluster_name: "${{ secrets.gke-cluster }}"
		}
	},
	{
		name: "Download build reference"
		uses: "actions/download-artifact@v2"
		with: {
			name: "build-ref"
		}
	},
	{
		uses: "yokawasa/action-setup-kube-tools@v0.7.1"
		with: {
			"setup-tools": "skaffold"
			skaffold:      "${{ inputs.skaffold }}"
		}
	},
]

#step_auth_gcp: #step & {
	id: "auth_gcp"
	name: "Authenticate to GCP"
	uses: "google-github-actions/auth@v0"
}

#step_auth_gcr: #step & {
	name: "Authenticate to GCR"
	uses: "docker/login-action@v1"
	with: {
		registry: "eu.gcr.io"
		username: "oauth2accesstoken"
		password: "${{ steps.auth_gcp.outputs.access_token }}"
	}
}
