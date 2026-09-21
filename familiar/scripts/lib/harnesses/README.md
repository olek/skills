# Familiar harness definitions

Each `*.sh` file in this directory is one drop-in Familiar harness. The file
basename, without `.sh`, is the harness name. The shared loader discovers the
files and sources only the selected harness, so adding one requires no central
registry edit.

Each harness implements the same generic function contract:

```text
familiar_harness_executable
familiar_harness_models
familiar_harness_efforts
familiar_harness_intent_pair <planning|implementation|review>
familiar_harness_build_command <cwd> <session_name> <prompt> <model> <effort> <status_line_config>
```

The executable, models, and efforts are printed to standard output. Models and
efforts are one entry per line. `intent_pair` returns the model and effort on
one line, separated by one space, for the defaults CLI to name. `build_command`
prints the complete pane command and owns all harness-specific flags and
environment prefixes.

Either field in an intent pair may be `default`, meaning the caller omits that
launcher option and lets the harness CLI use its configured default. This
sentinel belongs only to intent pairs and must not appear in model or effort
catalogs or be passed as an explicit launcher value.

The caller always selects a harness explicitly. There is no registry default,
and the summon launcher requires `--harness`, rejecting a missing or unknown
value.

Model and effort catalogs are informational and harness-owned. A definition may
print a stable embedded list or delegate to its harness CLI when availability is
configuration-dependent. The launcher remains an opaque `--model` pass-through
and does not translate model names between vendors.
