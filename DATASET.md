# Local selection dataset

The app's Python worker records inference requests by default in
`results/selection-dataset/` beside this file. The existing `results/` Git ignore
rule excludes this private content from normal Git additions. Directory access
is restricted to this account (0700); records use 0600. This is local storage,
not app-level encryption. Records contain clipboard excerpts and destination
text that were included in a Jev request. They must be reviewed before sharing.

Each inference has an immutable UUID `.request.json` and `.result.json` pair:

- Request: exact constructed API request, C0/C1-to-history-ID mapping, UTC time,
  schema version and hashes of the request/context source files.
- Result: parsed API response (including probabilities/confidence/usage where
  supplied), final selection after local overrides, elapsed time, or a safe error.
- Labels start as `unlabelled`; request success is not evidence of correctness.
- The worker cannot observe whether the native app posted a paste, whether the
  destination accepted it, or whether the choice met the user's intent.

Authentication headers, the API key and the worker's credential-setup message
are never recorded. Error HTTP bodies and malformed responses are omitted.
Health checks and requests rejected before dispatch preparation are not recorded.
No screenshots, image/file bytes, or full untruncated history values are added.
Consequently this dataset supports replay of the selector's actual inputs; it
cannot recreate source context that was never captured or text already truncated.

A request is persisted before the HTTP attempt. A request without a matching
result indicates an interrupted or incomplete attempt, not a successful send.
If recording fails, selection returns an error instead of silently proceeding
without a dataset record. Records are retained until explicitly removed.

For evaluation, create a separate `<UUID>.label.json` sidecar containing the
expected candidate ID (C0, C1, etc.), or `ambiguous` / `none_suitable`, plus a brief
reason. Do not replace the recorded model answer with the label. `NONE` currently
means the selector requested a latest-clipboard fallback; it does not establish
that this fallback was correct.

Existing Python workers must restart to load this code. No Swift rebuild is
needed: choose **Troubleshooting → Restart Jev**. Check that a new request/result
pair appears after the next Smart Paste. Synthetic tests use temporary directories
and make no hosted calls. Direct uses of `JevSelector` outside the app record only
when explicitly given a recorder, keeping benchmarks out of the personal dataset.
