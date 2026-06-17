# Karpathy Guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

# Project Specific Instructions

## Project Overview

Applebox (`box`) is a CLI tool for creating and managing persistent Linux
development containers on macOS, similar to `toolbox` on Fedora. It is
built with Swift Package Manager and uses Apple's
[container](https://github.com/apple/container) and
[containerization](https://github.com/apple/containerization) frameworks
for lightweight Linux VMs via the Virtualization framework.

The codebase lives under a single executable target:

- **Sources/applebox/** -- Entry point (`Applebox.swift`), CLI commands
  (`Commands/`), container helpers (`Container/`), and supported distro
  definitions.
- **Tests/AppleboxTests/** -- Unit tests.

Commands are implemented as `AsyncParsableCommand` subcommands using
Swift Argument Parser: `create`, `enter`, `run`, `list`, and `rm`.

## Build & Test

- Build: `make` (or `swift build`).
- Install: `make install` (installs to `/usr/local/bin/box` by default;
  override with `INSTALL_PREFIX`).
- Run tests: `swift test`.
- Release build: `make PROFILE=release`.
- Requires macOS 26.0 (Tahoe) and Swift 6.2 or later.

## Code Conventions

- **Swift 6** with strict concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`). Respect `Sendable` and actor-isolation rules.
- Prefer `Task @MainActor` over `DispatchQueue.main.async` for main
  queue execution.
- Use `@Observable` and `@Environment` for state management.
- Bridge SDK callbacks to Swift concurrency with `AsyncStream`.
- Keep commits focused and atomic. Use imperative mood, sentence-case
  commit messages (e.g. "Add thread support to timeline view").
- Comments should reflect the current state of the code. Documentation
  should not discuss previous iterations of the code, only the current one.

## Commit Conventions

- Include a summary of what changed in the commit message.
- When authoring a commit, use either `Assisted-By: <name of code assistant>` or
  `Generated-By: <name of code assistant"` in the commit message
  footer.
  - **Assisted-By**: You directed the work and edited meaningfully
    (default for typical use).
  - **Generated-By**:  A substantial portion was generated with
    minimal human edit (e.g. full file scaffold).
- Never push commits without explicit approval from the user.

## Architecture Rules

- Commands (`Commands/`) interact with containers through `ContainerClient`
  (from `ContainerAPIClient`) and the toolbox extension methods in
  `ContainerClient+Toolbox.swift`. Commands should not import
  `Containerization`, `ContainerizationError`, or `ContainerizationOCI`
  directly; keep lower-level container configuration logic in the
  `Container/` layer. The one exception is `Create.swift`, which imports
  `ContainerizationOCI` and `ContainerResource` for image pulling.
- `SupportedDistro` and `ToolboxPaths` depend only on `Foundation` (and
  `ArgumentParser` for `SupportedDistro`). They must not import any
  container framework.
- Shell scripts are embedded as string constants in `ToolboxPaths.swift`.
  The `Resources/` directory contains reference copies but is excluded
  from the build target; do not add SPM resource bundling.
- All logging goes through `Applebox.logger`. Each command must call
  `Applebox.applyLogging(options)` as the first line of its `run()` method.
- All applebox-specific errors are defined in `AppleboxError`. Do not
  scatter error types across files.

## CLI Design

Applebox is a terminal tool. Follow conventions established by `toolbox`,
`podman`, and other container CLIs:

- Keep output concise and machine-parseable where practical (e.g. `list`
  uses columnar output).
- Use stderr for log/diagnostic messages and stdout for primary output.
- Exit with non-zero status on errors.
- Provide helpful error messages that suggest corrective action when
  possible.

## Swift Instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.

## SwiftUI Instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
