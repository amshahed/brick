# Issue #31 — Blocklist app count doubled

## Problem
The row in the Blocklists list and the editor's summary line both report 2× the actual number of picked apps/categories/domains.

## Root cause
`FamilyActivitySelection` has two parallel sets per kind:

| Token set | Metadata set |
|---|---|
| `applicationTokens` | `applications` |
| `categoryTokens` | `categories` |
| `webDomainTokens` | `webDomains` |

Under `.individual` authorization, the FamilyActivityPicker populates **both** sets with the same picked items (each `Application` carries an `ApplicationToken` that also appears in `applicationTokens`). Two display sites add the counts together:

- `Shared/Models/Blocklist.swift:22-33` — `selectionSummary` (drives the row and `ActiveBlockCard.swift:71`)
- `Brick/Views/Blocklists/BlocklistEditorView.swift:138-139` — `summary`

## Fix
Use `max(tokens.count, structs.count)` instead of summing. Same change in both files.

The actual blocking logic in `ShieldManager.swift` is unaffected — it unions only the token sets (lines 70-72).

## Acceptance
- [ ] Picking N apps shows "N apps" on the row
- [ ] Same for categories and web domains
- [ ] Editor summary matches
- [ ] No change to which apps are shielded (verify by toggling an existing schedule on/off)
