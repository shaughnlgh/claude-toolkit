#!/usr/bin/env bash
# Behavior tests for topic-recall.py. Every case builds its own temporary vault and HOME.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -I "$HERE/test_topic_recall.py"
