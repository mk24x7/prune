# Security Policy

## Supported versions

Only the latest release of Prune (app and CLI) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub private vulnerability reporting:
open the repository's Security tab and choose "Report a vulnerability"
(https://github.com/mk24x7/prune/security/advisories/new).

Do not open a public issue for security problems.

Include the Prune version, macOS version, whether you used the app or the CLI, and the smallest directory layout or steps that reproduce the problem.

You should receive an acknowledgement within 7 days. Once a fix is released the advisory will be published and you will be credited unless you ask otherwise.

## Scope

Prune deletes or moves files to the Trash, so the most serious class of bug is removing something the user did not intend. In scope:

- Any way Prune could delete or trash a file or directory outside its declared targets in `Definitions/artifacts.json`.
- Path traversal, for example through crafted directory names, environment variable overrides or `..` segments.
- Following symbolic links during scanning, verification or deletion.
- Race conditions between scan and deletion that allow a different path to be removed than the one shown.

Out of scope: deleting an artifact type the user explicitly selected, and disk usage figures that are inaccurate but cause no deletion.
