#!/usr/bin/env bash
# ============================================================
# EverSpark Forge - Junk Rules V1
#
# Single source of truth for disposable ComfyUI files.
#
# Used by:
#   - clean_local_junk.sh
#   - push_incremental.sh rclone excludes
#   - manual R2 cleanup commands/scripts
#
# Policy:
#   R2 is a runtime asset/state store, not a full Git source mirror.
#   Keep plugin runtime code and required model assets.
#   Drop cache, Python bytecode, dev docs, examples, samples, and old demo workflows.
# ============================================================

# rclone filter patterns.
# These are passed as repeated:
#   --exclude "<pattern>"
JUNK_RCLONE_EXCLUDES=(
  "**/.cache/**"
  "**/__pycache__/**"
  "**/*.pyc"
  "**/.git/**"
  "**/.gitignore"
  "**/.DS_Store"
  "**/Thumbs.db"
  "**/*.tmp"
  "**/*.log"
  "**/*.lock"
  "**/README*"
  "**/readme*"
  "**/LICENSE*"
  "**/license*"
  "**/docs/**"
  "**/examples/**"
  "**/example_workflows/**"
  "**/samples/**"
  "**/old_workflows/**"
)

# Local directory names to remove anywhere under COMFYUI_ROOT.
JUNK_LOCAL_DIR_NAMES=(
  ".cache"
  "__pycache__"
  ".git"
  "docs"
  "examples"
  "example_workflows"
  "samples"
  "old_workflows"
)

# Local file globs to remove anywhere under COMFYUI_ROOT.
JUNK_LOCAL_FILE_GLOBS=(
  "*.pyc"
  ".gitignore"
  ".DS_Store"
  "Thumbs.db"
  "*.tmp"
  "*.log"
  "*.lock"
  "README*"
  "readme*"
  "LICENSE*"
  "license*"
)

# Extra known ComfyUI runtime cache paths relative to COMFYUI_ROOT.
JUNK_LOCAL_REL_PATHS=(
  "user/__manager/cache"
)
