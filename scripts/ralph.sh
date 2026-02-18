#!/usr/bin/env bash
# Ralph.sh - Autonomous AI coding agent loop using OpenCode
set -euo pipefail

# Configuration
RALPH_WORKSPACE="$HOME/source/ralph"
RALPH_TEMPLATES="$RALPH_WORKSPACE/.templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Sanitize directory name
sanitize_dir_name() {
  local name="$1"
  # Lowercase
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  # Spaces to hyphens
  name=$(echo "$name" | tr ' ' '-')
  # Remove special chars (keep alphanumeric and hyphens)
  name=$(echo "$name" | sed 's/[^a-z0-9-]//g')
  # Collapse multiple hyphens
  name=$(echo "$name" | sed 's/-\{2,\}/-/g')
  # Remove leading/trailing hyphens
  name=$(echo "$name" | sed 's/^-\|-$//g')
  echo "$name"
}

# Sanitize tmux session name
sanitize_tmux_name() {
  local name="$1"
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  name=$(echo "$name" | tr ' ' '_')
  name=$(echo "$name" | sed 's/[^a-z0-9_]//g')
  name=$(echo "$name" | sed 's/_\{2,\}/_/g')
  echo "$name"
}

# Escape special characters for sed
escape_sed() {
  local str="$1"
  str=$(echo "$str" | sed 's/[&/\]/\\&/g')
  echo "$str"
}

# Get unique tmux session name
get_tmux_session_name() {
  local description="$1"
  local base_name="ralph_$(sanitize_tmux_name "$description")"
  local counter=1
  local session_name="$base_name"
  
  while tmux has-session -t "$session_name" 2>/dev/null; do
    counter=$((counter + 1))
    session_name="${base_name}_${counter}"
  done
  
  echo "$session_name"
}

# Extract metadata from PRD.md
extract_metadata() {
  local prd_path="$1"
  local key="$2"
  local value
  value=$(grep "^${key}:" "$prd_path" 2>/dev/null | cut -d' ' -f2-)
  echo "$value"
}

# Update metadata in PRD.md
update_metadata() {
  local prd_path="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}:" "$prd_path"; then
    sed -i "s/^${key}:.*/${key}: ${value}/" "$prd_path"
  else
    sed -i "/^#project_path:/a\\
${key}: ${value}" "$prd_path"
  fi
}

# Create initial PRD.md with metadata
create_prd_metadata() {
  local prd_path="$1"
  local project_path="$2"
  local description="$3"
  local branch_name="$4"
  
  cat > "$prd_path" << EOF
# Project: [Project Name]

#project_path: ${project_path}
#description: ${description}
#worktree_path: 
#branch_name: ${branch_name}
#iteration_count: 0
#status: created
#tmux_session: 

## Project Overview
[Description of what to build]

## User Stories & Acceptance Criteria
[Generate via OpenCode]

## Technical Constraints
[Any technical constraints]

## Implementation Notes
[Any implementation guidance]
EOF
}

# Substitute template variables
substitute_prompt_vars() {
  local template="$1"
  local workspace="$2"
  local prd_path="$3"
  local iteration
  local quality_gates
  
  iteration=$(extract_metadata "$prd_path" "#iteration_count")
  quality_gates=""
  
  # Extract quality gates if they exist
  if grep -q "## Quality Gates" "$prd_path"; then
    quality_gates=$(sed -n '/## Quality Gates/,/^## /p' "$prd_path" | grep -E "^\s*-\s*\`" || echo "No Quality Gates specified in PRD")
  else
    quality_gates="No Quality Gates specified in PRD"
  fi

  sed -e "s/ITERATION_COUNT/${iteration}/g" \
      -e "s/<workspace>/${workspace}/g" \
      -e "s|QUALITY_GATE_COMMANDS|${quality_gates}|g" \
      "$template"
}

# Check if notify-send is available
check_notify_send() {
  if ! command -v notify-send &> /dev/null; then
    print_warning "notify-send not found. Install libnotify-bin for notifications."
    return 1
  fi
  return 0
}

# Main loop execution
run_ralph_loop() {
  local prd_path="$1"
  local project_path
  local description
  local worktree_path
  local branch_name
  local iteration
  local status
  
  # Extract metadata
  project_path=$(extract_metadata "$prd_path" "#project_path")
  description=$(extract_metadata "$prd_path" "#description")
  worktree_path=$(extract_metadata "$prd_path" "#worktree_path")
  branch_name=$(extract_metadata "$prd_path" "#branch_name")
  iteration=$(extract_metadata "$prd_path" "#iteration_count")
  status=$(extract_metadata "$prd_path" "#status")
  
  # Validate project path exists
  if [ ! -d "$project_path/.git" ]; then
    print_error "Repository path is not a git repository: $project_path"
    print_info "You can edit PRD to fix this: ralph.sh --edit $prd_path"
    exit 1
  fi
  
  # Check for active session
  if [ "$status" = "active" ]; then
    print_warning "This PRD already has an active Ralph session"
    print_info "Resume with: ralph.sh --prd $prd_path"
    print_info "Or cleanup first: ralph.sh --cleanup $prd_path"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Create worktree if needed
  local workspace_dir
  if [ -z "$worktree_path" ] || [ ! -d "$worktree_path" ]; then
    print_info "Creating git worktree..."
    workspace_dir=$(dirname "$prd_path")
    worktree_path="${workspace_dir}/worktree"
    
    # Create worktree
    cd "$project_path"
    git worktree add -b "$branch_name" "$worktree_path"
    
    # Update PRD with worktree path
    update_metadata "$prd_path" "#worktree_path" "$worktree_path"
    print_success "Worktree created at: $worktree_path"
  else
    workspace_dir=$(dirname "$prd_path")
  fi
  
  # Copy loop template if needed
  local loop_template
  loop_template="$workspace_dir/PROMPT_loop.md"
  if [ ! -f "$loop_template" ]; then
    cp "$RALPH_TEMPLATES/PROMPT_loop_template.md" "$loop_template"
  fi
  
  # Set status to active
  update_metadata "$prd_path" "#status" "active"
  
  print_success "Starting Ralph loop..."
  print_info "Project: $project_path"
  print_info "Worktree: $worktree_path"
  print_info "Branch: $branch_name"
  print_info "Starting iteration: $iteration"
  echo
  
  # Graceful shutdown handler
  trap shutdown_handler SIGINT SIGTERM

  shutdown_handler() {
    echo
    print_warning "Interrupted. Saving state..."
    update_metadata "$prd_path" "#status" "paused"
    local session
    session=$(extract_metadata "$prd_path" "#tmux_session")
    print_info "Session paused at iteration $iteration"
    print_info "Tmux session: $tmux_session (persisting for inspection)"
    print_info "Resume with: ralph.sh --prd $prd_path"
    exit 0
  }

  # Generate tmux session name
  local tmux_session
  tmux_session=$(get_tmux_session_name "$description")
  update_metadata "$prd_path" "#tmux_session" "$tmux_session"

  print_success "Starting Ralph loop..."
  print_info "Project: $project_path"
  print_info "Worktree: $worktree_path"
  print_info "Branch: $branch_name"
  print_info "Starting iteration: $iteration"
  print_info "Tmux session: $tmux_session"
  print_info "Attach with: tmux attach -t $tmux_session"
  echo

  # Create detached tmux session
  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux new-session -d -s "$tmux_session"
    print_success "Tmux session created (detached)"
  fi
  
  # Main loop
  while true; do
    # Get current iteration
    iteration=$(extract_metadata "$prd_path" "#iteration_count")
    
    # Notify on milestones
    if [ "$((iteration % 50))" -eq 0 ] && [ "$iteration" -gt 0 ]; then
      if check_notify_send; then
        notify-send "Ralph" "Iteration count reached $iteration"
      fi
    fi
    
    print_info "Starting iteration $iteration"
    print_info "Worktree: $worktree_path"
    
    # Substitute prompt variables
    local temp_prompt
    temp_prompt=$(mktemp)
    substitute_prompt_vars "$loop_template" "$(basename "$workspace_dir")" "$prd_path" > "$temp_prompt"

    # Run opencode in tmux session
    tmux send-keys -t "$tmux_session" "cd \"$worktree_path\"" C-m
    tmux send-keys -t "$tmux_session" "cat \"$temp_prompt\" | OPENCODE_PERMISSION=allow opencode run \"Execute Ralph iteration $iteration\"" C-m
    
    rm "$temp_prompt"
    
    # Check for completion
    if grep -q "<instruct>COMPLETED</instruct>" "$prd_path"; then
      update_metadata "$prd_path" "#status" "completed"
      print_success "All tasks completed!"
      break
    fi
    
    # Increment iteration
    iteration=$((iteration + 1))
    update_metadata "$prd_path" "#iteration_count" "$iteration"
    
    echo
    print_info "Iteration $iteration completed. Continuing..."
    echo
  done
  
  # Final summary
  echo
  print_success "Ralph loop completed!"
  echo
  echo "Summary:"
  echo "  Iterations: $iteration"
  echo "  Worktree: $worktree_path"
  echo "  Branch: $branch_name"
  echo
  echo "To merge changes into your project:"
  echo "  cd $project_path"
  echo "  git merge $branch_name"
  echo
  echo "To clean up when done:"
  echo "  ralph.sh --cleanup $prd_path"
}

# Generate PRD
generate_prd() {
  local project_path="$1"
  local project_name
  local branch_name
  local workspace_name
  local workspace_dir
  local prd_path
  local description
  local tmpfile
  
  # Validate required parameters
  if [ -z "$project_path" ]; then
    print_error "--project <path> is required to generate a PRD"
    echo
    show_usage
    exit 1
  fi
  
  if [ ! -d "$project_path/.git" ]; then
    print_error "Not a git repository: $project_path"
    exit 1
  fi
  
  # Ensure workspace exists
  mkdir -p "$RALPH_WORKSPACE"
  mkdir -p "$RALPH_TEMPLATES"
  mkdir -p "/tmp/ralph"
  
  # Get project name from project path
  project_name=$(basename "$project_path")
  
  # Create temp file for description
  tmpfile=$(mktemp /tmp/ralph/prd_description_XXXXXX.md)
  cp "$RALPH_TEMPLATES/PRD_DESCRIPTION_template.md" "$tmpfile"
  
  # Open editor for description input
  print_info "Opening editor to enter PRD description..."
  local editor="${EDITOR:-nvim}"
  if [[ "$editor" == "nvim" ]] || [[ "$editor" == "vim" ]]; then
    $editor "+normal! 9G" "+startinsert" "$tmpfile"
  else
    $editor "$tmpfile"
  fi
  
  # Read description (filter out comments and empty lines)
  description=$(grep -v '^#' "$tmpfile" | grep -v '^[[:space:]]*$' | head -n1 | xargs)
  rm -f "$tmpfile"
  
  if [ -z "$description" ]; then
    print_error "Description is required"
    exit 1
  fi
  
  print_info "Using description: $description"
  
  # Get branch name
  branch_name=""
  read -r -p "Branch name [default: ralph-$(sanitize_dir_name "$description")]: " branch_name
  if [ -z "$branch_name" ]; then
    branch_name="ralph-$(sanitize_dir_name "$description")"
  fi
  
  # Create workspace directory
  workspace_name="${project_name}-$(sanitize_dir_name "$description")"
  workspace_dir="$RALPH_WORKSPACE/${workspace_name}"
  
  if [ -d "$workspace_dir" ]; then
    print_error "Workspace already exists: $workspace_dir"
    print_info "Edit existing PRD: ralph.sh --edit $workspace_dir/PRD.md"
    print_info "Or cleanup first: ralph.sh --cleanup $workspace_dir/PRD.md"
    exit 1
  fi
  
  mkdir -p "$workspace_dir"  
  # Create initial PRD
  prd_path="$workspace_dir/PRD.md"
  create_prd_metadata "$prd_path" "$project_path" "$description" "$branch_name"
  
  print_success "Created workspace: $workspace_dir"
  print_info "Launching OpenCode to generate PRD..."
  
  # Copy prd template to workspace
  cp "$RALPH_TEMPLATES/PROMPT_prd_template.md" "$workspace_dir/PROMPT_prd_template.md"
  
  # Substitute description in template (escape special characters)
  local escaped_description
  escaped_description=$(escape_sed "$description")
  sed -i "s/DESCRIPTION_PLACEHOLDER/$escaped_description/g" "$workspace_dir/PROMPT_prd_template.md"
  
  # Read prompt content into variable
  local prompt
  prompt="$(cat "$workspace_dir/PROMPT_prd_template.md")"
  
  # Launch opencode with prompt in plan mode
  cd "$workspace_dir"
  opencode --prompt "$prompt" --agent plan
  
  print_success "PRD created: $prd_path"
  print_info "Start Ralph loop with: ralph.sh --prd $prd_path"
}

# Edit PRD
edit_prd() {
  local prd_path="$1"
  local workspace_dir
  
  if [ ! -f "$prd_path" ]; then
    print_error "PRD not found: $prd_path"
    exit 1
  fi
  
  print_info "Editing PRD: $prd_path"
  
  workspace_dir=$(dirname "$prd_path")
  cd "$workspace_dir"
  opencode
}

# Status check
show_status() {
  local prd_path="$1"
  local project_path
  local description
  local worktree_path
  local branch_name
  local iteration
  local status
  local workspace_dir
  local impl_plan
  local complete_tasks
  local incomplete_tasks
  
  if [ ! -f "$prd_path" ]; then
    print_error "PRD not found: $prd_path"
    exit 1
  fi
  
  # Extract metadata
  project_path=$(extract_metadata "$prd_path" "#project_path")
  description=$(extract_metadata "$prd_path" "#description")
  worktree_path=$(extract_metadata "$prd_path" "#worktree_path")
  branch_name=$(extract_metadata "$prd_path" "#branch_name")
  iteration=$(extract_metadata "$prd_path" "#iteration_count")
  status=$(extract_metadata "$prd_path" "#status")
  workspace_dir=$(dirname "$prd_path")
  
  # Count tasks if implementation plan exists
  impl_plan="$workspace_dir/IMPLEMENTATION_PLAN.md"
  complete_tasks=0
  incomplete_tasks=0
  
  if [ -f "$impl_plan" ]; then
    complete_tasks=$(grep -c "\- \[x\]" "$impl_plan" 2>/dev/null || echo "0")
    incomplete_tasks=$(grep -c "\- \[ \]" "$impl_plan" 2>/dev/null || echo "0")
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Project: $(basename "$workspace_dir")"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "Repository: $project_path"
  echo "Description: $description"
  echo "Workspace: $workspace_dir"
  echo "Worktree: ${worktree_path:-Not created yet}"
  echo "Branch: $branch_name"
  echo "Iteration: $iteration"
  echo "Status: $status"
  echo
  
  if [ -f "$impl_plan" ]; then
    echo "Tasks:"
    echo "  Complete: $complete_tasks"
    echo "  Incomplete: $incomplete_tasks"
    echo
  fi
  
  echo "Last Updated: $(stat -c "%y" "$prd_path" 2>/dev/null || stat -f "%Sm" "$prd_path")"
  echo

  # Show tmux session status
  local tmux_session
  tmux_session=$(extract_metadata "$prd_path" "#tmux_session")
  if [ -n "$tmux_session" ]; then
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
      echo "Tmux Session: $tmux_session (running)"
      echo "  Attach: tmux attach -t $tmux_session"
    else
      echo "Tmux Session: $tmux_session (not running)"
    fi
    echo
  fi

  echo "Commands:"
  echo "  Start loop: ralph.sh --prd $prd_path"
  echo "  Edit PRD: ralph.sh --edit $prd_path"
  echo "  Show status: ralph.sh --status $prd_path"
  echo "  Cleanup: ralph.sh --cleanup $prd_path"
}

# Cleanup
cleanup_workspace() {
  local prd_path="$1"
  local worktree_path
  local project_path
  local workspace_dir
  
  if [ ! -f "$prd_path" ]; then
    print_error "PRD not found: $prd_path"
    exit 1
  fi
  
  # Extract metadata
  worktree_path=$(extract_metadata "$prd_path" "#worktree_path")
  project_path=$(extract_metadata "$prd_path" "#project_path")
  workspace_dir=$(dirname "$prd_path")
  
  echo
  print_warning "Cleanup will remove:"
  echo "  Worktree: ${worktree_path:-Not created}"
  echo "  Workspace: $workspace_dir"
  echo
  read -r -p "Continue? (y/N) " -n 1
  echo
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Cleanup cancelled"
    exit 0
  fi
  
  # Remove worktree if it exists
  if [ -n "$worktree_path" ] && [ -d "$worktree_path" ]; then
    print_info "Removing worktree..."
    cd "$project_path"
    git worktree remove "$worktree_path" 2>/dev/null || true
  fi

  # Kill tmux session if it exists
  local tmux_session
  tmux_session=$(extract_metadata "$prd_path" "#tmux_session")
  if [ -n "$tmux_session" ] && tmux has-session -t "$tmux_session" 2>/dev/null; then
    print_info "Killing tmux session: $tmux_session"
    tmux kill-session -t "$tmux_session" 2>/dev/null || true
  fi

  # Remove workspace directory
  print_info "Removing workspace..."
  rm -rf "$workspace_dir"
  
  print_success "Cleanup complete"
}

# Show usage
show_usage() {
  cat << EOF
Ralph.sh - Autonomous AI coding agent using OpenCode

Usage:
  ralph.sh --project <path>                  Generate PRD (required)

  ralph.sh --prd <path to PRD>                Start Ralph loop
  ralph.sh --edit <path to PRD>                Edit existing PRD
  ralph.sh --status <path to PRD>              Show PRD status
  ralph.sh --cleanup <path to PRD>             Clean up workspace

Examples:
  ralph.sh --project ~/source/myproject
  ralph.sh --prd ~/source/ralph/myproject-rest/PRD.md
  ralph.sh --status ~/source/ralph/myproject-rest/PRD.md
  ralph.sh --cleanup ~/source/ralph/myproject-rest/PRD.md

For more information, see: https://github.com/opencode-ai/opencode
EOF
}

# Main
main() {
  local action=""
  local prd_path=""
  local project_path=""
  
  # Show help if no arguments
  if [ $# -eq 0 ]; then
    show_usage
    exit 0
  fi
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --prd)
        action="loop"
        prd_path="$2"
        shift 2
        ;;
      --edit)
        action="edit"
        prd_path="$2"
        shift 2
        ;;
      --status)
        action="status"
        prd_path="$2"
        shift 2
        ;;
      --cleanup)
        action="cleanup"
        prd_path="$2"
        shift 2
        ;;
      --project)
        project_path="$2"
        shift 2
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --*)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
      *)
        print_error "Unknown argument: $1"
        show_usage
        exit 1
        ;;
    esac
  done
  
  # Route to action
  case $action in
    loop)
      if [ -z "$prd_path" ]; then
        print_error "--prd requires a path"
        show_usage
        exit 1
      fi
      run_ralph_loop "$prd_path"
      ;;
    edit)
      if [ -z "$prd_path" ]; then
        print_error "--edit requires a path"
        show_usage
        exit 1
      fi
      edit_prd "$prd_path"
      ;;
    status)
      if [ -z "$prd_path" ]; then
        print_error "--status requires a path"
        show_usage
        exit 1
      fi
      show_status "$prd_path"
      ;;
    cleanup)
      if [ -z "$prd_path" ]; then
        print_error "--cleanup requires a path"
        show_usage
        exit 1
      fi
      cleanup_workspace "$prd_path"
      ;;
    "")
      # Default: generate PRD (but --project is now required)
      generate_prd "$project_path"
      ;;
    *)
      print_error "Unknown action: $action"
      show_usage
        exit 1
      ;;
  esac
}

# Run main
main "$@"
