#!/bin/bash

# Dispatch GitHub Actions workflows
REPO="DigitalDreams-ai/Public-API-Unlocked"

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

show_help() {
    echo "Usage: npm run gh:dispatch -- <workflow>"
    echo ""
    echo "Available workflows:"
    echo "  beta-create    - Beta - Create (Unlocked) [main only]"
    echo "  beta-promote   - Beta - Promote (Unlocked) [main only]"
    echo "  feature-test   - Feature - Test (Unlocked)"
    echo "  package-install - Package - Install (Unlocked)"
    echo ""
    echo "Options:"
    echo "  --branch, -b   - Specify branch (default: current branch '$BRANCH')"
    echo "  --list, -l     - List all workflows"
    echo ""
    echo "Examples:"
    echo "  npm run gh:dispatch -- beta-create"
    echo "  npm run gh:dispatch -- beta-create -b main"
}

list_workflows() {
    echo "Available workflows in $REPO:"
    gh workflow list --repo "$REPO"
}

# Parse arguments
WORKFLOW=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_workflows
            exit 0
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        *)
            WORKFLOW="$1"
            shift
            ;;
    esac
done

if [ -z "$WORKFLOW" ]; then
    show_help
    exit 1
fi

# Map friendly names to workflow files
case $WORKFLOW in
    beta-create)
        WORKFLOW_FILE="beta_create.yml"
        BRANCH="main"  # Beta workflows only run on main
        ;;
    beta-promote)
        WORKFLOW_FILE="beta_promote.yml"
        BRANCH="main"  # Beta workflows only run on main
        ;;
    feature-test)
        WORKFLOW_FILE="feature_test.yml"
        ;;
    package-install)
        WORKFLOW_FILE="package_install.yml"
        ;;
    *)
        echo "Unknown workflow: $WORKFLOW"
        echo ""
        show_help
        exit 1
        ;;
esac

echo "Dispatching '$WORKFLOW_FILE' on branch '$BRANCH'..."
gh workflow run "$WORKFLOW_FILE" --repo "$REPO" --ref "$BRANCH"

if [ $? -eq 0 ]; then
    echo "Workflow dispatched successfully!"
    echo ""
    echo "View runs: https://github.com/$REPO/actions"
else
    echo "Failed to dispatch workflow."
    exit 1
fi

