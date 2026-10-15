# Game library scan memory

The personal fork keeps local scan overrides and manual cover selection. AI title cleanup, AI cover matching, and their network requests have been removed.

`useApps.js` scans directories and Steam/Epic/GOG libraries, then applies `applyGameLibraryOverrides()` before displaying results. Confirming an entry calls `rememberGameLibraryApp()` so later scans retain the user's chosen name and cover. Covers supplied by a game platform or chosen manually still use the existing local upload path.

`gameLibraryCuratorAgent.js` retains the memory skill, resource keys, and review policy. Its registry has no built-in user-selectable enrichment skills. The generic runner and extension validation remain covered by `tests/gameLibraryCuratorAgent.test.js`.
