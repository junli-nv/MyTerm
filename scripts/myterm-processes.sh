#!/bin/bash
# MCP stdio adapters belong to their Codex/IDE parent, not the GUI application.
# Match process arguments, not merely the shared executable name. An adapter can
# survive an app restart and reconnect to the current bridge on its next request.
myterm_gui_running() {
    local process_id process_command
    while IFS= read -r process_id; do
        process_command=$(/bin/ps -p "$process_id" -o command=) || continue
        case " $process_command " in
            *" --myterm-mcp "*) continue ;;
        esac
        return 0
    done < <(/usr/bin/pgrep -x MyTerm || true)
    return 1
}
