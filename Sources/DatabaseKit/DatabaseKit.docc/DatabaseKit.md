# ``DatabaseKit``

A protocol-based SwiftData layer shared by an app and its extensions, ready for CloudKit and safe to
open at launch.

## Overview

DatabaseKit wraps SwiftData behind a few small protocols so that features depend on `Sendable`
value types and a ``Repository``, never on a `ModelContext` or a `@Model` object.

- **One configuration** — a ``DatabaseConfiguration`` built the same way in the app and in every
  extension opens the same file.
- **Value types across the boundary** — a ``DatabaseEntity`` maps itself to a `Sendable`
  ``DatabaseEntity/Model``; managed objects never leave ``DatabaseActor``.
- **CloudKit-ready** — upserts go through your own identifier, because CloudKit forbids
  `@Attribute(.unique)`, and mirroring can be switched on and off at runtime with
  ``Database/setCloudKitEnabled(_:)``.
- **Never traps at launch** — ``DatabaseDefault/makeOrEphemeral(configuration:logger:onFailure:)``
  degrades to an in-memory store and reports it through ``Database/isEphemeral``.
- **Testable** — swap ``RepositoryDefault`` for `RepositoryMock` from `DatabaseKitTesting`.

```
Repository<Model>                ← features depend on this
 ├─ RepositoryDefault<Entity>    ← resolves the actor on every call
 └─ RepositoryMock<Model>        ← DatabaseKitTesting
Database
 └─ DatabaseDefault              ← owns the replaceable ModelContainer
     └─ DatabaseActor            ← the only place a ModelContext is touched
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ExampleUsage>
- <doc:SchemaVersioning>

### Opening a Store

- ``Database``
- ``DatabaseDefault``
- ``DatabaseConfiguration``
- ``StoreLocation``
- ``CloudKitSync``
- ``IncompatibleStorePolicy``

### Describing Your Models

- ``DatabaseSchema``
- ``DatabaseEntity``

### Reading and Writing

- ``Repository``
- ``RepositoryDefault``
- ``DatabaseChangeSet``
- ``DatabaseActor``

### Diagnostics

- ``DatabaseLogger``
- ``DatabaseLoggerDefault``
- ``DatabaseLogLevel``
- ``DatabaseError``
