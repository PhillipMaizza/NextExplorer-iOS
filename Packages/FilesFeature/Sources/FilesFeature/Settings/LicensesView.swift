import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconSmall
    static let detailPadding: CGFloat = .space16
    static let detailSpacing: CGFloat = .space8
}

/// One open-source dependency this app ships, with its real license text embedded verbatim
/// (fetched from each project's own `LICENSE`/`OFL.txt`, not paraphrased) — not just a name
/// and a guessed license type.
struct OpenSourceLicense: Identifiable {
    let name: String
    let licenseName: String
    let text: String

    var id: String {
        name
    }
}

extension OpenSourceLicense {
    /// The MIT body text is identical verbatim across every MIT-licensed dependency below
    /// (confirmed against each project's own `LICENSE` file) — only the copyright line
    /// differs, so it's kept as one shared constant rather than duplicated five times.
    private static func mitText(copyright: String) -> String {
        """
        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }

    static let all: [OpenSourceLicense] = [
        OpenSourceLicense(
            name: "swift-composable-architecture",
            licenseName: "MIT",
            text: mitText(copyright: "Copyright (c) 2020 Point-Free, Inc.")
        ),
        OpenSourceLicense(
            name: "swift-dependencies",
            licenseName: "MIT",
            text: mitText(copyright: "Copyright (c) 2022 Point-Free, Inc.")
        ),
        OpenSourceLicense(
            name: "Runestone",
            licenseName: "MIT",
            text: mitText(copyright: "Copyright (c) 2021 Simon Støvring")
        ),
        OpenSourceLicense(
            name: "TreeSitterLanguages",
            licenseName: "MIT",
            text: mitText(copyright: "Copyright (c) 2021 Simon Støvring")
        ),
        OpenSourceLicense(
            name: "tree-sitter",
            licenseName: "MIT",
            text: mitText(copyright: "Copyright (c) 2018 Max Brunsfeld")
        ),
        OpenSourceLicense(
            name: "Figtree",
            licenseName: "OFL-1.1",
            text: """
            Copyright 2022 The Figtree Project Authors (https://github.com/erikdkennedy/figtree)

            This Font Software is licensed under the SIL Open Font License, Version 1.1.
            This license is copied below, and is also available with a FAQ at:
            http://scripts.sil.org/OFL

            -----------------------------------------------------------
            SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
            -----------------------------------------------------------

            PREAMBLE
            The goals of the Open Font License (OFL) are to stimulate worldwide
            development of collaborative font projects, to support the font creation
            efforts of academic and linguistic communities, and to provide a free and
            open framework in which fonts may be shared and improved in partnership
            with others.

            The OFL allows the licensed fonts to be used, studied, modified and
            redistributed freely as long as they are not sold by themselves. The
            fonts, including any derivative works, can be bundled, embedded,
            redistributed and/or sold with any software provided that any reserved
            names are not used by derivative works. The fonts and derivatives,
            however, cannot be released under any other type of license. The
            requirement for fonts to remain under this license does not apply
            to any document created using the fonts or their derivatives.

            DEFINITIONS
            "Font Software" refers to the set of files released by the Copyright
            Holder(s) under this license and clearly marked as such. This may
            include source files, build scripts and documentation.

            "Reserved Font Name" refers to any names specified as such after the
            copyright statement(s).

            "Original Version" refers to the collection of Font Software components as
            distributed by the Copyright Holder(s).

            "Modified Version" refers to any derivative made by adding to, deleting,
            or substituting -- in part or in whole -- any of the components of the
            Original Version, by changing formats or by porting the Font Software to a
            new environment.

            "Author" refers to any designer, engineer, programmer, technical
            writer or other person who contributed to the Font Software.

            PERMISSION & CONDITIONS
            Permission is hereby granted, free of charge, to any person obtaining
            a copy of the Font Software, to use, study, copy, merge, embed, modify,
            redistribute, and sell modified and unmodified copies of the Font
            Software, subject to the following conditions:

            1) Neither the Font Software nor any of its individual components,
            in Original or Modified Versions, may be sold by itself.

            2) Original or Modified Versions of the Font Software may be bundled,
            redistributed and/or sold with any software, provided that each copy
            contains the above copyright notice and this license. These can be
            included either as stand-alone text files, human-readable headers or
            in the appropriate machine-readable metadata fields within text or
            binary files as long as those fields can be easily viewed by the user.

            3) No Modified Version of the Font Software may use the Reserved Font
            Name(s) unless explicit written permission is granted by the corresponding
            Copyright Holder. This restriction only applies to the primary font name as
            presented to the users.

            4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
            Software shall not be used to promote, endorse or advertise any
            Modified Version, except to acknowledge the contribution(s) of the
            Copyright Holder(s) and the Author(s) or with their explicit written
            permission.

            5) The Font Software, modified or unmodified, in part or in whole,
            must be distributed entirely under this license, and must not be
            distributed under any other license. The requirement for fonts to
            remain under this license does not apply to any document created
            using the Font Software.

            TERMINATION
            This license becomes null and void if any of the above conditions are
            not met.

            DISCLAIMER
            THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
            MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
            OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
            COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
            INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
            DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
            FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
            OTHER DEALINGS IN THE FONT SOFTWARE.
            """
        ),
    ]
}

struct LicensesView: View {
    var body: some View {
        List(OpenSourceLicense.all) { license in
            NavigationLink {
                LicenseDetailView(license: license)
            } label: {
                HStack {
                    Text(license.name).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer()
                    Text(license.licenseName).type(.body2(.regular), style: .secondary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle(L10n.Licenses.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseDetailView: View {
    let license: OpenSourceLicense

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.detailSpacing) {
                Text(license.name).type(.headline3, style: .primaryOnSurface)
                Text(license.licenseName).type(.body2(.regular), style: .secondary)
                Text(license.text)
                    .type(.body3(.regular), style: .secondary)
                    .textSelection(.enabled)
                    .padding(.top, Constants.detailSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Constants.detailPadding)
        }
        .backgroundGradient()
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}

#Preview("Detail") {
    NavigationStack {
        LicenseDetailView(license: OpenSourceLicense.all[0])
    }
}
