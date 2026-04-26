# Plan — Issue #3: Blocklist CRUD + FamilyActivityPicker

## Context

Blocklists are the primary unit of configuration — every schedule (#4), one-shot block (#5), and break (#7) references one. This slice introduces the first real SwiftData model, sets the persistence pattern the rest of the app follows, and wires up Apple's `FamilyActivityPicker` so the user can actually pick apps. Everything downstream is unblocked once this ships.

## Approach

One SwiftData model (`Blocklist`), one thin store (`BlocklistStore`), two SwiftUI views (list + editor). `FamilyActivityPicker` is embedded directly — it owns its own selection UI; we just bind a `FamilyActivitySelection` to it and persist the encoded form.

**Encoding `FamilyActivitySelection`:** the type conforms to `Codable` (since iOS 15), so SwiftData stores it as a blob via a `Data` property on the model, encoded/decoded through a computed accessor. Using `PropertyListEncoder` — the selection contains opaque Apple tokens, and property list is what Apple's sample code uses.

**Uniqueness:** `name` is `@Attribute(.unique)` so SwiftData enforces at the store level. UI catches duplicates by catching the save error and surfacing an inline error state.

**Deletion guard:** the `Schedule` model doesn't exist yet (comes in #4). This slice deletes blocklists freely. Issue #4 adds the guard that blocks deletion when a schedule references the blocklist.

## File plan

- `Brick/Models/Blocklist.swift` — `@Model final class Blocklist` with `name` (unique), `activitySelectionData: Data`, `createdDate: Date`, plus a computed `selection: FamilyActivitySelection` accessor that encodes/decodes the blob.
- `Brick/Models/BlocklistStore.swift` — `struct BlocklistStore` wrapping a `ModelContext`. Methods: `create(name:) throws -> Blocklist`, `rename(_:to:) throws`, `updateSelection(_:to:)`, `delete(_:)`, `all() throws -> [Blocklist]`, `find(id:) -> Blocklist?`. Throws `BlocklistStoreError.duplicateName` / `.emptyName`.
- `Brick/BrickApp.swift` — add `Blocklist.self` to the `Schema([...])`.
- `Brick/Views/BlocklistsTab.swift` — replace placeholder with `BlocklistsListView` wrapped in `NavigationStack`.
- `Brick/Views/Blocklists/BlocklistsListView.swift` — `@Query(sort: \.createdDate)` list, swipe-to-delete, toolbar `+` to create, `NavigationLink` row to editor, empty state via `ContentUnavailableView`.
- `Brick/Views/Blocklists/BlocklistEditorView.swift` — name `TextField`, embedded `FamilyActivityPicker` with `@State private var selection: FamilyActivitySelection`, count summary ("12 apps, 3 categories"), save button, inline duplicate-name error.

Final tree addition:
```
Brick/
├── Models/
│   ├── Blocklist.swift
│   └── BlocklistStore.swift
├── Views/
│   ├── Blocklists/
│   │   ├── BlocklistsListView.swift
│   │   └── BlocklistEditorView.swift
│   └── BlocklistsTab.swift                 # rewired
```

## Edge cases covered

- **Empty name** — save disabled until non-empty after trim.
- **Duplicate name** — unique constraint throws on save; UI surfaces "Name already in use" under the text field without losing user's work.
- **Rename to existing** — same path as duplicate on create.
- **Empty selection** — allowed. A blocklist with no apps is a valid-but-inert config; enforcing non-empty here would thrash users who open the picker after naming the list.

## Verification plan

1. `xcodegen generate && xcodebuild ... build` still succeeds.
2. On device: open Blocklists tab, empty state shown. Tap `+`, name "Social", pick Instagram + TikTok via `FamilyActivityPicker`, save. List shows "Social — 2 apps."
3. Tap the row: editor opens with name populated and selection preserved. Rename to "Distractions." Save. List updates.
4. Kill app, relaunch: the blocklist is still there (SwiftData persistence works).
5. Swipe-delete: row disappears, empty state returns.
6. Create two blocklists with the same name: second save shows duplicate error inline.
