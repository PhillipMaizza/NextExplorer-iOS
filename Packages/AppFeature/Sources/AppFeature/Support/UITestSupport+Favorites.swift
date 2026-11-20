#if DEBUG
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Foundation
    import NetworkClient

    extension UITestSupport {
        /// The signed in account's favorites, kept in memory for one app launch so adding, removing,
        /// editing and reordering show in the next listing, as on the server. The seed mixes a plain
        /// folder, labels, icons and colours, a nested path and a read only folder.
        static func installFavoriteMocks(into client: inout FilesClient, now: Date) {
            typealias Fixture = UITestFixture
            let seed: [(
                folder: Fixture.Folder,
                label: Fixture.FavoriteLabel?,
                icon: Fixture.FavoriteIcon,
                color: Fixture.FavoriteColor?
            )] = [
                (.documents, nil, .folder, nil),
                (.invoices, .invoices, .creditCard, .red),
                (.website, nil, .globe, .blue),
                (.teamLibrary, .teamLibrary, .bookmark, .purple),
                (.media, nil, .musicalNote, .amber),
            ]
            let favorites = LockIsolated(seed.enumerated().map { index, entry in
                Favorite(
                    id: "fav-\(index)",
                    path: entry.folder.path,
                    label: entry.label?.rawValue,
                    icon: entry.icon.rawValue,
                    color: entry.color?.rawValue,
                    position: index,
                    createdAt: now,
                    updatedAt: now
                )
            })
            let nextID = LockIsolated(seed.count)

            client.favorites = { _ in favorites.value }
            client.addFavorite = { _, path in
                favorites.withValue { list in
                    if let existing = list.first(where: { $0.path == path }) {
                        return existing
                    }
                    let id = nextID.withValue { next in
                        defer { next += 1 }
                        return "fav-\(next)"
                    }
                    let added = Favorite(
                        id: id,
                        path: path,
                        label: nil,
                        icon: UITestFixture.FavoriteIcon.star.rawValue,
                        color: nil,
                        position: list.count,
                        createdAt: now,
                        updatedAt: now
                    )
                    list.append(added)
                    return added
                }
            }
            client.removeFavorite = { _, path in
                favorites.withValue { $0.removeAll { $0.path == path } }
            }
            client.updateFavorite = { _, id, label, icon, color in
                try favorites.withValue { list in
                    guard let index = list.firstIndex(where: { $0.id == id }) else {
                        throw FilesClientError.server(statusCode: HTTPStatus.notFound.rawValue)
                    }
                    let old = list[index]
                    list[index] = Favorite(
                        id: id,
                        path: old.path,
                        label: label.flatMap { $0.isEmpty ? nil : $0 },
                        icon: icon.isEmpty ? UITestFixture.FavoriteIcon.star.rawValue : icon,
                        color: color.flatMap { $0.isEmpty ? nil : $0 },
                        position: old.position,
                        createdAt: old.createdAt,
                        updatedAt: now
                    )
                    return list[index]
                }
            }
            client.reorderFavorites = { _, orderedIDs in
                favorites.withValue { list in
                    list = orderedIDs.enumerated().compactMap { position, id in
                        list.first { $0.id == id }.map { $0.moved(to: position) }
                    }
                    return list
                }
            }
        }
    }

    private extension Favorite {
        func moved(to position: Int) -> Favorite {
            Favorite(
                id: id,
                path: path,
                label: label,
                icon: icon,
                color: color,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }
#endif
