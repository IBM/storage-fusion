# IBM Fusion Recipe Builder — Bob Skill

This directory contains a [Bob](https://www.ibm.com/docs/en/bob) skill that helps customers create IBM Fusion Data Protection Recipe custom resources for their OpenShift applications.

## What is a Fusion Recipe?

A [Fusion Recipe](https://www.ibm.com/docs/en/fusion-software/2.13.x?topic=workflows-creating-recipe) is a Kubernetes custom resource that defines application-consistent backup and restore workflows for IBM Fusion Data Protection. Recipes orchestrate the correct sequence of:

- **Groups** — which PersistentVolumes and Kubernetes resources to capture
- **Hooks** — quiesce/resume commands, readiness checks, and post-restore operations
- **Workflows** — the ordered sequence of groups and hooks for backup and for restore

## Using the skill with Bob

### Install the skill

Copy (or symlink) this directory into your Bob skills location:

```bash
# Project-level (recommended — version-controlled with this repo)
mkdir -p <your-project>/.bob/skills
cp -r storage-fusion/backup-restore/recipes/Bob <your-project>/.bob/skills/create-fusion-recipe

# Or global (available in all your projects)
mkdir -p ~/.bob/skills
cp -r storage-fusion/backup-restore/recipes/Bob ~/.bob/skills/create-fusion-recipe
```

### Invoke the skill

Open Bob and ask it to create a recipe for your application:

```
Help me create a Fusion Recipe for my PostgreSQL application
```

```
Create a Fusion backup recipe for my custom Node.js app running in the myapp namespace
```

Bob will automatically activate the `create-fusion-recipe` skill, ask you a structured set of questions about your application, and generate a complete, valid Recipe YAML.

## Directory structure

```
Bob/
├── README.md                        ← This file
├── SKILL.md                         ← Bob skill definition (entry point)
├── recipe-crd-reference.md          ← Authoritative field reference from the CRD
└── question-guide.md                ← Known quiesce/resume patterns for common apps
```

Master recipes are located in sibling directories under `storage-fusion/backup-restore/recipes/` (e.g. `PostgreSQL/`, `MySQL/`, `MongoDB/`, `Redis/`, `WordPress/`, `Elasticsearch/`, etc.).

## Supported applications (built-in knowledge)

The skill has pre-built quiesce/resume knowledge for the following applications. When you name one of these, Bob will suggest the correct hook commands automatically:

| Application | Quiesce method |
|---|---|
| PostgreSQL | `CHECKPOINT` |
| MySQL / MariaDB | `FLUSH TABLES WITH READ LOCK` |
| MongoDB | `db.fsyncLock()` / `db.fsyncUnlock()` |
| Redis | `BGSAVE` (background save) |
| Elasticsearch | Index write-block + `_flush` |
| Db2 | Instance maintenance mode |
| Cassandra | `nodetool flush` |
| CockroachDB | Consistent snapshot (no strict quiesce required) |
| Any app without a quiesce command | Scale-to-zero pattern |

For custom or unlisted applications, Bob will ask you for the quiesce command and container details.

## Adding more applications

To add quiesce/resume knowledge for a new application, edit [`question-guide.md`](question-guide.md) and add a new section following the existing pattern. Include:

- The quiesce command and which container it runs in
- Whether `singlePodOnly: true` is needed (primary/leader selection)
- The resume command or whether `inverseOp` handles it automatically
- Any post-restore steps
- A reference to an example recipe if one exists
