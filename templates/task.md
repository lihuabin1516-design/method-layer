# Task Artifact Draft

> JSON output must validate against `schemas/task.schema.json`.

## Identity

- protocolVersion: `0.1`
- artifactType: `task`
- taskId:
- createdAt:
- status:
- riskMode: `simple | standard | deep`（v0.1 advisory-only）

## Objective

<one measurable objective>

## Authorization

### Allowed paths

- <path>

### Forbidden actions

- <action>

### Conditional actions

- <action and exact approval condition>

## Baseline

- Workspace:
- Project path:
- Repo root:
- Branch:
- HEAD: `unborn | <40-character commit SHA>`
- Status state: `clean | dirty | untracked | mixed`
- Status summary:
- Relevant rules:

## Acceptance

- <assertion>

## Required Evidence

- <evidence item>

## Stop Conditions

- <condition>

## Lineage

- Spec:
- Ticket:
- Review:
- PR:
- Parent tasks:
- External references:
