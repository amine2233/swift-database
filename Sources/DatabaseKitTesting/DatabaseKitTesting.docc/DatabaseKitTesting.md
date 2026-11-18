# ``DatabaseKitTesting``

Test doubles for code that depends on DatabaseKit.

## Overview

Features built on DatabaseKit depend on `Repository`, not on SwiftData. ``RepositoryMock`` is an
in-memory `Repository` that behaves like the real one — upserts by id, `update` throws
`DatabaseError.notFound` for a missing row — records every call it receives and fails on demand.

Link `DatabaseKitTesting` from test targets only:

```swift
.testTarget(
    name: "BookmarksKitTests",
    dependencies: [
        "BookmarksKit",
        .product(name: "DatabaseKitTesting", package: "swift-database"),
    ]
)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ExampleUsage>
- <doc:TestingSchemaVersions>

### Test Doubles

- ``RepositoryMock``
