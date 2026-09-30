# Harness contract

Each `*.sh` filename is a harness name. The loader sources the selected file.
It defines:

```text
familiar_harness_executable
familiar_harness_build_command <cwd> <session_name> <prompt> <model> <effort>
```

The executable function prints its CLI name. The command builder prints the
complete shell command and owns its flags and environment. An empty model or
effort means omit that override. The harness may ignore the session name if
its CLI has no naming option.
