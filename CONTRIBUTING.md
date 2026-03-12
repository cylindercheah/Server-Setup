# Contributing to Server-Setup

Thank you for your interest in contributing! This guide explains how to add files and folders to this repository.

## Yes, you can upload a folder here!

You can contribute scripts, configuration files, documentation, or any other server-related material by adding it to this repository.

## How to Upload a Folder

### Option 1: GitHub Web Interface (easiest)

1. **Fork** this repository (click **Fork** at the top-right of the page).
2. In your fork, navigate to the location where you want to add your folder.
3. Click **Add file → Upload files**.
4. Drag and drop your entire folder (or individual files) into the upload area.
   - GitHub's web uploader supports dragging a local folder directly from your file explorer.
5. Add a short commit message describing what you are adding.
6. Click **Commit changes**.
7. Open a **Pull Request** from your fork back to this repository.

> **Note:** GitHub's web uploader supports dragging a folder from your desktop — it will preserve the folder structure automatically.

### Option 2: Git command line

```bash
# 1. Clone your fork
git clone https://github.com/<your-username>/Server-Setup.git
cd Server-Setup

# 2. Copy your folder into the repository
cp -r /path/to/your/folder uploads/

# 3. Stage, commit, and push
git add uploads/
git commit -m "Add <folder-name>: brief description"
git push origin main

# 4. Open a Pull Request on GitHub
```

### Option 3: GitHub CLI

```bash
gh repo fork cylindercheah/Server-Setup --clone
cd Server-Setup
cp -r /path/to/your/folder uploads/
git add uploads/ && git commit -m "Add <folder-name>"
git push
gh pr create --fill
```

## Where to Put Your Folder

| What you are adding | Suggested location |
|---|---|
| Shell scripts / automation | `scripts/` or `uploads/<your-folder>/` |
| Documentation / how-tos | `docs/` or `uploads/<your-folder>/` |
| Configuration files | `uploads/<your-folder>/` |
| Anything else | `uploads/<your-folder>/` |

If your contribution fits neatly into an existing directory (`scripts/`, `docs/`), feel free to place it there directly. Otherwise, drop it in `uploads/` so it is easy to find.

## Guidelines

- Include a short `README.md` inside your folder describing what it contains and how to use it.
- Keep file names lowercase with hyphens (e.g., `my-setup-script.sh`).
- Do not commit passwords, private keys, or other secrets.
- Scripts should be POSIX-compatible shell or clearly document their requirements.

## Need Help?

Open an [issue](../../issues) and ask — the maintainers are happy to guide you through the process.
