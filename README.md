# CI/CD Reusable Workflows

## Deployment workflow

To automate deployment process DevOps team has created [reusable workflow](https://github.com/goes-funky/workflows/blob/master/.github/workflows/deploy.yaml) that can be referenced in your repo GitHub Actions configuration.

### Flow

- push to default branch (`master` or `main`) triggers deployment to `development`
- creating `v[semver]` tag triggers deployment to `development` first, if it succeeded then deployment to `production` follows.
- hotfixes can be deployed to `production` by checking out branch from tagged release and manually triggering workflow
- arbitrary branches can be deployed to `development`/`demo` by triggering workflow
- `production` releases require approval from `group-backend-deployers`

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
Don't make any direct change in `.github/workflows` folder, it's will be overrided.

Contributing flow:
- Changes should be made within `pkg/*`
- Run `make` to generate actual workflows
- Commit your change for both `pkg/*` and generated workflows in `.github/workflows`
- PR time!
