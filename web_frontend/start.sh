#!/bin/sh
# Runs the CMi web frontend. The Python 3 virtualenv is created on first launch, and refreshed when requirements.txt changes.
set -e
cd "$(dirname "$0")"

SUPPORT_FOLDER="${CMI_SUPPORT_FOLDER:-$HOME/Library/Application Support/CMi}"
VENV="$SUPPORT_FOLDER/venv"

# Apps launched from Finder get a minimal PATH, so look where Python 3 is usually installed
export PATH="$HOME/.local/bin:$HOME/.pyenv/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! cmp -s requirements.txt "$VENV/requirements.txt"; then
    echo "Setting up Python environment in $VENV..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check --upgrade -r requirements.txt
    cp requirements.txt "$VENV/requirements.txt"
fi

exec "$VENV/bin/python" CMi/runserver.py
