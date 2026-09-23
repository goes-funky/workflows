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


## Integration schema publishing on AWS

`deploy-integration.yaml` publishes generated `integrations/` content to S3 with
`public, max-age=300`, preserving the directory prefix. DEV, PROD and explicit
environment jobs retain their existing triggers, generation command and dependencies.

Each **calling repository's GitHub environment** needs these variables:

- `AWS_PUBLIC_SCHEMAS_BUCKET`: its environment's public schema bucket.
- `AWS_PUBLIC_SCHEMAS_ROLE`: the environment's GitHub schema publisher role ARN.
- `AWS_PUBLIC_SCHEMAS_REGION`: `eu-central-1`.

Callers need `contents: read` and `id-token: write`. The old `json-schema-bucket`
secret remains accepted for compatibility but is no longer used. No bucket-wide
delete is performed. Build and Kubernetes deployment jobs still use GCP; this change
migrates only schema uploads. A schema job still depends on the existing build job,
so it is not an independent AWS-only pipeline.

Do not merge this switch into `master` until destinations and environment variables
are ready for its callers, including PROD and any explicit environment they use.
Current callers reference `@master`, so merging affects them without caller commits.
Do not dispatch a full legacy workflow merely to test uploads: it can also build
images and deploy workloads.
