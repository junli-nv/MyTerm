import Foundation

enum CodexTransferTools {
    static let tools: [[String: Any]] = [
        ["name": "upload_items",
         "description": CodexTransferPolicy.scope + " Upload local files and/or recursive directories from the Mac running MyTerm to the currently associated SSH tab, using its existing SFTP transport (jumps/proxies retained). For this explicitly requested upload, MyTerm reads the files; do not encode local file bytes in SSH commands or use Git as an upload substitute. Each selected basename is placed under an existing absolute remote_directory. Preserves empty directories, merges directories without deleting remote-only files. Default conflict=error leaves differing files untouched; identical completed files may be skipped for retry. Links/special files are rejected. Exclusions are explicit relative glob patterns: basename patterns match any component; slash patterns match paths relative to the selection's parent (including its basename), * does not cross /. No implicit exclusions. Requires execution authorization and one allowance. EVERY upload needs separate MyTerm Allow Once, even with command Always Allow. Print source paths, target, policy and reason. Returns job_id; poll transfer_status (at most once/sec) until terminal state; report failures/partial results. Never resubmit to poll. Local macOS file permissions apply.",
         "inputSchema": ["type": "object", "properties": [
            "session_id": ["type": "string"],
            "local_paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 64],
            "remote_directory": ["type": "string", "description": "Existing absolute destination directory; independent of interactive shell cwd"],
            "conflict": ["type": "string", "enum": ["error", "skip", "overwrite"], "default": "error"],
            "exclude": ["type": "array", "items": ["type": "string"], "maxItems": 64],
            "reason": ["type": "string", "maxLength": 1024]],
            "required": ["session_id", "local_paths", "remote_directory", "reason"], "additionalProperties": false],
         "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false]],
        ["name": "download_items",
         "description": CodexTransferPolicy.scope + " Download remote files and/or recursive directories from the associated SSH tab to an existing local directory on the Mac running MyTerm, over its existing SFTP transport. Each remote basename is placed inside local_directory. Preserves empty/hidden directories and remote-only/local-only files; no deletion. conflict defaults to error; skip/overwrite must match the user's request. Identical completed files may be skipped for retry. Links/special files are rejected. exclude follows upload_items glob rules. Requires execution authorization and one allowance; EVERY transfer needs MyTerm Allow Once, independently of command Always Allow. Show exact remote sources, local directory, conflicts, exclusions and reason. Poll transfer_status serially at most once/sec; report failures, partial results and truncation. macOS local write permissions apply. File contents never pass through model context.",
         "inputSchema": ["type": "object", "properties": [
            "session_id": ["type": "string"],
            "remote_paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 64],
            "local_directory": ["type": "string", "description": "Existing absolute local directory or ~/ directory"],
            "conflict": ["type": "string", "enum": ["error", "skip", "overwrite"], "default": "error"],
            "exclude": ["type": "array", "items": ["type": "string"], "maxItems": 64],
            "reason": ["type": "string", "maxLength": 1024]],
            "required": ["session_id", "remote_paths", "local_directory", "reason"], "additionalProperties": false],
         "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false]],
        ["name": "transfer_status", "description": "Read the existing transfer's state, overall/current-file progress, completed/skipped/failed counts and bounded failures (up to 50 / 8 KiB; inspect failures_truncated). Poll serially at most once per second. completed means success; rejected means pending work was declined/cancelled; failed/cancelled can leave completed files and resumable partials. No terminal text or file contents are returned.",
         "inputSchema": jobSchema, "annotations": ["readOnlyHint": true, "destructiveHint": false]],
        ["name": "cancel_transfer", "description": "Cancel this association's pending, queued or running upload/download. Already completed files remain; matching partial files may be resumed by a separately approved retry. Does not disconnect the SSH tab.",
         "inputSchema": jobSchema, "annotations": ["readOnlyHint": false, "destructiveHint": true]]
    ]
    private static let jobSchema: [String: Any] = ["type": "object", "properties": ["session_id": ["type": "string"], "job_id": ["type": "string"]], "required": ["session_id", "job_id"], "additionalProperties": false]
}
