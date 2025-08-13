#!/bin/bash

# Script to find commits in dasharo-24.02.1 that are missing from dasharo
# Usage: ./check-missing-commits.sh [options]

set -e

# Configuration
OLD_BRANCH="dasharo-24.02.1"
NEW_BRANCH="dasharo"
UPSTREAM_BRANCH="origin/main"  # Adjust this to your upstream branch name

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -o, --old-branch     Old branch name (default: $OLD_BRANCH)"
    echo "  -n, --new-branch     New branch name (default: $NEW_BRANCH)"
    echo "  -u, --upstream       Upstream branch (default: $UPSTREAM_BRANCH)"
    echo "  -v, --verbose        Show detailed commit information"
    echo "  -s, --summary        Show only summary count"
    echo "  -m, --method         Check method: hash|patch|subject (default: hash)"
    echo "  --all-methods        Show results for all checking methods"
    echo ""
    echo "Check methods:"
    echo "  hash     - Compare by commit hash (strict, for merges/fast-forwards)"
    echo "  patch    - Compare by patch content (detects rebased/cherry-picked commits)"
    echo "  subject  - Compare by commit subject line (fuzzy, may have false positives)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Basic hash-based check"
    echo "  $0 -m patch                           # Content-based check (recommended for rebases)"
    echo "  $0 --all-methods                      # Compare all methods"
    echo "  $0 -m subject --verbose               # Subject-based with details"
}

# Parse command line arguments
VERBOSE=false
SUMMARY_ONLY=false
CHECK_METHOD="hash"
ALL_METHODS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -o|--old-branch)
            OLD_BRANCH="$2"
            shift 2
            ;;
        -n|--new-branch)
            NEW_BRANCH="$2"
            shift 2
            ;;
        -u|--upstream)
            UPSTREAM_BRANCH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--summary)
            SUMMARY_ONLY=true
            shift
            ;;
        -m|--method)
            CHECK_METHOD="$2"
            shift 2
            ;;
        --all-methods)
            ALL_METHODS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_color $RED "Error: Not in a git repository"
    exit 1
fi

# Verify branches exist
for branch in "$OLD_BRANCH" "$NEW_BRANCH"; do
    if ! git show-ref --verify --quiet refs/heads/$branch 2>/dev/null && \
       ! git show-ref --verify --quiet refs/remotes/$branch 2>/dev/null; then
        print_color $RED "Error: Branch '$branch' does not exist"
        exit 1
    fi
done

# Function to show detailed commit information
show_detailed_commits() {
    local commits="$1"
    echo "$commits" | while read -r commit; do
        if [ -n "$commit" ]; then
            commit_hash=$(echo "$commit" | cut -d' ' -f1)
            print_color $YELLOW "Commit: $commit_hash"
            git show --no-patch --format="Author: %an <%ae>%nDate: %ad%nSubject: %s%n" --date=short "$commit_hash" 2>/dev/null || echo "Could not show commit details"

            # Show files changed
            files_changed=$(git diff-tree --no-commit-id --name-only -r "$commit_hash" 2>/dev/null || true)
            if [ -n "$files_changed" ]; then
                echo "Files changed:"
                echo "$files_changed" | sed 's/^/  /'
            fi
            echo ""
        fi
    done
}

# Function to check by commit hash
check_by_hash() {
    local method_name="$1"

    if [ -n "$method_name" ]; then
        print_color $BLUE "=== Method: Hash-based comparison ==="
        echo "Compares actual commit hashes (strict)"
        echo ""
    fi

    # Use the EXACT same command as the original script
    missing_commits=$(git log --oneline --no-merges "$NEW_BRANCH..$OLD_BRANCH" --not "$UPSTREAM_BRANCH" 2>/dev/null || true)

    if [ -z "$missing_commits" ]; then
        print_color $GREEN "✓ No missing commits by hash"
        return 0
    fi

    local count=$(echo "$missing_commits" | wc -l)

    if [ "$SUMMARY_ONLY" = true ]; then
        print_color $RED "Missing commits: $count"
        return $count
    fi

    print_color $RED "⚠ Found $count commits by hash:"
    echo ""

    if [ "$VERBOSE" = true ]; then
        show_detailed_commits "$missing_commits"
    else
        echo "$missing_commits"
    fi

    return $count
}

# Function to check by patch content (using git cherry)
check_by_patch() {
    local method_name="$1"

    if [ -n "$method_name" ]; then
        print_color $BLUE "=== Method: Patch content comparison ==="
        echo "Compares actual patch content (detects rebased/cherry-picked commits)"
        echo ""
    fi

    # git cherry shows commits in OLD_BRANCH not applied to NEW_BRANCH
    # + means not applied, - means applied (but with different hash)
    cherry_output=$(git cherry "$NEW_BRANCH" "$OLD_BRANCH" 2>/dev/null || true)

    # Filter to only show commits not in upstream and only the + ones (not applied)
    missing_commits=""
    if [ -n "$cherry_output" ]; then
        while read -r line; do
            if [[ $line == +* ]]; then
                commit_hash=$(echo "$line" | cut -d' ' -f2)
                # Check if this commit is not in upstream
                if ! git merge-base --is-ancestor "$commit_hash" "$UPSTREAM_BRANCH" 2>/dev/null; then
                    if [ -n "$missing_commits" ]; then
                        missing_commits="$missing_commits"$'\n'
                    fi
                    missing_commits="$missing_commits$(git log --oneline -1 "$commit_hash")"
                fi
            fi
        done <<< "$cherry_output"
    fi

    if [ -z "$missing_commits" ]; then
        print_color $GREEN "✓ No missing commits by patch content"
        return 0
    fi

    local count=$(echo "$missing_commits" | wc -l)

    if [ "$SUMMARY_ONLY" = true ]; then
        print_color $RED "Missing commits: $count"
        return $count
    fi

    print_color $RED "⚠ Found $count commits by patch content:"
    echo ""

    if [ "$VERBOSE" = true ]; then
        show_detailed_commits "$missing_commits"
    else
        echo "$missing_commits"
    fi

    return $count
}

# Function to check by commit subject
check_by_subject() {
    local method_name="$1"

    if [ -n "$method_name" ]; then
        print_color $BLUE "=== Method: Subject line comparison ==="
        echo "Compares commit subject lines (fuzzy matching)"
        echo ""
    fi

    # Get subjects from old branch (excluding upstream)
    old_subjects=$(git log --format="%H %s" --no-merges "$NEW_BRANCH..$OLD_BRANCH" --not "$UPSTREAM_BRANCH" 2>/dev/null || true)

    if [ -z "$old_subjects" ]; then
        print_color $GREEN "✓ No commits to check by subject"
        return 0
    fi

    # Get subjects from new branch (excluding upstream)
    new_subjects=$(git log --format="%s" --no-merges "$NEW_BRANCH" --not "$UPSTREAM_BRANCH" 2>/dev/null || true)

    missing_commits=""
    missing_count=0

    # Process each commit from old branch
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            commit_hash=$(echo "$line" | cut -d' ' -f1)
            # Get everything after the first space as the subject
            subject=$(echo "$line" | sed 's/^[^ ]* //')

            # Check if this exact subject exists in new branch
            if ! echo "$new_subjects" | grep -Fxq "$subject"; then
                if [ -n "$missing_commits" ]; then
                    missing_commits="$missing_commits"$'\n'
                fi
                missing_commits="$missing_commits$(git log --oneline -1 "$commit_hash")"
                missing_count=$((missing_count + 1))
            fi
        fi
    done <<< "$old_subjects"

    if [ $missing_count -eq 0 ]; then
        print_color $GREEN "✓ No missing commits by subject line"
        return 0
    fi

    if [ "$SUMMARY_ONLY" = true ]; then
        print_color $RED "Missing commits: $missing_count"
        return $missing_count
    fi

    print_color $RED "⚠ Found $missing_count commits by subject line:"
    echo ""

    if [ "$VERBOSE" = true ]; then
        show_detailed_commits "$missing_commits"
    else
        echo "$missing_commits"
    fi

    return $missing_count
}

# Main execution
print_color $BLUE "=== Checking for missing commits ==="
print_color $YELLOW "Old branch: $OLD_BRANCH"
print_color $YELLOW "New branch: $NEW_BRANCH"
print_color $YELLOW "Upstream: $UPSTREAM_BRANCH"
echo ""

if [ "$ALL_METHODS" = true ]; then
    # Run all three methods
    echo "Running all comparison methods..."
    echo ""

    check_by_hash "show_header"
    echo ""

    check_by_patch "show_header"
    echo ""

    check_by_subject "show_header"
    echo ""

    print_color $BLUE "=== Recommendations ==="
    echo "• Hash method: Most strict, only finds commits with exact same hash"
    echo "• Patch method: Best for rebases, finds commits by content regardless of hash"
    echo "• Subject method: Most permissive, may have false positives"
    echo ""
    echo "For rebased branches, 'patch' method is usually most accurate."

elif [ "$CHECK_METHOD" = "hash" ]; then
    check_by_hash ""
elif [ "$CHECK_METHOD" = "patch" ]; then
    check_by_patch ""
elif [ "$CHECK_METHOD" = "subject" ]; then
    check_by_subject ""
else
    print_color $RED "Error: Unknown method '$CHECK_METHOD'. Use: hash, patch, or subject"
    exit 1
fi

if [ "$ALL_METHODS" != true ] && [ "$SUMMARY_ONLY" != true ]; then
    echo ""
    print_color $BLUE "=== Helpful commands ==="
    echo "Git cherry (patch-based): git cherry $NEW_BRANCH $OLD_BRANCH"
    echo "Hash-based diff: git log --oneline $NEW_BRANCH..$OLD_BRANCH --not $UPSTREAM_BRANCH"
    echo "Detailed patches: git log -p $NEW_BRANCH..$OLD_BRANCH --not $UPSTREAM_BRANCH"
    echo ""
    echo "To cherry-pick a commit: git cherry-pick <commit-hash>"
    echo "To see what method works best: $0 --all-methods"
fi
