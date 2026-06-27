# Contributing

Thanks for taking a look at Cog.

Before opening a pull request:

- Run `cd Cog && xcodegen generate`.
- Run the simulator test command from `README.md` when your change touches app code.
- Keep signing credentials, provisioning profiles, `.asc/`, DerivedData, and local agent files out of commits.
- Prefer small, focused pull requests with a plain-English description of the behavior change.

For UI changes, keep SwiftUI controls accessible: icon-only buttons should use `Label(...).labelStyle(.iconOnly)` rather than bare `Image` labels.
