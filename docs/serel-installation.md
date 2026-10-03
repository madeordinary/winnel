# Serel development tooling

The repository includes Serel Memory v0.6.0 and Serel Kit v0.2.0 adapters for Codex and Claude Code. Kit includes the `writing` and `verify` packs; hooks are off. Serel is development tooling and is not copied into Winnel.app.

| Component | Pinned source |
|---|---|
| Memory v0.6.0 | `5f99244d648735db94429bf4e77571325160e5ec` |
| Kit v0.2.0 | `a4b7b29b9b80e72294e601da2c264f8a9082a795` |

Framework source bytes and Kit receipt hashes were checked against the pinned releases. The Memory anchor and installer-produced Kit receipt remain tracked; third-party notices are in `THIRD_PARTY_NOTICES/`. Do not edit receipts to conceal conflicts or drift.

Framework workflows are shared, but each developer's populated `memory-bank/`, `.rules`, `GOAL.md` and raw `docs/evidence/` are ignored. A fresh clone therefore has no populated local bank. Initialize from the actual code and `PRD.md` using the installed `init-memory` workflow; do not reseed an existing bank. Publish only reviewed durable findings in contributor docs.

See [setup guidance](serel-setup-notes.md) and [contributor privacy rules](../CONTRIBUTING.md#documentation-and-local-memory).
