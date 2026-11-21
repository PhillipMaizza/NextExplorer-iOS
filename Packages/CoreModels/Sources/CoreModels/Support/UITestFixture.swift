#if DEBUG
    import Foundation

    /// Names the UI test mock world serves, read by the mock app and by the UI tests alike so a
    /// rename touches one place.
    public enum UITestFixture {
        /// Every folder in the browse tree. Root names never contain one another, since the UI tests
        /// find rows by a label that contains the name.
        public enum Folder: String, CaseIterable, Sendable {
            case documents = "Documents"
            case photos = "Photos"
            case media = "Media"
            case projects = "Projects"
            /// The signed in account can read and download here, and nothing else.
            case teamLibrary = "Team Library"
            case invoices = "Invoices"
            case invoices2025 = "2025"
            case invoices2026 = "2026"
            /// Enough photos to scroll well past one screen.
            case cameraRoll = "Camera Roll"
            case photos2024 = "2024"
            /// Nothing in it.
            case drafts = "Drafts"
            case website = "Website"
            /// The first of four folders nested one inside the next.
            case clients = "Clients"
            case acme = "Acme"
            case launch = "Launch"
            case kickoff = "Kickoff"

            /// The folder it sits in; nil at the root.
            public var parent: Folder? {
                switch self {
                case .documents, .photos, .media, .projects, .teamLibrary: nil
                case .invoices: .documents
                case .invoices2025, .invoices2026: .invoices
                case .cameraRoll, .photos2024: .photos
                case .drafts, .website, .clients: .projects
                case .acme: .clients
                case .launch: .acme
                case .kickoff: .launch
                }
            }

            public var name: String {
                rawValue
            }

            /// Its path from the root, as the server names it.
            public var path: String {
                parent.map { "\($0.path)/\(name)" } ?? name
            }

            /// The four nested folders, outermost first.
            public static let nestedChain: [Folder] = [.clients, .acme, .launch, .kickoff]
        }

        /// Every named file in the browse tree.
        public enum File: String, CaseIterable, Sendable {
            case notes = "notes.txt"
            case vacation = "vacation.jpg"
            case welcome = "Welcome.pdf"
            /// Found by any search, as if its contents held the query.
            case quarterlyReport = "Quarterly Report.txt"
            case meetingNotes = "Meeting Notes.md"
            /// An image among the search hits, so a filter chip narrows them.
            case beach = "Beach.jpg"
            /// In Projects, so a search inside Documents misses it and one from the root finds it.
            case archiveNotes = "Archive Notes.txt"
            case proposal = "Proposal.docx"
            case budget = "Budget 2026.xlsx"
            case roadmap = "Roadmap.pptx"
            case contract = "Contract signed by both parties after the second review round.pdf"
            case resume = "Résumé Zoë Müller.pdf"
            case teamSheet = "Team Sheet.gsheet"
            case logo = "logo.svg"
            /// Zero bytes.
            case empty = "empty.txt"
            /// A kind nothing on the device opens, with a date the server could not read.
            case export = "export.bin"
            case sunset = "sunset.png"
            case portrait = "portrait.dng"
            case birthday = "birthday.mov"
            case beachDay = "beach day.jpg"
            case snow = "snow.heic"
            case podcast = "Podcast Episode 12.m4a"
            case song = "Song.mp3"
            /// A video no native player opens.
            case concert = "Concert.mkv"
            case trailer = "Trailer.mp4"
            case siteBackup = "site backup.zip"
            case tools = "tools.tar.gz"
            case index = "index.html"
            case styles = "styles.css"
            case script = "app.js"
            case config = "config.json"
            case readme = "README.md"
            /// The file at the end of the nested chain.
            case agenda = "Agenda.pdf"
            case handbook = "Handbook.pdf"
            case brandGuide = "Brand Guide.pdf"

            public var name: String {
                rawValue
            }

            /// The name without its extension, a query that finds it.
            public var stem: String {
                (rawValue as NSString).deletingPathExtension
            }

            /// The files the mocked search finds whatever was typed.
            public static let searchFixtures: Set<File> = [.quarterlyReport, .meetingNotes, .beach, .archiveNotes]
        }

        /// Files generated in bulk, named by number.
        public enum Series {
            public static let cameraRollCount = 120
            public static let invoiceMonths2025 = 1 ... 12
            public static let invoiceMonths2026 = 1 ... 3

            public static func cameraRollPhoto(_ number: Int) -> String {
                "IMG_\(1000 + number).HEIC"
            }

            public static var lastCameraRollPhoto: String {
                cameraRollPhoto(cameraRollCount)
            }

            public static func invoice(_ year: Folder, month: Int) -> String {
                "Invoice \(year.name)-\(String(format: "%02d", month)).pdf"
            }
        }

        /// Labels the seeded favorites carry in place of their folder names.
        public enum FavoriteLabel: String, Sendable {
            case invoices = "Bills"
            case teamLibrary = "Handbooks"
        }

        /// Icons the seeded favorites use, in the server's `variant:Name` form.
        public enum FavoriteIcon: String, Sendable {
            case star = "outline:StarIcon"
            case folder = "outline:FolderIcon"
            case creditCard = "outline:CreditCardIcon"
            case globe = "outline:GlobeAltIcon"
            case bookmark = "outline:BookmarkIcon"
            case musicalNote = "outline:MusicalNoteIcon"
        }

        /// Colours the seeded favorites use, from the server's palette.
        public enum FavoriteColor: String, Sendable {
            case red = "#ff5e5a"
            case amber = "#ffb000"
            case blue = "#009cff"
            case purple = "#d873fb"
        }

        /// The servers the mocked sign in knows.
        public enum Host: String, Sendable {
            case primary = "nextexplorer.example.com"
            /// A second server, for adding another account.
            case other = "other.example.com"
        }

        public enum SignedInAccount: String, Sendable {
            case id = "uitest-user"
            case username = "phillip"
            case email = "phillip@example.com"
        }

        /// What the mocked sign in, two factor and token routes accept or refuse.
        public enum Credential: String, Sendable {
            case password = "hunter2"
            case wrongPassword = "not-the-password"
            case validCode = "123456"
            case wrongCode = "000000"
            case recoveryCode = "AAAAA-BBBBB"
            case twoFactorSecret = "JBSWY3DPEHPK3PXP"
            /// Signing in as this name answers "the password is right, now send a code".
            case secondFactorUser = "phillip.2fa"
            /// Signing in as this name is refused as wrong credentials.
            case rejectedUser = "phillip.rejected"
        }

        /// The people an admin manages, beside the signed in account.
        public enum ManagedUser: String, CaseIterable, Sendable {
            case jamie
            case sam
            /// Locked out after too many wrong passwords.
            case riley
            /// A second admin with two factor on.
            case morgan

            public var username: String {
                rawValue
            }

            public var id: String {
                "user-\(rawValue)"
            }

            public var email: String {
                "\(rawValue)@example.com"
            }

            public var displayName: String {
                switch self {
                case .jamie: "Jamie Rivera"
                case .sam: "Sam Okafor"
                case .riley: "Riley Chen"
                case .morgan: "Morgan Diaz"
                }
            }
        }

        /// The person a test adds through the new user form.
        public enum NewUser: String, Sendable {
            case casey

            public var email: String {
                "\(rawValue)@example.com"
            }
        }

        /// How a managed person signs in, as the server names the method.
        public enum SignInMethod: String, Sendable {
            case password = "local_password"
            case oidc
        }

        /// The single sign on provider a managed person uses.
        public enum IdentityProvider: String, Sendable {
            case authentik = "Authentik"
            case google = "Google"
        }

        /// A folder an access rule covers, with what it allows.
        public enum AccessRulePath: String, CaseIterable, Sendable {
            case reports = "Documents/Reports"
            case teamLibrary = "Team Library"
            case privateFolder = "Private"

            public var id: String {
                "rule-\(self)"
            }

            public var permission: AccessRule.Permission {
                switch self {
                case .reports, .teamLibrary: .readOnly
                case .privateFolder: .hidden
                }
            }

            /// Whether it covers the folders inside too.
            public var isRecursive: Bool {
                self != .privateFolder
            }
        }

        /// A storage volume an admin hands to a person.
        public enum ManagedVolume: String, CaseIterable, Sendable {
            case projects = "Projects"
            case archive = "Archive"

            public var path: String {
                "/srv/volumes/\(rawValue.lowercased())"
            }
        }

        /// The activity log's seeded lines, newest first, as the server names their actions.
        public enum ActivityAction: String, CaseIterable, Sendable {
            case signIn = "sign-in"
            case fileDelete = "file.delete"
            case shareCreate = "share.create"
            case accountToken = "account.token"
            case adminUser = "admin.user"
            case fileUpload = "file.upload"
        }

        /// Files with a version history, as the admin's versioned files list shows them.
        public enum VersionedFile: String, CaseIterable, Sendable {
            case notes
            case budget
            case logo
            /// Deleted, so only its history is left.
            case roadmap

            public var file: File {
                switch self {
                case .notes: .notes
                case .budget: .budget
                case .logo: .logo
                case .roadmap: .roadmap
                }
            }

            public var versionCount: Int {
                switch self {
                case .notes: 6
                case .budget: 3
                case .logo: 2
                case .roadmap: 4
                }
            }
        }

        /// Labels on the seeded file versions.
        public enum VersionLabel: String, Sendable {
            case approved = "Approved"
        }

        /// What the seeded trash holds besides what a test deletes.
        public enum TrashEntry: String, CaseIterable, Sendable {
            /// Goes for good today.
            case oldBudget = "Old Budget.xlsx"
            /// A folder with files inside to browse before restoring.
            case oldPhotos = "Old Photos"
            /// Deleted by someone else, with share links that a restore can bring back.
            case sharedPlan = "Shared Plan.pdf"
            /// Deleted through a share link.
            case dropped = "Dropped Upload.txt"
            /// On a volume that is not mounted.
            case offlineArchive = "Archive 2019.zip"

            public var name: String {
                rawValue
            }

            /// The other person who deleted `sharedPlan`.
            public static let otherPerson = ManagedUser.jamie
            /// What `dropped` reads.
            public static let droppedText = "Uploaded through the link before it was taken down."
            public static let offlineVolume = ManagedVolume.archive
        }

        /// The files inside the trashed `oldPhotos` folder.
        public enum TrashedPhotosEntry: String, CaseIterable, Sendable {
            case first = "IMG_0001.HEIC"
            case second = "IMG_0002.HEIC"
            /// Text to read in the trash before restoring.
            case shotList = "shot list.txt"

            public var name: String {
                rawValue
            }

            public static let shotListText = "Beach day: sunrise, pier, dunes."
        }

        /// A folder name the mocked server refuses to create.
        public static let failingFolderName = "__uitest_fail__"
    }
#endif
