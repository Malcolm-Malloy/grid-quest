# Grid Quest

A top-down, grid-based game built in Godot 4.

## Requirements

- Godot 4.7 (GL Compatibility renderer)

## Running

Open the project folder in Godot and run the main scene (`main.tscn`), or launch from the command line:

```
godot --path .
```

## Branching

This repo follows a protected-branch workflow:

- `master` and `develop` are protected. Do not commit or push to them directly.
- Do all work on a feature branch (`type/short-description`, e.g. `feat/gate-shadows`), branched off `develop`.
- Merges into `develop` or `master` happen via pull request only.

Tests and a CI/CD pipeline will be added in a later pass.
