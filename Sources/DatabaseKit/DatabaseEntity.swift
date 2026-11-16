import Foundation
import SwiftData

/// A SwiftData model that crosses the store boundary as a value type.
///
/// `PersistentModel` instances are bound to the context that fetched them and are not `Sendable`, so
/// nothing outside ``DatabaseActor`` ever sees one: reads return ``Model``, writes take ``Model``.
///
/// ``idKeyPath`` names the stored property holding the model's identity. It has to be a property of
/// your own — CloudKit forbids `@Attribute(.unique)`, so the store cannot enforce it and ``DatabaseActor``
/// upserts by this key instead.
public protocol DatabaseEntity: PersistentModel {
    associatedtype Model: Identifiable & Sendable where Model.ID: Sendable & Codable

    static var idKeyPath: any KeyPath<Self, Model.ID> & Sendable { get }

    init(model: Model)

    func makeModel() -> Model

    /// Overwrites every stored property with `model`'s values.
    func update(with model: Model)
}

extension DatabaseEntity {
    static func predicate(id: Model.ID) -> Predicate<Self> {
        Predicate<Self> { entity in
            PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: entity, keyPath: idKeyPath),
                rhs: PredicateExpressions.build_Arg(id)
            )
        }
    }

    static func predicate(ids: [Model.ID]) -> Predicate<Self> {
        Predicate<Self> { entity in
            PredicateExpressions.build_contains(
                PredicateExpressions.build_Arg(ids),
                PredicateExpressions.build_KeyPath(root: entity, keyPath: idKeyPath)
            )
        }
    }
}
