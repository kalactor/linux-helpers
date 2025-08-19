#!/usr/bin/env bash
# timeshift.sh - safer Timeshift helper (create / list / restore / delete)
# Improved parsing, numeric validation, non-interactive options.
#
# Usage:
#   ./timeshift.sh            # interactive menu
#   ./timeshift.sh --list
#   ./timeshift.sh --create
#   ./timeshift.sh --restore 3
#   ./timeshift.sh --delete 3
#   ./timeshift.sh --restore 3 --target /dev/sda1 --yes
#
# Notes:
# - This script expects `timeshift` to be installed and in PATH.
# - It strips potential ANSI escapes from timeshift output before parsing.

set -euo pipefail

###############################################################################
# Helpers
###############################################################################

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

confirm() {
  # Usage: confirm "Prompt message" [default_no]
  local prompt="${1:-Are you sure? [y/N]: }"
  local default_no=${2:-1}
  read -r -p "$prompt" answer || return 1
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    return 0
  fi
  if [[ $default_no -eq 0 && "$answer" =~ ^[Nn]$ ]]; then
    return 1
  fi
  return 1
}

strip_ansi() {
  # Read stdin, strip common ANSI escape sequences
  sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

# Return a parseable timeshift --list with row numbers
timeshift_list_clean() {
  # timeshift --list output -> remove ANSI escapes -> remove leading/trailing blank lines
  timeshift --list 2>/dev/null | strip_ansi | sed '/^\s*$/d'
}

# Given a snapshot number (as shown by timeshift --list), return snapshot name
get_snapshot_name_by_num() {
  local num="$1"
  if ! [[ "$num" =~ ^[0-9]+$ ]]; then
    echo ""
    return 1
  fi
  # timeshift --list typically formats with number in $1 and snapshot name in $2.
  # Use awk to find the row whose first field equals num and print the second field (snapshot name).
  timeshift_list_clean | awk -v n="$num" '$1==n {print $2; exit}'
}

# Print timeshift list in a friendly way
show_timeshift_list() {
  echo "---- Timeshift snapshots ----"
  timeshift --list 2>/dev/null || echo "(timeshift returned non-zero or no output)"
  echo "-----------------------------"
}

###############################################################################
# Core operations
###############################################################################

do_create_snapshot() {
  echo "Creating Timeshift snapshot..."
  # timeshift create may require sudo; let it prompt if needed
  if timeshift --create --comments "manual snapshot $(date '+%Y-%m-%d %H:%M:%S')" --tags D ; then
    echo "Snapshot created successfully."
  else
    die "timeshift --create failed."
  fi
}

do_restore_snapshot_by_num() {
  local num="$1"
  local target_arg="${2:-}"  # e.g. --target /dev/sda1
  local auto_yes="${3:-}"    # if 'yes' run without confirmation

  local snap_name
  snap_name=$(get_snapshot_name_by_num "$num") || true

  if [ -z "${snap_name:-}" ]; then
    echo "Unable to parse snapshot name for number: $num"
    echo "Showing available snapshots for manual selection:"
    show_timeshift_list
    die "Restore aborted."
  fi

  echo "Selected snapshot: $snap_name (number: $num)"

  if [ "${auto_yes:-}" != "yes" ]; then
    if ! confirm "Are you sure you want to restore snapshot '$snap_name'? THIS WILL OVERWRITE CURRENT SYSTEM! [y/N]: "; then
      echo "Restore cancelled."
      return 0
    fi
  fi

  echo "Starting restore..."
  # Add target argument if provided (e.g., --target /dev/sda1).
  if timeshift --restore --snapshot "$snap_name" ${target_arg:+--target "$target_arg"} --yes; then
    echo "Restore finished. Reboot recommended."
    return 0
  else
    die "timeshift --restore failed."
  fi
}

do_delete_snapshot_by_num() {
  local num="$1"
  local snap_name
  snap_name=$(get_snapshot_name_by_num "$num") || true

  if [ -z "${snap_name:-}" ]; then
    echo "Unable to parse snapshot name for number: $num"
    show_timeshift_list
    die "Delete aborted."
  fi

  echo "Selected snapshot for deletion: $snap_name (number: $num)"
  if ! confirm "Delete snapshot '$snap_name'? This action is irreversible. [y/N]: "; then
    echo "Delete cancelled."
    return 0
  fi

  echo "Deleting snapshot..."
  if timeshift --delete --snapshot "$snap_name" --yes; then
    echo "Snapshot deleted."
    return 0
  else
    die "timeshift --delete failed."
  fi
}

###############################################################################
# CLI parsing & interactive menu
###############################################################################

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --help                 Show this help
  --list                 List snapshots (non-interactive)
  --create               Create a snapshot (non-interactive)
  --restore <N>          Restore snapshot number N (non-interactive)
  --delete  <N>          Delete snapshot number N (non-interactive)
  --target <device>      Use with --restore; specify target device (e.g. /dev/sda1)
  --yes                  Assume yes for confirmations
EOF
}

# Check timeshift exists
require_cmd timeshift

# If no args => interactive menu
if [ "$#" -eq 0 ]; then
  while true; do
    cat <<MENU

Timeshift helper - choose an action:
1) Create snapshot
2) List snapshots
3) Restore snapshot (by number)
4) Delete snapshot (by number)
5) Exit

MENU
    read -r -p "Enter choice [1-5]: " CHOICE || { echo; exit 1; }

    case "$CHOICE" in
      1)
        do_create_snapshot
        ;;
      2)
        show_timeshift_list
        ;;
      3)
        show_timeshift_list
        read -r -p "Enter snapshot number to restore: " SNAP_NUM
        if ! [[ "$SNAP_NUM" =~ ^[0-9]+$ ]]; then
          echo "Invalid number: $SNAP_NUM"
          continue
        fi
        do_restore_snapshot_by_num "$SNAP_NUM"
        ;;
      4)
        show_timeshift_list
        read -r -p "Enter snapshot number to delete: " SNAP_NUM
        if ! [[ "$SNAP_NUM" =~ ^[0-9]+$ ]]; then
          echo "Invalid number: $SNAP_NUM"
          continue
        fi
        do_delete_snapshot_by_num "$SNAP_NUM"
        ;;
      5)
        echo "Bye."
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
fi

# Non-interactive flags
TARGET=""
AUTO_YES="no"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_usage
      exit 0
      ;;
    --list)
      show_timeshift_list
      exit 0
      ;;
    --create)
      do_create_snapshot
      exit 0
      ;;
    --restore)
      shift
      if [ -z "${1:-}" ]; then die "--restore requires a snapshot number"; fi
      SNAP_NUM="$1"
      # Validate
      if ! [[ "$SNAP_NUM" =~ ^[0-9]+$ ]]; then die "Snapshot number must be an integer."; fi
      shift
      # Optionally accept --target and --yes after restore number
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --target)
            shift
            TARGET="${1:-}"
            if [ -z "$TARGET" ]; then die "--target requires a value"; fi
            ;;
          --yes)
            AUTO_YES="yes"
            ;;
          *)
            die "Unknown option after --restore: $1"
            ;;
        esac
        shift
      done
      do_restore_snapshot_by_num "$SNAP_NUM" "$TARGET" "$AUTO_YES"
      exit $?
      ;;
    --delete)
      shift
      if [ -z "${1:-}" ]; then die "--delete requires a snapshot number"; fi
      SNAP_NUM="$1"
      if ! [[ "$SNAP_NUM" =~ ^[0-9]+$ ]]; then die "Snapshot number must be an integer."; fi
      do_delete_snapshot_by_num "$SNAP_NUM"
      exit $?
      ;;
    --target)
      shift
      TARGET="${1:-}"
      if [ -z "$TARGET" ]; then die "--target requires a value"; fi
      shift
      ;;
    --yes)
      AUTO_YES="yes"
      shift
      ;;
    *)
      die "Unknown option: $1. Run with --help."
      ;;
  esac
done
