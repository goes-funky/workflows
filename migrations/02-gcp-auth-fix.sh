#!/usr/bin/env bash

set -e
dir="$(dirname "$0")"

process_workflow () {
  workflow="$1"

  # Find out if the workflow uses any of the workflows we're modifying:
  if grep "goes-funky/workflows/.github/workflows/build-python.yaml@master" "$workflow"; then
    echo "$workflow: references found, patching"

    new=$(ytt -f "$workflow" -f "$dir/02-gcp-auth-fix-build-python-perms.ytt.yml")
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
