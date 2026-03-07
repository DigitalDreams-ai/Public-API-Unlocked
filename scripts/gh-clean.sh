#!/bin/bash

# Clean up failed and cancelled GitHub Actions workflow runs
REPO="DigitalDreams-ai/PublicApiUnlocked"

echo "Fetching failed workflow runs..."
failed_ids=$(gh run list --repo "$REPO" --status failure --json databaseId -q '.[].databaseId')

echo "Fetching cancelled workflow runs..."
cancelled_ids=$(gh run list --repo "$REPO" --status cancelled --json databaseId -q '.[].databaseId')

all_ids="$failed_ids $cancelled_ids"

if [ -z "$(echo $all_ids | tr -d '[:space:]')" ]; then
    echo "No failed or cancelled runs to delete."
    exit 0
fi

count=0
for id in $all_ids; do
    gh run delete --repo "$REPO" "$id" && echo "Deleted run $id"
    ((count++))
done

echo "Done. Deleted $count workflow run(s)."
