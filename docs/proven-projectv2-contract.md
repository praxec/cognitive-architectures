# Proven ProjectV2 GraphQL contract (Project 3 = "MVP Gremlin List")

Verified live 2026-07-31 via `gh api graphql` (token: matt-cochran). These IDs are the operator's
board; scripts resolve them at runtime via `resolve-project` — this file is the reference for
implementers and the fixture for tests.

- **project** owner=`outboundlabs` number=`3` → **projectId** `PVT_kwDOB8Crxs4BVRQh`
- **repo** default `outboundlabs/autopilot-beta`

## Single-select fields (fieldId → {optionName: optionId})

| Field | fieldId | options |
|---|---|---|
| Status | `PVTSSF_lADOB8Crxs4BVRQhzhQuNTA` | Found `f971fb55` · Hunting `5ef0dc97` · Killed `856cdede` · Buried `98236657` |
| Priority | `PVTSSF_lADOB8Crxs4BVRQhzhQuNnE` | P0 `79628723` · P1 `0a877460` · P2 `da944a9c` |
| Size | `PVTSSF_lADOB8Crxs4BVRQhzhQuNnI` | XS `3fd50a4c` · S `203d27bd` · M `3da4ca48` · L `8d0cdae9` · XL `71251445` |

## Query: resolve-project (fields + option IDs)

```graphql
query($o:String!,$n:Int!){ organization(login:$o){ projectV2(number:$n){
  id
  fields(first:30){ nodes{ __typename
    ... on ProjectV2SingleSelectField{ id name options{ id name } } } } } } }
```
`gh api graphql -f query='…' -f o=outboundlabs -F n=3`  (`-F` = typed Int for `$n`).

## Query: project-enumerate (items + status + linked PRs)

```graphql
query($o:String!,$n:Int!){ organization(login:$o){ projectV2(number:$n){
  items(first:50){ nodes{
    id
    content{ __typename ... on Issue{
      number title state url createdAt
      repository{ nameWithOwner }
      closedByPullRequestsReferences(first:5){ nodes{ number state } } } }
    fieldValues(first:20){ nodes{ __typename
      ... on ProjectV2ItemFieldSingleSelectValue{ name field{ ... on ProjectV2FieldCommon{ name } } } } } } } } } }
```

## Mutations (Projects-v2 write path)

```graphql
# add an existing issue (by node id) to the project → returns item id
mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p, contentId:$c}){ item{ id } } }

# set a single-select field on a project item
mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){
  updateProjectV2ItemFieldValue(input:{projectId:$p, itemId:$i, fieldId:$f, value:{singleSelectOptionId:$o}}){ projectV2Item{ id } } }
```

- **Issue node id** (for `addProjectV2ItemById.contentId`): `gh api graphql` on the issue, or
  `gh issue view N --json id -q .id` (returns the GraphQL node id).
- **Create issue:** `gh issue create --repo O/N --title … --body … --label …` (returns URL; parse number).
- **Dedup search:** `search(query:"repo:O/N in:body \"qa-fingerprint: <hash>\"", type:ISSUE, first:1)`.
- **Close + comment:** `gh issue close N --repo O/N --comment "…"` then set Status=Killed via the
  single-select mutation.

## Current backlog (12 items, all outboundlabs/autopilot-beta, all issue-state OPEN)

Statuses as of verification: #922 Killed · #919 Hunting · #916 Killed · #917 Hunting · #918 Killed ·
#923 Found · #924 Killed · #925 Found · #926 Found · #927 Hunting · #928 Found · #931 Killed.
Note: several are Status=Killed but issue-OPEN → cleanup-pass candidates (verify-fixed → close on board).
