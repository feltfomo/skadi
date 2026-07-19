# Claim and unit keys

## Claim keys

| Key | Value | Scope |
| --- | --- | --- |
| `hosts` | list of host names or canonical IDs | user, system |
| `exceptHosts` | list of host names or canonical IDs | user, system |
| `users` | list of user IDs | user only |
| `exceptUsers` | list of user IDs | user only |
| `when` | context predicate | user, system |

Name claims must be lists of strings. A unit can't set both include and exclude keys for one axis.

`hosts = []` is impossible. `exceptHosts = []` is global. The same polarity laws apply to users.

## Reserved non-claim keys

| Key | Meaning |
| --- | --- |
| `children` | nested unit list |
| `value` | verbatim payload escape hatch |
| `label` | diagnostic/trace identity |
| `source` | source identity fallback |
| `mergeProfile` | unit-level profile name for profiled doors |

`label`, `source`, and `mergeProfile` must be strings when their corresponding path validates them. A parent identity or merge profile does not inherit into children.
