# Familiar harness definitions

Each `*.sh` file in this directory is one drop-in Familiar harness. The file
basename, without `.sh`, is the harness name. The shared loader discovers the
files and sources only the selected harness, so adding one requires no central
registry edit.

Each harness implements the same generic function contract:

```text
familiar_harness_executable
familiar_harness_build_command \
  <cwd> <session_name> <prompt> <model> <effort> <status_line_config>
```

The executable is printed to standard output. `build_command` prints the
complete pane command and owns all harness-specific flags and environment
prefixes. Intent choices live in the user-owned configuration file; without a
matching entry, the launcher omits model and effort overrides.

Either field in an intent pair may be `default`, meaning the caller omits that
launcher option and lets the harness CLI use its configured default. This
sentinel must not be passed as an explicit launcher value.

The caller always selects a harness explicitly. There is no registry default,
and the summon launcher requires `--harness`, rejecting a missing or unknown
value.

The launcher remains an opaque `--model` pass-through and does not translate
model names between vendors.
