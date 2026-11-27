# 0028. Share access as choice rows, with Custom for a folder's own switches

Status: Accepted

## Context
The Mac Create Share Link and Edit Share sheets offered Read Only / Read & Write. The server and web also keep
`allowDownload`, `allowDelete`, `allowCreateFolder`, `allowCreateFile`, `allowUpload`, `versionsVisible` and
`versionsDownload` per share. Editing a share from the Mac could not show or set them.

## Decision
- "People can" lists View only (`readonly`, no download), Can download (`readonly`), Can edit (`readwrite`,
  every allow flag on) and, for a folder, Custom (`readwrite` plus one switch per allow flag).
- A share opens on the preset its flags match. A share that matches none opens on Custom, also for a file,
  so every web setting survives a save.
- Presets set only their own flags, so moving between them never loses the version settings.
- Show file versions and an indented Download versions sit with Password and Expires. A new link turns versions
  on for Specific users and off for Anyone, as the server does when the keys are left out. Download versions
  is never sent on while versions are hidden, as on the web.
- Create and Edit always send the full set of flags. The Shared inspector's permission popup uses the same
  presets, and lists Custom only for a share that already is Custom.
- `accessModeChanged` stays for the iPhone sheets: it picks the preset for the current flags without
  changing them.

Code: `SharePermissions` (server keys mapped to `canDownload`, `canDelete`, `showsVersions` and friends), `ShareAccessChoice`, `MacShareAccessField`, `MacChoiceRow`, `ShareAccessChoiceTests`,
`SharePermissionsTests`.
