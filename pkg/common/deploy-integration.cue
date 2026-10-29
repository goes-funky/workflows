package common

import "list"

#deploy_integration_workflow: #workflow & {
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
                    default:     "119462788859.dkr.ecr.eu-central-1.amazonaws.com"
                    required:    false
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
                "skip-build": {
                    type:        "boolean"
                    description: "Skip build to cluster"
                    required:    false
                }
                "tap-template-name": {
                    type: "string"
                    description: "Opt in to GitOps tap releases; directory name under integrations/taps"
                    default: ""
                    required: false
                }
                "skip-job-template-build": {
                    type:        "boolean"
                    description: "Job-template configmap building for deploy of tap containers"
                    default:     false
                    required:    false
                }
                "skip-integration-schema-generate": {
                    type:        "boolean"
                    description: "Whether to skip integration json schema generation & upload"
                    default:     false
                    required:    false
                }
                "integration-schema-command": {
                    type:        "string"
                    description: "The command to run to generate the integration schema"
                    default:     "poetry run python -m datos_integrations.commands.generate_schemas --outpath=./integrations --version=0.0.0"
                    required:    false
                }
                "python-version": {
                    type:        "string"
                    description: "Python version"
                    default:     "3.9"
                    required:    false
                }
                "poetry-version": {
                    type:        "string"
                    description: "Poetry version"
                    default:     "1.1.15"
                    required:    false
                }
                // Know issue installing some packages. Resolved past poetry v1.2 which is currently in beta https://github.com/python-poetry/poetry/issues/4511
                "setuptools-version": {
                    type:        "string"
                    description: "Force poetry setuptools version"
                    default:     "57.5.0"
                }
                "skip-checkout": {
                    type:        "boolean"
                    description: "Whether to skip checkout"
                    default:     false
                }
                "use-skaffold-cache": {
                    type: "boolean"
                    required: false
                    default: false
                    description: "Setup skaffold cache before build"
                }
                ...
            }
            secrets: {
                #with.ssh_agent.secrets
                "integrations-token": {
                    description: "Token with contents and pull requests write on goes-funky/integrations, for GitOps taps"
                    required: false
                }
                ...
            }
        }

    }

    jobs: {
        "integration-schema-generate-development": {
            name: "Upload Integration Schema to dev"
            needs: ["deps", "build"]
            environment: "${{ inputs.development-environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        "integration-schema-generate-production": {
            name: "Upload Integration Schema to prod"
            needs: ["deps", "build", "integration-schema-generate-development", "deploy-development"]
            if:          string | *"inputs.environment"
            environment: "${{ inputs.production-environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        "deploy-development": {
            name: "Deploy to development"
            needs: ["build"]
            environment: "${{ inputs.development-environment }}"
            env: TARGET_ENVIRONMENT: "${{ inputs.development-environment }}"
            steps:       #integration_steps.deploy_integration
        }

        "deploy-production": {
            name: "Deploy to production"
            needs: ["build", "deploy-development"]
            environment: "${{ inputs.production-environment }}"
            env: TARGET_ENVIRONMENT: "${{ inputs.production-environment }}"
            steps:       #integration_steps.deploy_integration
        }

        deps: {
            name:  "Dependencies"
            steps: #integration_steps.dependencies
        }

        "integration-schema-generate-environment": {
            name: "Upload Integration Schema to env"
            needs: ["deps", "build"]
            if:          "inputs.environment && !inputs.skip-integration-schema-generate"
            environment: "${{ inputs.environment }}"
            steps:       #integration_steps.json_scheme_generate
        }

        build: {
            name: "Build Docker images"
            steps: [
                {
                    name: "Checkout"
                    if:   "!inputs.skip-checkout"
                    uses: "actions/checkout@v4"
                    with: {
                        path: "./code"
                    }
                },
                {
                    name: "Setup buildkit"
                    id:   "setup-buildkit"
                    uses: "docker/setup-buildx-action@v3"
                },
                #with.expose_action_env.step,
                #with.custom_skaffold_build_script.step,
                {
                    name: "Configure skaffold to build with buildkit"
                    run:  "cp ./code/skaffold.yaml . && yq -i 'del(.build.local) | del(.build.artifacts.[].docker) | del(.build.artifacts.[].sync.*) | .build.artifacts.[] *= {\"custom\": {\"buildCommand\": \"../docker-buildx\", \"dependencies\": {\"dockerfile\": {\"path\": \"Dockerfile\"}}}}' skaffold.yaml"
                },
                #with.skaffold_cache.step,
                {
                    name: "Download artifact"
                    uses: "actions/download-artifact@v4"
                    if:   "inputs.dist-artifact"
                    with: {
                        name: "${{ inputs.dist-artifact }}"
                        path: "./code/dist"
                    }
                },
                #with.ssh_agent.step,
                #integration_aws_registry_auth,
                #integration_aws_registry_login,
                #with.kube_tools.step,
                {
                    name: "Export git build details"
                    env: REPO: "${{ inputs.default-repo }}"
                    run: """
                        CONTAINER_NAME=$(cd ./code && basename -s .git "$(git remote get-url origin)") && echo "CONTAINER_NAME=$CONTAINER_NAME" >> "$GITHUB_ENV"
                        SHORT_SHA="$(git -C ./code rev-parse --short HEAD)" && echo "SHORT_SHA=$SHORT_SHA" >> "$GITHUB_ENV"
                        COMMIT_SHA="$(git -C ./code rev-parse HEAD)" && echo "COMMIT_SHA=$COMMIT_SHA" >> "$GITHUB_ENV"
                        IMAGE_NAME="$REPO/$CONTAINER_NAME:$SHORT_SHA" && echo "IMAGE_NAME=$IMAGE_NAME" >> "$GITHUB_ENV"
                        """
                },
                {
                    name: "Configure Skaffold"
                    // env: REPO: "${{ inputs.default-repo }}"
                    run: "skaffold config set default-repo '${{ inputs.default-repo }}'"
                },
                {
                    name: "Build"
                    if:   "!inputs.skip-build"
                    env: {
                        CONTAINER_NAME: "${{ env.CONTAINER_NAME }}"
                        SHORT_SHA:      "${{ env.SHORT_SHA }}"
                        COMMIT_SHA:     "${{ env.COMMIT_SHA }}"
                        IMAGE_NAME:     "${{ env.IMAGE_NAME }}"
                        SKAFFOLD_DEFAULT_REPO:    "${{ inputs.default-repo }}"
                        SKAFFOLD_CACHE_ARTIFACTS: "${{ inputs.use-skaffold-cache }}"
                        DOCKER_BUILDKIT_BUILDER:  "${{ steps.setup-buildkit.outputs.name }}"
                    }
                    run: "cd ./code && skaffold build --filename=../skaffold.yaml --file-output=build.json"
                },
                {
                    name: "Archive build reference"
                    if:   "!inputs.skip-build"
                    uses: "actions/upload-artifact@v4"
                    with: {
                        name: "build-ref"
                        path: "./code/build.json"
                    }
                },
            ]
        }

        "deploy-environment": {
            name: "Deploy to environment"
            needs: ["build"]
            if:          "inputs.environment && !inputs.skip-deploy"
            environment: "${{ inputs.environment }}"
            env: TARGET_ENVIRONMENT: "${{ inputs.environment }}"
            steps:       #integration_steps.deploy_integration
        }
    }
}

#integration_steps: {
    dependencies: list.Concat(
            [
                #steps_base,
                [
                    #with.ssh_agent.step,
                    {
                    name: "Configure setup tools for poetry"
                    if:   "inputs.setuptools-version"
                    env: SETUPTOOLS_VERSION: "${{ inputs.setuptools-version }}"
                    run: "poetry run pip install \"setuptools==$SETUPTOOLS_VERSION\""
                },
                {
                    name: "Download dependencies"
                    run: """
                        git config --global url."git@github.com:".insteadOf "https://github.com/"
                        poetry install
                        """
                },
            ],
        ])

    json_scheme_generate: list.Concat(
                [#steps_base,
                    [{
                name: "Generate Integration JSON schema"
                env: {
                    GENERATE_SCHEMA_COMMAND: "${{ inputs.integration-schema-command }}"
                    DEPLOY_ENVIRONMENT:      "${{ inputs.environment }}"
                }
                run: """
                    KAFKA_SERVERS='' export KAFKA_SERVERS
                    KAFKA_SASL_KEY=''  export KAFKA_SASL_KEY
                    KAFKA_SASL_SECRET='' export KAFKA_SASL_SECRET
                    CONTAINER_MODULE=$(basename -s .git "$(git remote get-url origin | sed 's/-/_/g')" ) export CONTAINER_MODULE
                    eval "$GENERATE_SCHEMA_COMMAND"
                    """
            },
                {
                    name: "Configure AWS credentials"
                    uses: "aws-actions/configure-aws-credentials@v4"
                    with: {
                        "role-to-assume": "${{ vars.AWS_PUBLIC_SCHEMAS_ROLE }}"
                        "aws-region": "${{ vars.AWS_PUBLIC_SCHEMAS_REGION }}"
                    }
                },
                {
                    name: "Upload Integration schema to S3"
                    env: SCHEMA_BUCKET: "${{ vars.AWS_PUBLIC_SCHEMAS_BUCKET }}"
                    // Public schema URLs retain the integrations/ prefix.
                    run: """
                        aws s3 cp integrations/ "s3://$SCHEMA_BUCKET/integrations/" --recursive --content-type application/json --cache-control 'public, max-age=300'
                        """
                }],
        ])

    deploy_integration: [
        {
            name: "Validate GitOps release configuration"
            if: "inputs.tap-template-name != ''"
            env: INTEGRATIONS_TOKEN: "${{ secrets.integrations-token }}"
            run: """
                test -n "$INTEGRATIONS_TOKEN" || { echo "integrations-token is required for GitOps tap releases" >&2; exit 1; }
                case "$TARGET_ENVIRONMENT" in dev|prod) ;; *) echo "GitOps taps support dev and prod only" >&2; exit 1;; esac
                """
        },
        #with.checkout.step,
        #with.ssh_agent.step,
        #integration_aws_registry_auth,
        #integration_aws_registry_login,
        {
            name: "Authenticate to the AWS deployment environment"
            uses: "aws-actions/configure-aws-credentials@v4"
            with: {
                "role-to-assume": "${{ vars.AWS_INTEGRATIONS_DEPLOY_ROLE }}"
                "aws-region": "${{ vars.AWS_EKS_REGION }}"
                "unset-current-credentials": true
            }
        },
        {
            name: "Configure EKS credentials"
            env: {
                CLUSTER_NAME: "${{ vars.AWS_EKS_CLUSTER }}"
                CLUSTER_REGION: "${{ vars.AWS_EKS_REGION }}"
            }
            run: "aws eks update-kubeconfig --name \"$CLUSTER_NAME\" --region \"$CLUSTER_REGION\""
        },
        {
            name: "Download build reference"
            uses: "actions/download-artifact@v4"
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
        {
            name: "Deploy"
            if:   "inputs.skip-job-template-build && !inputs.tap-template-name"
            run:  "skaffold deploy --force --build-artifacts=build.json"
        },
        {
            name: "Deploy tap container with job-template"
            if:   "!inputs.skip-job-template-build && !inputs.tap-template-name"
            run: """
                skaffold render --offline=true --build-artifacts=build.json > rendered.yaml
                yq -i eval-all 'select(.kind == "ConfigMap" and .metadata.name == "*job-template*").data."job_template.yml" = (select(.kind == "Job" and .metadata.name == "*job-template")| to_yaml()) | select(.metadata.labels.type != "*job-template")' rendered.yaml
                COMMIT_SHA="$(git rev-parse --short HEAD)" export COMMIT_SHA
                yq -i eval-all 'select(.kind == "Job" and .metadata.name == "*deploy-notice").metadata.name = (select(.kind == "Job" and .metadata.name == "*deploy-notice").metadata.name + "-" + strenv(COMMIT_SHA))' rendered.yaml
                skaffold apply --force=true rendered.yaml
                yq 'select(.kind == "Job" and .metadata.name == "*deploy-notice-*")' rendered.yaml | kubectl wait --for=condition=complete --timeout=300s -f -
                """
        },
        {
            name: "Publish OAuth settings for GitOps tap"
            if: "inputs.tap-template-name != ''"
            env: RELEASE_ID: "${{ github.run_id }}-${{ github.run_attempt }}"
            run: """
                skaffold render --offline=true --build-artifacts=build.json > rendered.yaml
                # Opted-in manifests must contain only the OAuth notice and tap-config.
                yq -e 'select(.kind == "Job" and .metadata.name == "*deploy-notice") | .spec.template.spec.containers[0].args[0] | contains("--auth-only")' rendered.yaml
                test "$(yq 'select(.kind == "Job") | .metadata.name' rendered.yaml | grep -c .)" -eq 1
                test -z "$(yq 'select(.kind == "ConfigMap" and .metadata.name == "*job-template*") | .metadata.name' rendered.yaml)"
                yq -i 'select(.kind == "Job").metadata.name += "-" + strenv(RELEASE_ID)' rendered.yaml
                skaffold apply --force=true rendered.yaml
                yq 'select(.kind == "Job")' rendered.yaml | kubectl wait --for=condition=complete --timeout=300s -f -
                """
        },
        {
            name: "Checkout authoritative tap templates"
            if: "inputs.tap-template-name != ''"
            uses: "actions/checkout@v4"
            with: {
                repository: "goes-funky/integrations"
                ref: "main"
                path: ".integrations"
                "fetch-depth": 0
                token: "${{ secrets.integrations-token }}"
            }
        },
        {
            name: "Prepare environment-specific tap image update"
            if: "inputs.tap-template-name != ''"
            env: {
                TAP_TEMPLATE: "${{ inputs.tap-template-name }}"
                CONNECTOR_REPOSITORY: "${{ github.repository }}"
            }
            run: """
                python3 -m pip install 'PyYAML==6.0.2'
                python3 .integrations/scripts/update_tap_image.py --integration "$TAP_TEMPLATE" --environment "$TARGET_ENVIRONMENT" --image-name "${CONNECTOR_REPOSITORY##*/}" --build build.json
                """
        },
        {
            name: "Checkout signed commit helper"
            if: "inputs.tap-template-name != ''"
            uses: "actions/checkout@v4"
            with: {
                repository: "goes-funky/infra"
                // Reuse the reviewed signer without the infra dispatch/IAM path.
                ref: "d457527b382c4e14366a819c721e5562cf3ac2d3"
                path: ".infra-signing"
                "ssh-key": "${{ secrets.ssh-private-key }}"
                "persist-credentials": false
                "sparse-checkout": "scripts/image-update-branches.js"
                "sparse-checkout-cone-mode": false
            }
        },
        {
            name: "Propose tap image release"
            id: "tap-release"
            if: "inputs.tap-template-name != ''"
            env: {
                GH_TOKEN: "${{ secrets.integrations-token }}"
                TARGET_REPOSITORY: "goes-funky/integrations"
                TAP_TEMPLATE: "${{ inputs.tap-template-name }}"
                SOURCE_REPOSITORY: "${{ github.repository }}"
                SOURCE_SHA: "${{ github.sha }}"
                SOURCE_RUN: "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
            run: """
                cd .integrations
                node <<'NODE'
                const fs = require('node:fs')
                const { execFileSync } = require('node:child_process')
                const { fetchBranch, pushSignedCommit } = require('../.infra-signing/scripts/image-update-branches')
                const run = (cmd, args, input) => execFileSync(cmd, args, { encoding: 'utf8', input }).trim()
                const git = (...args) => run('git', args)
                const gh = (...args) => run('gh', args)
                const env = process.env
                // Adapt the existing helper inside this process; runner GITHUB_* defaults cannot be overridden by workflow env.
                env.GITHUB_REPOSITORY = env.TARGET_REPOSITORY
                const environment = env.TARGET_ENVIRONMENT
                if (!['dev', 'prod'].includes(environment) || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(env.TAP_TEMPLATE)) throw new Error('Invalid tap release target')
                const file = `integrations/taps/${env.TAP_TEMPLATE}/${environment}/job_template.yaml`
                const branch = `tap-release/${env.TAP_TEMPLATE}/${environment}`
                const base = git('rev-parse', 'HEAD')
                const changed = git('diff', '--name-only')
                const openPRs = () => JSON.parse(gh('pr', 'list', '--repo', env.GITHUB_REPOSITORY, '--base', 'main', '--head', branch, '--state', 'open', '--json', 'number,url,headRefOid'))
                if (!changed) {
                    const obsolete = openPRs()
                    if (obsolete.length > 1) throw new Error('Expected at most one release PR')
                    if (obsolete.length) {
                        const previous = fetchBranch(branch)
                        if (!previous || previous !== obsolete[0].headRefOid) throw new Error('Release branch changed; retry cleanup')
                        const ancestor = git('merge-base', base, previous)
                        if (git('diff', '--name-only', ancestor, previous) !== file) throw new Error('Refusing to close a proposal with unrelated changes')
                        run('python3', ['-c', 'import json,sys; from scripts.update_tap_image import validate_image_change; validate_image_change(*json.load(sys.stdin))'],
                            JSON.stringify([git('show', `${ancestor}:${file}`), git('show', `${previous}:${file}`)]))
                        gh('pr', 'close', String(obsolete[0].number), '--repo', env.GITHUB_REPOSITORY)
                    }
                    console.log('Image is already pinned on main; no release needed')
                    process.exit(0)
                }
                if (changed !== file) throw new Error('Refusing to publish changes outside the selected template')
                const previousHead = fetchBranch(branch)
                git('diff', '--check')
                git('add', '--', file)
                // This commit is local only. The helper signs on an isolated branch,
                // verifies signature and tree, then publishes using a guarded lease.
                git('-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com', '-c', 'commit.gpgsign=false',
                    'commit', '-m', `Update ${env.TAP_TEMPLATE} image in ${environment}`)
                const sameTree = previousHead && git('rev-parse', `${previousHead}^{tree}`) === git('rev-parse', 'HEAD^{tree}')
                const alreadySigned = sameTree && JSON.parse(gh('api', `repos/${env.GITHUB_REPOSITORY}/commits/${previousHead}`)).commit.verification.verified
                if (!alreadySigned) pushSignedCommit(branch, base, previousHead, [file])
                const title = `Release ${env.TAP_TEMPLATE} to ${environment}`
                const body = `Updates the broker template shared by all aliases with the digest-pinned build image.

                Source: ${env.SOURCE_REPOSITORY}@${env.SOURCE_SHA}
                Build: ${env.SOURCE_RUN}

                DEV uses the existing bot approval/auto-merge policy after image-only validation and required checks. PROD requires manual review and merge. Flux deploys after merge; PR creation alone is not a completed rollout.`
                const prs = openPRs()
                if (prs.length > 1) throw new Error('Expected at most one release PR')
                const label = environment === 'dev' ? 'flux-dev-update' : 'flux-prod-update'
                let url
                if (prs.length) {
                    run('gh', ['pr', 'edit', String(prs[0].number), '--repo', env.GITHUB_REPOSITORY, '--title', title, '--add-label', label, '--body-file', '-'], body)
                    url = prs[0].url
                } else {
                    url = run('gh', ['pr', 'create', '--repo', env.GITHUB_REPOSITORY, '--base', 'main', '--head', branch, '--title', title, '--label', label, '--body-file', '-'], body)
                }
                fs.appendFileSync(env.GITHUB_OUTPUT, `pull-request-url=${url}\n`)
                NODE
                """
        },
        {
            name: "Report template release proposal"
            if: "inputs.tap-template-name != ''"
            env: PR_URL: "${{ steps.tap-release.outputs.pull-request-url }}"
            run: """
                echo "Template release proposal: ${PR_URL:-no image change}. DEV auto-merges after checks; PROD requires manual review/merge. Broker rollout follows Flux reconciliation." >> "$GITHUB_STEP_SUMMARY"
                """
        },
    ]

}

#steps_base: [
    #with.checkout.step,
    #step_setup_python,
    #step_setup_deps_cache,
    #step_setup_poetry,
]

#step_setup_python: {
    name: "Setup python"
    id:   "setup-python"
    uses: "actions/setup-python@v5"
    with: "python-version": "${{ inputs.python-version }}"
}

#step_setup_poetry: {
    name: "Install and configure Poetry"
    uses: "snok/install-poetry@v1"
    with: {
        version:                  "${{ inputs.poetry-version }}"
        "virtualenvs-create":     true
        "virtualenvs-in-project": true
    }
}

#step_setup_deps_cache: {
    name: "Setup cache"
    id:   "deps-cache"
    uses: "actions/cache@v4"
    with: {
        path: ".venv/"
        key:  "${{ runner.os }}-python-${{ steps.setup-python.outputs.python-version }}-${{ hashFiles('**/poetry.lock') }}"
    }
}

// Registry credentials remain in Docker's config when deployment switches to
// the environment's EKS role. The deployment role itself needs no ECR grant.
#integration_aws_registry_auth: {
    name: "Authenticate to AWS Artifacts"
    uses: "aws-actions/configure-aws-credentials@v4"
    with: {
        "role-to-assume": "${{ vars.AWS_ARTIFACTS_ECR_ROLE }}"
        "aws-region": "${{ vars.AWS_ARTIFACTS_ECR_REGION }}"
    }
}

#integration_aws_registry_login: {
    name: "Log in to Amazon ECR"
    uses: "aws-actions/amazon-ecr-login@v2"
}
