#if os(macOS)
    import SwiftUI

    public struct MacTransferStatus: View {
        let fileName: String?
        let timeLeft: String?
        let fraction: Double?

        public init(fileName: String?, timeLeft: String?, fraction: Double?) {
            self.fileName = fileName
            self.timeLeft = timeLeft
            self.fraction = fraction
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                HStack(alignment: .firstTextBaseline, spacing: .space8) {
                    if let fileName {
                        Text(fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: .zero)
                    if let timeLeft {
                        Text(timeLeft)
                            .lineLimit(1)
                    }
                    if let fraction {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(Color.primaryDS)
                    }
                }
                .type(.body3(.regular))
                .foregroundStyle(Color.secondaryDS)
                MacProgressBar(value: fraction)
            }
        }
    }

    #Preview("Uploading") {
        MacTransferStatus(fileName: "brief-v2.pdf", timeLeft: "12s left", fraction: 0.45)
            .frame(width: 300)
            .padding(.space40)
            .background(Color.macChrome)
    }

    #Preview("Long name, no estimate yet") {
        MacTransferStatus(
            fileName: "quarterly-report-final-version-with-appendix.pdf",
            timeLeft: nil,
            fraction: 0.02
        )
        .frame(width: 300)
        .padding(.space40)
        .background(Color.macChrome)
    }

    #Preview("Preparing") {
        MacTransferStatus(fileName: nil, timeLeft: nil, fraction: nil)
            .frame(width: 300)
            .padding(.space40)
            .background(Color.macChrome)
    }
#endif
