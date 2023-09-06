#!/usr/bin/env bash

set -e
dir="$(dirname "$0")"

process_workflow () {
  workflow="$1"

  # Find out if the workflow uses any of the workflows we're modifying:
  if grep "goes-funky/workflows/.github/workflows/deploy-integration.yaml@master" "$workflow" || grep "goes-funky/workflows/.github/workflows/flux-build.yaml@master" "$workflow" || grep "goes-funky/workflows/.github/workflows/build-python.yaml@master" "$workflow"; then
    echo "$workflow: references found, patching"

    # Because strict (or over-simplified, dumb, take your pick) YAML implementations
    # consider "on" to mean "true" (hey, we're a configuration language, it makes "sense"),
    # and YTT which further processes our workflow files is one such implementation, replace
    # the `on:` keys near the top of our workflows with their quoted versions.
    # Ugly, but effective.
    sed -i 's/^on:$/"on":/g' "$workflow"

    new=$(ytt -f "$workflow" -f "$dir/01-gcp-auth-deploy-integration.ytt.yml" -f "$dir/01-gcp-auth-flux-build.ytt.yml" -f "$dir/01-gcp-auth-build-python.ytt.yml")
    if [[ $? -eq 0 ]]; then
      cat <<< "$new" > "$workflow"
    else
      echo "$workflow: ytt exit code $?, output:"
      cat <<< "$new"
      echo
    fi
  fi
}

for file in .github/workflows/*; do
  process_workflow "$file"
done
