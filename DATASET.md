# Development selection datasets

Normal builds contain no dataset recorder and ignore `CUEKIT_DATASET_ROOT`.
Evaluation timing logs are also compiled out. Python is retained only for
synthetic tests, benchmarks and reference evaluation, not the shipped app.

To collect an explicitly opted-in development dataset:

1. Build with `./build.sh --development` (do not distribute this build).
2. Quit running Cuekit instances.
3. Launch the development executable from Terminal with a private output path:

```sh
CUEKIT_DATASET_ROOT="$PWD/results/selection-dataset" "$PWD/Cuekit.app/Contents/MacOS/LayaClipboard"
```

Only this process receives the setting. A development build without an output
path does not collect records. Return to `./build.sh` for a normal build; the
build fingerprint distinguishes the configurations.

Records contain clipboard excerpts and destination text sent to Jev. They are
local, not encrypted by the app, and must be reviewed before sharing. The output
directory must belong to this account with mode 0700; files use 0600. `results/`
is Git-ignored. Clear History does not erase datasets; retain or remove these
files deliberately.

Each native inference produces immutable UUID `.request.json` and `.result.json`
files using schema version 2:

- Request: exact constructed API request, C0/C1-to-history-ID mapping, UTC time,
  and an initially unlabelled status. Native records do not include source hashes.
- Result: parsed valid API response, final Jev-only selection or confidence/NONE
  fallback, elapsed time, or a safe error.
- The client cannot observe whether the destination accepted a paste or whether
  the choice met the user’s intent. Success is not a correctness label.

Authentication headers and the API key are excluded. Requests containing the
configured key are rejected. Error HTTP bodies and malformed responses are
omitted. Connection checks are not recorded. Images/file bytes and full history
are not added; records cannot recover context omitted or truncated before send.

The request is persisted before the HTTP attempt. A request without a result
means interrupted/incomplete, not successful. Recording failure blocks selection
in this explicitly enabled mode. Records are retained until removed.

For evaluation, add a separate `<UUID>.label.json` with an expected candidate ID,
`ambiguous` or `none_suitable`, and a reason. Keep labels separate from model
answers. Neither `NONE` nor a low-confidence fallback establishes correctness.

The Python reference recorder retains its schema-1 source hashes for development
benchmarks. Direct `JevSelector` use records only when supplied a recorder; the
legacy development worker requires `CUEKIT_DATASET_ROOT`. Synthetic tests use
temporary directories and no hosted calls. Paid benchmarks must be run explicitly.
