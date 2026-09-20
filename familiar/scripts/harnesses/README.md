# Familiar harness definitions

Each `*.sh` file in this directory is one drop-in Familiar harness. The file
basename, without `.sh`, is the harness name. The shared loader discovers and
sources every file in this directory, so adding a harness means adding one file
and making no central registry edit.

Use the following namespaced functions as the definition contract, replacing
`<name>` with the file basename:

```text
familiar_harness_<name>_executable
familiar_harness_<name>_models
familiar_harness_<name>_efforts
familiar_harness_<name>_supports_session_name
familiar_harness_<name>_validate_effort <effort>
familiar_harness_<name>_intent_model <planning|implementation|review>
familiar_harness_<name>_intent_effort <planning|implementation|review>
familiar_harness_<name>_build_command <cwd> <session_name> <prompt> <model> <effort> <status_line_config>
```

The executable, models, efforts, session-name support flag, and intent
suggestions are printed to standard output. Models and efforts are one entry per
line. `validate_effort` returns success or failure and must not silently rewrite
the supplied effort. `intent_model` and `intent_effort` return the model-effort
pair for the requested intent. `build_command` prints the complete
pane command and owns all harness-specific flags and environment prefixes.

The caller always selects a harness explicitly. There is no registry default,
and the summon launcher requires `--harness`, rejecting a missing or unknown
value.

The embedded model and effort catalog is informational and hand-maintained. It
does not fetch or cache data at runtime. The launcher remains an opaque
`--model` pass-through and does not translate model names between vendors.

`opencode` and `antigravity` are planned drop-in harnesses; support is not yet
implemented.
