# Sourced by hooks/agent-model.sh and scripts/resolve-models.sh: the one definition of the model names both read.
# The built-in Agent types that run on the parent session's model. agent-model.sh reads a user file entry under one of them, so the resolver does not warn on it.
BUILTIN_AGENT_TYPES='["general-purpose","Plan","Explore","claude"]'
# jq def: the one family alias a model value names, case-insensitive, or "" when it names none or several.
MODEL_FAMILY_JQ='def family: [ascii_downcase | scan("opus|sonnet|haiku|fable")] | unique | if length == 1 then .[0] else "" end;'
# The effort values an Agent call takes; mirrors EFFORTS in validate-plan.py, minus inherit.
EFFORT_VALUES='["low","medium","high","xhigh","max"]'
