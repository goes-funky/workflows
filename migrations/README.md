# Workflow migrations
To avoid manual labor, when changing the workflow files en masse (e.g. when changing their inputs),
you can use [`multi-gitter`](https://github.com/lindell/multi-gitter) - a tool that allows you to run
a script over all of organization's repositories, and [`ytt`](https://carvel.dev/ytt/) - a YAML "shaping" tool,
for actually modifying the workflow files.

For example, to run our first migration, we ran:

```sh
multi-gitter run ./migrations/01-gcp-auth.sh --skip-repo goes-funky/modeling-api goes-funky/y42-frontend --dry-run --log-level=debug -O goes-funky -m "SRE-95: update workflows to auth to GCP using OIDC" -B SRE-95-oidc-auth
```