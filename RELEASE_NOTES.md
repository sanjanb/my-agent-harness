# Release Notes — v1.1.0

> **Date:** 2026-08-11  
> **Tag / Version:** `v1.1.0`  
> **Focus:** Portable Setup, Security Safeguards, Permission Alignment, and 4-Tier Memory Integration.

---

## 🚀 Key Improvements & Highlights

### 1. Portable Setup CLI (`src/cli.ts` & `package.json`)
- **Auto-Directory Resolution**: Running `npm run setup` or `npx my-agent-harness` now intelligently detects the local working directory (`process.cwd()`) on any system, removing reliance on fixed git URLs or hardcoded path destinations.
- **Non-Admin Windows Junctions**: Fixed Windows symlink linking by leveraging Node's native `fs.symlinkSync(repoDir, installDir, 'junction')`, allowing non-administrator execution on Windows.
- **Build-Before-Setup Execution**: Updated `package.json` setup script to `"setup": "npm run build && node dist/cli.js"` ensuring `tsc` compilation happens seamlessly before invoking the installer CLI.

### 2. Secret Key Protection & Safety
- **Git-Safe `.env` Storage**: Updated `promptForApiKeys()` in `src/cli.ts`. API keys inputted during interactive setup are now securely appended to the local gitignored `.env` file (`CONTEXT7_API_KEY=...`) rather than overwriting tracked `opencode.jsonc` files.

### 3. Complete 4-Tier Memory Architecture
- **Vector DB Plugin (`opencode-mem`) Integration**: Synchronized default configuration templates (`config/opencode.jsonc.template`) to include `"opencode-mem"` and `"opencode-warden"`.
- **Local Embeddings & Web Dashboard**: Built-in support for ONNX embeddings (`Xenova/nomic-embed-text-v1`), 30-day retention cleanup, vector deduplication (0.90 similarity), and local web UI on `http://127.0.0.1:4747`.
- **Inter-Session & Agent Conventions**: Integrated `AutoDream` inter-session consolidation (`scripts/auto-dream.sh`) and agent-writable shared conventions (`.opencode/conventions.jsonl`).

### 4. Unblocked Tool Permissions (`opencode.jsonc`)
- **Permission Alignment**: Changed default tool permissions in `opencode.jsonc` and `config/opencode.jsonc.template` from global `"deny"` to `"ask"` (for remote MCPs like Context7, Exa, and gh_grep) and `"allow"` (for `worktree_*`), enabling orchestrators and agents to use worktree isolation and library docs out of the box.

---

## 🛠 Migration & Quick Upgrade Instructions

If you have an existing installation, pull the latest changes and re-run setup:

```bash
git pull origin main
npm install
npm run setup
```

---

## 📄 Full File Changelog

- `package.json`: Updated version to `1.1.0`, enhanced setup script with pre-build step.
- `src/cli.ts`: Cross-platform link fixes, `.env` key storage, auto `REPO_DIR` detection.
- `opencode.jsonc`: Updated permission defaults (`worktree_*` to `allow`, MCPs to `ask`).
- `config/opencode.jsonc.template`: Synchronized plugins and permissions with active config.
- `README.md`: Updated installation documentation, memory section, and architecture breakdown.
- `RELEASE_NOTES.md`: Created release notes for v1.1.0.
