package common

#with: {
	checkout: {
		inputs: {
			"skip-checkout": {
				type:        "boolean"
				description: "Whether to skip checkout"
				default:     false
			}
		}

		step: #step & {
			name: "Checkout"
			if:   "!inputs.skip-checkout"
			uses: "actions/checkout@v3"
			with: {
			    "fetch-depth": "2"
			}
		}

	}

	ssh_agent: {
	    inputs: {
	    	"is-repo-public": {
                type:        "boolean"
                description: "Whether to skip ssh agent configuration"
                default:     false
            }
	    }

		secrets: {
			"ssh-private-key": {
				description: "SSH private key used to authenticate to GitHub with, in order to fetch private dependencies"
				required:    false
			}
		}

		step: #step & {
			name: "Setup SSH Agent"
			uses: "webfactory/ssh-agent@v0.5.4"
			if: "!inputs.is-repo-public"
			with: {
				"ssh-private-key": "${{ secrets.ssh-private-key }}"
			}
		}
	}

	kube_tools: {
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
		}

		step: #step & {
			name: "Setup Kubernetes tools"
			uses: "yokawasa/action-setup-kube-tools@v0.7.1"
			with: {} | *{
				"setup-tools": """
					skaffold
					kubeval
					"""
				skaffold: "${{ inputs.skaffold }}"
				kubeval:  "${{ inputs.kubeval }}"
			}
		}
	}

	gcloud: {
		secrets: {
			"gcp-project-id": {
				description: "GCP Project ID"
				required:    true
			}
			"gcp-service-account": {
				description: "GCP Service Account Key"
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
		}

		step: #step & {
			name: "Setup GCloud"
			uses: "google-github-actions/setup-gcloud@v0.2.1"
			with: {} | *{
				project_id:                 "${{ secrets.gcp-project-id }}"
				service_account_key:        "${{ secrets.gcp-service-account }}"
				export_default_credentials: true
				credentials_file_path:      "/tmp/2143f99e-4ec1-11ec-9d55-cbf168cabc9e"
			}
		}
	}

	gke: {
		secrets: {
			"gke-cluster": {
				description: "GKE Cluster Name"
				required:    true
			}
			"gke-location": {
				description: "GKE Cluster Location (ignored in lieu of fully-qualified cluster ID)"
				required:    false
			}
		}

		step: #step & {
			uses: "google-github-actions/get-gke-credentials@v0.8.0"
			with: {
				cluster_name: "${{ secrets.gke-cluster }}"
			}
		}
	}

	docker_auth: {
		step: #step & {
			name: "Configure Docker Auth"
			run:  "gcloud --quiet auth configure-docker eu.gcr.io"
		}
	}
}
