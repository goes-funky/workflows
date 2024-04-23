package common

#with: {
    checkout: {
        inputs: {
            "skip-checkout": {
                type:        "boolean"
                description: "Whether to skip checkout"
                default:     false
            }
            "with-submodules": {
                type:        "boolean"
                description: "Whether to fetch git submodules"
                default:     false
            }
        }

        step: #step & {
            name: "Checkout"
            if:   "!inputs.skip-checkout"
            uses: "actions/checkout@v4"
            with: {
                "submodules": "${{ inputs.with-submodules }}"
            }
        }
    }

    load_artifact: {
        inputs: {
            "project-artifact": {
                type:        "string"
                description: "Use project from artifact (instead of checking out repo)"
                default:     ""
            }
        }

        step: #step & {
            name: "Download artifact"
            uses: "actions/download-artifact@v3"
            if:   "inputs.project-artifact"
            with: {
                name: "${{ inputs.project-artifact }}"
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
            uses: "webfactory/ssh-agent@v0.9.0"
            if: "!inputs.is-repo-public"
            with: {
                "ssh-private-key": "${{ secrets.ssh-private-key }}"
            }
        }
    }

    trufflehog: {
        step: #step & {
            name: "Scan for Secrets"
            uses: "trufflesecurity/trufflehog@v3.22.0"
            with: {
                path: "./"
                base: "${{ github.event.repository.default_branch }}"
                head: "HEAD"
                extra_args: "--only-verified"
            }
        }
    }

    custom_skaffold_build_script: {
        step: #step & {
            name: "Download custom skaffold docker build script"
            run:  "curl -LsO https://raw.githubusercontent.com/goes-funky/workflows/master/scripts/docker-buildx && chmod +x docker-buildx"
        }
    }

    kube_tools: {
        inputs: {
            "skaffold": {
                type:        "string"
                description: "Skaffold version"
                default:     "1.39.2"
            }
            "kubeval": {
                type:        "string"
                description: "Kubeval version"
                default:     "0.16.1"
            }
        }

        step: #step & {
            name: "Setup Kubernetes tools"
            uses: "yokawasa/action-setup-kube-tools@v0.9.2"
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

    flux_tools: {
        inputs: {
            "skaffold": {
                type:        "string"
                description: "Skaffold version"
                default:     "1.39.2"
            }
        }

        step: #step & {
            name: "Setup Flux build tools"
            uses: "yokawasa/action-setup-kube-tools@v0.9.2"
            with: {} | *{
                "setup-tools": """
                    skaffold
                    """
                skaffold: "${{ inputs.skaffold }}"
            }
        }
    }

    gcloud_deploy: {
        secrets: {
            "gcp-service-account": {
                description: "GCP Service Account e-mail, has permission to artifact repo"
                required:    true
            }
            "gcp-workload-identity-provider": {
                description: "GCP Workload Identity provider"
                required: true
            }
            "gcp-gcr-service-account": {
                description: "GCP GCR Service Account e-mail"
                required:    true
            }
            "gcp-gcr-workload-identity-provider": {
                description: "GCP GCR Workload Identity provider"
                required: true
            }
        }
    }

    gcloud_build: {
        secrets: {
            "gcp-service-account": {
                description: "GCP Service Account e-mail, has permission to artifact repo"
                required:    true
            }
            "gcp-workload-identity-provider": {
                description: "GCP Workload Identity provider"
                required: true
            }
        }
    }

    gcloud: {
        step: #step & {
            id: "auth_gcp"
            name: "Authenticate to Google Cloud"
            uses: "google-github-actions/auth@v2"
            with: {} | *{
                service_account: "${{ secrets.gcp-service-account }}"
                workload_identity_provider: "${{ secrets.gcp-workload-identity-provider }}"
                token_format: "access_token"
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
            uses: "google-github-actions/get-gke-credentials@v1"
            with: {
                cluster_name: "${{ secrets.gke-cluster }}"
            }
        }
    }

    docker_auth: {
        step: #step & {
            id: "auth_gcr"
            name: "Authenticate to Google Container Registry"
            uses: "docker/login-action@v3"
            with: {
                    registry: "eu.gcr.io"
                    username: "oauth2accesstoken"
                    password: "${{ steps.auth_gcp.outputs.access_token }}"
            }
        }
    }

    docker_artifacts_auth: {
        step: #step & {
            id: "auth_docker_pkg_dev"
            name: "Authenticate to Google Artifact Registry"
            uses: "docker/login-action@v3"
            with: {
                    registry: "europe-west3-docker.pkg.dev"
                    username: "oauth2accesstoken"
                    password: "${{ steps.auth_gcp.outputs.access_token }}"
            }
        }
    }
    skaffold_cache: {
        step: #step & {
            name: "Setup skaffold cache"
            if:  "inputs.use-skaffold-cache"
            uses: "actions/cache@v4"
            with: {
                path: "~/.skaffold/cache"
                key:  "${{ runner.os }}-skaffold-${{ github.sha }}"
                "restore-keys": """
                    ${{ runner.os }}-skaffold-${{ github.sha }}
                    ${{ runner.os }}-skaffold
                    """
            }
        }
    }
    // For some reasons, some action's envs like ACTIONS_CACHE_URL,
    // ACTIONS_RUNTIME_TOKEN not being exposed to workflow steps so we use this
    // step as a workround to expose those envs for subsequent steps. It's
    // needed so that skaffold can work with buildkit + github action cache
    expose_action_env: {
        step: #step & {
            name: "Expose Github Action runtime"
            uses: "actions/github-script@v6"
            with: {
                script: """
                        try {
                            Object.keys(process.env).forEach(function (key) {
                                if (key.startsWith('ACTIONS_')) {
                                    core.info(`${key}=${process.env[key]}`);
                                    core.exportVariable(key, process.env[key]);
                                }
                            });
                        } catch (error) {
                            core.setFailed(error.message);
                        }
                        """
            }
        }
    }
}
