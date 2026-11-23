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
Registry login uses the Artifacts role before deployment switches to the EKS role.
Deployment waits for the registration Job to complete successfully.

The only accepted secret is `ssh-private-key`. Remove `json-schema-bucket`,
`gcp-service-account`, `gcp-workload-identity-provider`, `gcp-gcr-service-account`,
`gcp-gcr-workload-identity-provider`, `gke-cluster` and `gke-location` from callers;
GitHub rejects explicitly passed secrets that the reusable workflow does not declare.

Callers referencing `@master` adopt changes on their next run. Deferred callers
must be configured for AWS when they are next used. Merging the shared workflow
does not trigger caller builds or deployments by itself.
Use `skip-deploy: true` for build/schema-only tests. PROD deployment requires its
own AWS identity and environment variables; schema DNS cutover is separate.


## AWS image-update notification

`flux-build.yaml` calls `notify-infra.yaml` after a successful main push build when
`AWS_INFRA_DISPATCH_ROLE` is configured for the caller. The notification workflow
uses OIDC to retrieve the infra-dispatch token from AWS Secrets Manager and sends
the exact published tag/digest to infra. It has its own runner and never executes
application code. No additional caller secret mappings or `secrets: inherit` are
needed. Feature-branch builds remain build-only.

Provision the role and token and merge infra's receiver before setting the role
variable. See [infra's image-update runbook](https://github.com/goes-funky/infra/blob/main/clouds/aws/docs/image_update_automation.md)
for permissions, activation and recovery. The dedicated role trusts only this
repository's `notify-infra.yaml` on master and approved callers on main.

Run `python3 -m unittest discover -s scripts/tests -v` after `make all` to test the
generated notification step with fake AWS/GitHub commands; no real token is used.

### GitOps tap releases

`deploy-integration.yaml` accepts an optional `tap-template-name`: the connector's
template directory under `goes-funky/integrations/integrations/taps` (for example
`google-adwords`). An opted-in connector releases the way services do:

- A push to the development branch builds the image and calls `notify-infra.yaml`
  with `tap-template`. Infra's `aws-image-update-branches.yaml` (target `taps`) opens a
  DEV and a PROD PR in integrations pinning that exact image, with the schemas
  generated from it. DEV merges automatically after validation; PROD needs review.
- The build's own schema upload jobs are skipped; integrations publishes each
  environment's schemas after its release PR merges.
- The deploy jobs no longer render a job template. They still publish the OAuth
  settings (`deploy_notice --auth-only`) and tap-config, on the existing triggers.

Requirements: the OAuth-only `build-scripts/src/tap-container/kustomize_gitops` base, a
`datos_integrations` revision with `deploy_notice --auth-only`, existing
`integrations/taps/<name>/{dev,prod}/job_template.yaml` files, the
`AWS_INFRA_DISPATCH_ROLE` Actions variable (the build fails without it rather than
release nothing), the repository in infra's `scripts/aws-image-updates.json` `taps`, and a
caller referencing this workflow at `@master`, the only ref the dispatch role trusts.
The release and cleanup procedure lives in
`goes-funky/integrations/docs/tap-gitops-releases.md`.

Callers without `tap-template-name` keep the legacy template-notice path while they
migrate. Do not remove legacy library or broker event compatibility globally until all
callers have migrated.
