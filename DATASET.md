# Local Smart Paste training dataset

Normal builds record every Smart Paste invocation automatically, including invocations
rejected as busy and attempts that stop before inference. Launching from Applications
requires no environment variable. Demo mode does not record.

Location: `~/Library/Application Support/Jev Clipboard/SmartPasteDataset/`.
Each invocation creates a UUID-named `.attempt.jsonl` journal (schema 3), retained
until explicitly removed. Clear History and clipboard eviction do not remove it.
The directory is account-only (0700), files are 0600, and data is not encrypted by
the app. No dataset upload is implemented. The existing hosted inference still sends
its usual request to TypeSafe; recording does not make inference local.

## Journal format and coverage

Each newline-delimited JSON entry includes `record_id`, monotonic `sequence`, UTC
`timestamp`, `event`, and `data`. All entries in one file share its UUID, also used
by the content-free diagnostic trace.

- `attempt`: schema version, model name, `label_status: unlabelled`, and unobserved
  paste outcome. Created and synchronized before permission/connection checks.
- `stage`: accepted, capture/ranking/validation stages, fallback, paste preparation,
  failure, cancellation, or `paste_posted`, with static reason codes and timings.
- `request`: exact constructed model body and C0/C1-to-history-ID mapping, saved
  before the HTTP attempt. `prepared_send_not_confirmed` is not proof of delivery.
- `response`: valid parsed model response, final selection/fallback and elapsed
  inference time. It is saved before returning the selection to the paste flow.
- `inference_failed`: an allowlisted reason, never an arbitrary error body.

Early failures and busy invocations have their own files even when there is no model
request. Cancellation and normal app shutdown have terminal stages. A model response
may arrive after a cancellation; it does not change that attempt's cancelled outcome.
An abrupt crash can leave no terminal stage or an incomplete final line: ignore only
that trailing partial line and classify the attempt as incomplete, never successful.

`paste_prepared` means dispatch was prepared; `paste_posted` means all keyboard
events were sent. Neither confirms target acceptance, insertion, user satisfaction,
or a correct model choice. No-history fallbacks record stages but have no model
request or raw clipboard snapshot. Repeated key-down auto-repeat suppressed by the
shortcut latch is not a new invocation. Ordinary copies and manual history pastes
are not dataset events.

## Content boundaries and failures

Request examples contain only the context and candidate excerpts actually sent to
Jev; they cannot reconstruct omitted/truncated context. Images and file bytes are
not copied into this dataset. Authentication headers and the configured API key are
excluded. Content that fails the existing configured-key checks is rejected before
request persistence; the rejected attempt still has a metadata-only record. Other
private information present in model inputs is retained, as authorized for training.
Malformed/secret-bearing responses and raw HTTP error bodies are not recorded.

Writes are serialized within an attempt and synchronized to disk. Unsafe output
directories, serialization errors, or storage failures block inference/paste before
dispatch and show an error. A failure saving the final outcome after dispatch produces
a distinct recording warning, not a claim that nothing was pasted. Disk failure can
prevent a record from being created at all; the app never promises impossible storage
guarantees. Persistent write failure remains an error for that attempt.

## Training labels

Keep human corrections in a separate `<UUID>.label.json`, using the same record ID,
an expected candidate ID, `ambiguous` or `none_suitable`, and a reason. Model responses
are teacher predictions, not verified ground truth. Keep cancelled, failed, incomplete,
and unlabelled examples distinguishable when preparing training/evaluation splits.

## Legacy development recorder

The optional schema-2 development recorder remains available with `--development`
and `CUEKIT_DATASET_ROOT`. Normal builds ignore that environment variable. Enabling
it creates an additional request/result export alongside the always-on attempt journal;
it is not needed for everyday collection. Existing records remain compatible and are
not migrated or deleted. Synthetic tests use isolated temporary folders and mock
transport; they do not record real clipboard content or call the hosted model.
