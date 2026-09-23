# CI/CD Reusable Workflows

## Deployment workflow

To automate deployment process DevOps team has created [reusable workflow](https://github.com/goes-funky/workflows/blob/master/.github/workflows/deploy.yaml) that can be referenced in your repo GitHub Actions configuration.

### Flow

- push to default branch (`master` or `main`) triggers deployment to `development`
- creating `v[semver]` tag triggers deployment to `development` first, if it succeeded then deployment to `production` follows, requiring a manual approval from `group-backend-deployers`.
- hotfixes can be deployed to `production` by checking out branch from tagged release and manually triggering workflow
- arbitrary branches can be deployed to `development`/`demo` by triggering workflow

### Stages

- Docker image is built and pushed to artifact registry
- Deployment is verified using [kubeval](https://github.com/instrumenta/kubeval)
- Deployment is run against environment, waiting for resources liveness and readiness probes if specified

### Triggering deployment manually

#### Using GitHub UI

Navigate to `build` workflow in your repository.

Click on `Run workflow`:

![](https://static.slab.com/prod/uploads/m2v4jwak/posts/images/-onVtjGRv2xb7EOXwXsCSRH9.png)

Select desired branch and environment and run workflow:

![](https://static.slab.com/prod/uploads/m2v4jwak/posts/images/utNxpHCSBNZ04nrTn6njFdg4.png)

#### Using GitHub CLI

Install GitHub CLI:

`brew install gh`

Trigger deployment:

`gh workflow run --ref build -f environment=`

Example:

`gh workflow run --ref feat-teams-api build -f environment=demo`

### Hotfix deployments

Create branch from last tagged release:

`git checkout -b hotfix- $(git tag --sort=committerdate | grep -E '^v.*' | tail -1)`

Trigger deployment:

`gh workflow run --ref hotfix- build -f environment=production`

Example:

`git checkout -b hotfix-roles-config $(git tag --sort=committerdate | grep -E '^v.*' | tail -1)`

`gh workflow run --ref hotfix-roles-config -f environment=production`\

## Contributing

We use [CUE](https://cuelang.org) to manage and generate actual workflows.
Don't make any direct change in `.github/workflows` folder, it will be overwritten.

Contributing flow:
- Changes should be made within `pkg/*`
- Run `make` to generate actual workflows
- Commit your change for both `pkg/*` and generated workflows in `.github/workflows`
- PR time!


## Integration pipelines on AWS

`deploy-integration.yaml` builds images in the shared AWS ECR registry, publishes
schemas to S3 and deploys Kubernetes resources to the environment's EKS cluster.
Schema paths retain the `integrations/` prefix and `public, max-age=300` metadata.
Existing tags, generation commands and build/deployment dependencies are retained.
Manual environment jobs honor `skip-deploy` and `skip-integration-schema-generate`.

Each calling repository needs these repository variables for registry access:

- `AWS_ARTIFACTS_ECR_ROLE`: the shared Artifacts publisher role ARN.
- `AWS_ARTIFACTS_ECR_REGION`: `eu-central-1`.

Each calling repository's GitHub environment needs:

- `AWS_PUBLIC_SCHEMAS_BUCKET`, `AWS_PUBLIC_SCHEMAS_ROLE`, `AWS_PUBLIC_SCHEMAS_REGION`.
- `AWS_INTEGRATIONS_DEPLOY_ROLE`: that environment's EKS deployment role ARN.
- `AWS_EKS_CLUSTER` and `AWS_EKS_REGION`.

Callers need `contents: read` and `id-token: write`. Dockerfiles must use available
ECR base images; manifests and registration jobs must match the AWS runtime.
The legacy GCP and `json-schema-bucket` secrets remain accepted, but are optional
and unused, allowing callers to migrate without an immediate interface break.
Registry login uses the Artifacts role before deployment switches to the EKS role.

Do not merge the shared workflow into `master` until its callers are ready. They
currently reference `@master`, so merging affects them without caller commits.
Use migration-branch references for staged tests, with `skip-deploy: true` until
the rendered environment-specific deployment has been reviewed and approved.
No PROD or DNS cutover is implied by preparing these workflows.
