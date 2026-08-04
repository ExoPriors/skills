# Contributing

This repository is a publish target. The `skills/` tree is canonical in ExoPriors' internal repository and projected here; direct edits to this repo are overwritten on the next sync.

## Reporting problems

Open an issue for defects, stale claims, or broken examples. The standing contract: skills must match the live API. `GET /v1/scry/schema` is the discovery authority — anything a skill claims that the schema does not advertise is a bug in the skill, and an example that errors on copy-paste is always a bug.

Pull requests against `skills/` cannot be merged as-is (the next sync would overwrite them), but a PR is a fine way to show an exact fix — it gets applied upstream and synced back with credit in the sync commit.

## Skill structure

Each skill follows the [Anthropic Agent Skills Spec](https://github.com/anthropics/skills/blob/main/spec/agent-skills-spec.md):

```
skills/<name>/
  SKILL.md          # Required. YAML frontmatter + markdown.
  references/       # Optional. Detailed docs for agent context.
```

Valid YAML frontmatter keys: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`, `disable-model-invocation`, `user-invocable`.
