# Verified Windows GUI package pairing

This fork's Windows workflow requires a successful Control Panel build at the
committed `src_assets/common/sunshine-control-panel` gitlink. It does not download
an unrelated latest GUI release when the paired build is unavailable.

Build the Panel commit first with its `build.yml` workflow and `create_release=false`.
The repository comes from the Panel URL in `.gitmodules`. Supply `gui_run_id`
when dispatching `main.yml`, or let `scripts/fetch-paired-gui.ps1` discover a
successful matching run. The run must contain an unexpired
`sunshine-gui-windows-x64` artifact with its ZIP and `gui-build.json` manifest.
The script checks repository, commit, run ID and ZIP SHA-256 before extraction.
It keeps the GUI executable and native plugin together and writes
`paired-build.json`, which is included in the installer and portable package.

This establishes provenance from the selected Actions producer; a manifest and
ZIP from the same producer do not independently prove that producer is benign.

For local paired staging, run `scripts/fetch-paired-gui.ps1 -Destination <fresh-path>`
from the Sunshine checkout. Omit `RunId` to discover a matching build, or pass
`-RunId <id>` to validate a specific build. Configure with `FETCH_GUI=OFF` and
`GUI_DIR=<fresh-path>` to use the verified bundle. The lower-level CMake default
still supports upstream release downloads for other build paths; this fork's
Windows workflow explicitly disables them. GitHub artifact access requires
an authenticated `gh` session or an appropriate `GH_TOKEN`.
