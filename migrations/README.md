# Workflow migrations
To avoid manual labor, when changing the workflow files en masse (e.g. when changing their inputs),
you can use [`multi-gitter`](https://github.com/lindell/multi-gitter) - a tool that allows you to run
a script over all of organization's repositories, and [`ytt`](https://carvel.dev/ytt/) - a YAML "shaping" tool,
for actually modifying the workflow files.

For example, to run our first migration, we ran:

```sh
multi-gitter run ./migrations/01-gcp-auth.sh \
  -i --log-level=debug \
  -O goes-funky \
  --pr-title "SRE-95: use keyless GitHub Actions authentication" \
  --pr-body "Please don't merge until Monday morning. Alternatively, merge when your deployments start failing GCP authentication." \
  -B SRE-95-oidc-auth --skip-repo goes-funky/modeling-api,goes-funky/y42-frontend,goes-funky/dbt-functions,goes-funky/fivetran-functions
```

Currently there's no mechanism to run these "migrations" automatically.