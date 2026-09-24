package common

#notify_infra_workflow: #workflow & {
    on: workflow_call: {
        inputs: {
            image: {
                type: "string"
                description: "Published service image, including tag and digest"
                required: true
            }
            registry: {
                type: "string"
                description: "Registry authenticated by the image build"
                required: true
            }
        }
        secrets: {}
    }
    jobs: notify: #job_infra_dispatch
}

// No checkout or application code in this job. The OIDC role trusts this shared
// workflow at master and approved callers on main, not arbitrary build jobs.
#job_infra_dispatch: #job & {
    name: "Request infra image update"
    if: "github.event_name == 'push' && github.ref == 'refs/heads/main' && vars.AWS_INFRA_DISPATCH_ROLE != ''"
    steps: [
        {
            name: "Authenticate for infra dispatch"
            uses: "aws-actions/configure-aws-credentials@v4"
            with: {
                "aws-region": "${{ vars.AWS_ARTIFACTS_ECR_REGION }}"
                "role-to-assume": "${{ vars.AWS_INFRA_DISPATCH_ROLE }}"
                "role-session-name": "github-infra-dispatch"
                "role-duration-seconds": 900
            }
        },
        {
            name: "Dispatch exact published image to infra"
            id: "dispatch"
            env: {
                PUBLISHED_IMAGE: "${{ inputs.image }}"
                EXPECTED_REGISTRY: "${{ inputs.registry }}"
            }
            run: """
                set -euo pipefail
                service="${GITHUB_REPOSITORY#*/}"
                digest="${PUBLISHED_IMAGE##*@}"
                tagged_image="${PUBLISHED_IMAGE%@*}"
                tag="${tagged_image##*:}"
                repository="${tagged_image%:*}"
                if [[ "$repository" != "$EXPECTED_REGISTRY/$service" || ! "$tag" =~ ^[a-fA-F0-9]{7,40}-[0-9]+$ || ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
                  echo 'Expected a published release image with a digest' >&2
                  exit 1
                fi
                short_sha="${tag%%-*}"
                if [[ "$GITHUB_SHA" != "$short_sha"* ]]; then
                  echo 'Published tag does not match the source commit' >&2
                  exit 1
                fi
                jq -n --arg service "$service" --arg tag "$tag" --arg digest "$digest" \\
                  --arg source_run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \\
                  '{ref: "main", inputs: {service: $service, environment: "both", tag: $tag, digest: $digest, automatic: "true", "source-run": $source_run, "dry-run": "false"}}' \\
                  > "$RUNNER_TEMP/infra-dispatch.json"
                # Retrieve only in this isolated job; never write the token to an
                # output, artifact, file, or Terraform state. GitHub masks logs.
                token="$(aws secretsmanager get-secret-value --secret-id github/infra-workflow-dispatch --query SecretString --output text)"
                if [[ -z "$token" || "$token" == *$'\\n'* || "$token" == *$'\\r'* || "$token" == 'None' ]]; then
                  echo 'Secrets Manager must contain a nonempty plaintext token' >&2
                  exit 1
                fi
                echo "::add-mask::$token"
                export GH_TOKEN="$token"
                unset token
                trap 'unset GH_TOKEN' EXIT
                for attempt in 1 2 3; do
                  if gh api --method POST repos/goes-funky/infra/actions/workflows/aws-image-update-branches.yaml/dispatches --input "$RUNNER_TEMP/infra-dispatch.json"; then
                    echo 'Requested DEV and PROD image-update branches in infra'
                    exit 0
                  fi
                  sleep "$attempt"
                done
                echo 'Infra dispatch failed; rerun this job to retry without rebuilding' >&2
                exit 1
                """
        }
    ]
}
