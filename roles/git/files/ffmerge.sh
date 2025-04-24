#!/usr/bin/env bash

# Function to display help
function display_help {
    echo "Usage: $0 <feature-branch> <base-branch>"
    echo
    echo "Arguments:"
    echo "  <feature-branch>  The name of the feature branch to be rebased and merged."
    echo "  <base-branch>     The name of the base branch to rebase onto and merge into."
    echo
    echo "Example:"
    echo "  $0 fix-tpm2-tests-fail-on-ftpm develop"
    exit 1
}

# Function to check for errors
function check_error {
    if [ $? -ne 0 ]; then
        echo "$1"
        exit 1
    fi
}

# Function to check out a branch
function checkout_branch {
    git checkout $1
    check_error "Failed to checkout branch $1"
}

# Function to update a branch from origin
function update_branch {
    git pull origin $1
    check_error "Failed to update branch $1"
}

# Function to push a branch to origin
function push_branch {
    git push $1 origin $2
    check_error "Failed to push branch $2"
}

# Function to delete a branch locally and remotely
function delete_branch {
    git branch -d $1
    check_error "Failed to delete local branch $1"
    git push origin --delete $1
    check_error "Failed to delete remote branch $1"
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Error: Incorrect number of arguments."
    display_help
fi

# Assign arguments to variables
feature_branch=$1
base_branch=$2

# Update
git fetch
check_error "Failed to fetch updates"

# Checkout and update the base branch
checkout_branch $base_branch
update_branch $base_branch

# Checkout and update the feature branch
checkout_branch $feature_branch
update_branch $feature_branch

# Rebase the feature branch onto the base branch
git rebase $base_branch
check_error "Rebase failed"

# Force push the updated feature branch
push_branch --force-with-lease $feature_branch

# Checkout the base branch
checkout_branch $base_branch

# Merge the feature branch into the base branch with fast-forward only
git merge --ff-only $feature_branch
check_error "Merge failed"

# Push the base branch to origin
push_branch "" $base_branch

# Delete the feature branch locally and remotely
delete_branch $feature_branch

echo "Process completed successfully"
