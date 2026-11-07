# Xplore Constraints - What This LPAR Allows / Forbids

> IBM Z Xplore (z/OS 3.1), ID Z78651, HLQ Z78651.BUILD
> Status: This document is an archival reference. Wazi Deploy was available on this LPAR during the project window only and has since been removed from the system. The project is complete. This doc explains what was allowed on Xplore and what must be done differently on an enterprise LPAR.

---

## 1. What Xplore Is

- Xplore is a free, multi-tenant, educational LPAR for learning IBM Z.
- It is not a production LPAR, not a corporate dev LPAR, and not a sandbox you own.
- It has no internet access to `pypi.org` or to public package registries.
- Home space `/z/z78651` has a small quota. Fill it and builds fail with `ENOSPC`.
- Shell history fills quota fast. `HISTFILE` must be `/dev/null`.

---

## 2. What You Can Use

| Resource | Location | Notes |
|---|---|---|
| DBB Toolkit | `/usr/lpp/IBM/dbb/bin/groovyz` (2.0.2.7) | Official, use directly |
| zAppBuild | `/z/z78651/work/dbb-zappbuild/build.groovy` (3.14.0-BASE) | Cloned from IBM GitHub, runs in workspace |
| COBOL compiler | `IGY650.SIGYCOMP` (COBOL 6.5.0) via TASKLIB | Found via `LISTALC`, not `IGY.V6R4M0.SIGYCOMP` |
| Binder | `CEE.SCEELKED` | Found via `LISTCAT LEVEL(CEE)` |
| Wazi Deploy (during project window) | `/usr/lpp/IBM/gdp/` (3.0.0) | Provided by IBM on the LPAR during the project window. Now removed. Do not expect it to be present on a fresh Xplore ID. |
| Wazi dependencies (during project window) | `/usr/lpp/IBM/gdp/dependencies/` | Official dependencies only. Use `PYTHONPATH=/usr/lpp/IBM/gdp/dependencies:$PYTHONPATH` if needed. |
| Python | `/usr/lpp/IBM/cyp/v3r9/pyz` (Python 3.9.2) | Use `PYTHONHOME=/usr/lpp/IBM/cyp/v3r9/pyz` |
| Rocket Git | `/usr/lpp/Rocket/rsusr/ported/bin/` | Add to `PATH` for `git` on USS. Set `GIT_SSL_CAINFO=/usr/lpp/Rocket/rsusr/ported/bin/ca-bundle.crt` |
| Java | `/usr/lpp/java/J11.0_64` | `JAVA_HOME` for DBB |

---

## 3. What You Must NOT Do on Xplore

### 3.1 Do NOT install custom Python packages

- Do NOT `pip install` from `pypi.org` - there is no internet, and Xplore does not allow custom installs.
- Do NOT create `~/wheels/` and upload `.whl` files from your workstation.
- Do NOT extract wheels to `~/.local/lib/python3.9/site-packages/`.
- Do NOT set `PYTHONPATH=$HOME/.local/...` as a permanent fix.

**Why:** Xplore provides the toolchain in `/usr/lpp/`. Adding your own packages to `~/.local` conflicts with the managed environment, corrupts `.pyc` binaries when `_BPXK_AUTOCVT=ON` converts them as text, and violates the LPAR usage policy for a shared educational system.

**Correct pattern:** Use only what IBM provides in `/usr/lpp/`. If a dependency is missing, the correct action is to ask IBM Z Xplore support or to run that step on an enterprise LPAR where you have install rights, not to work around it with uploaded wheels.

### 3.2 Do NOT use emojis in YAML, JCL, or workflow echo lines

- Emojis (for example U+1F447) crash the `latin-1` / ISO8859-1 encoder used by Wazi Deploy.
- Copy-paste from a rendered page can insert `¦` (U+00A6) which appears as byte `0xa6` and breaks UTF-8 parsing.
- Use plain ASCII only in all files that Wazi Deploy or `chtag` will touch.

### 3.3 Do NOT commit secrets

- Never commit `zowe.config.user.json`, `zowe.schema.json`, `.vscode/settings.json`, `logs/*.log`, or passwords.
- Use GitHub Secrets (`ZOS_HOST`, `ZOS_USER`, `ZOS_PASSWORD`, `JFROG_URL`, `JFROG_USER`, `JFROG_TOKEN`, `SONAR_TOKEN`) and pass them via `env:` in workflows.
- Rotate the Xplore password immediately if a secret is ever pushed.

### 3.4 Do NOT commit on USS

- USS `/z/z78651/work/workspace/mainframe-modernization-platform` is a build workspace, not a dev workspace.
- All commits happen on Windows / GitHub. On USS, use `git fetch origin` + `git reset --hard origin/main`, never `git pull` or local commits.

### 3.5 Do NOT use special characters in workflow names

- Workflow `name:` values with `(`, `)`, `+`, `->` break GitHub `workflow_run` triggering.
- Use simple names only: `DBB Build`, `Package and Publish`, `Deploy`.

---

## 4. Wazi Deploy on Xplore - Time-Limited Access

- Wazi Deploy 3.0.0 was available in `/usr/lpp/IBM/gdp/` during this project.
- That access was time-limited and has now ended. Wazi-related software has been removed from this LPAR.
- The project was completed within that window. All Wazi logs, JFrog publish proofs, and `deployable.tar` checksums in `README.md` and `docs/CICD.md` are the permanent record.
- **Do NOT expect to reproduce the Wazi steps on a fresh Xplore ID.** To reproduce, use an enterprise LPAR where Wazi Deploy is installed by your sysprog, or use the `deployment_method.yaml` and `app_manifest.yaml` in this repo as reference artifacts.

---

## 5. What to Do on an Enterprise LPAR Instead

If you move this project to a corporate LPAR, these Xplore constraints go away, but the architecture stays the same:

| On Xplore | On Enterprise LPAR |
|---|---|
| Use `/usr/lpp/IBM/gdp/dependencies/` only | Install Wazi Deploy + deps via SMP/E / pip with sysprog approval |
| No `pypi.org` | Use corporate Artifactory / pip mirror |
| HLQ `Z78651.BUILD` | Use team HLQ, e.g. `TEAM.BUILD` |
| `Z78651.TEST.LOAD` / `Z78651.PROD.LOAD` | Use team TEST / PROD HLQs, with RACF / SMS rules |
| JFrog trial `trialfh3rbr.jfrog.io` | Use corporate JFrog / Nexus |
| GitHub Actions + `appleboy/ssh-action` | Use corporate runner + SSH / Zowe CLI, with key auth, not password |
| Small USS quota, `HISTFILE=/dev/null` | Still good practice, but quota is larger |

The workflows in `.github/workflows/` are written to be portable: change `HLQ`, `JFROG_URL`, and secrets, and the same chain runs on an enterprise LPAR.

---

## 6. Quota and Workspace Hygiene

- Check quota: `df -k /z | head -5` - need >5000 free 1K blocks.
- Clean: `rm -rf ~/.npm ~/.zsh_history* ~/.vscode-server ~/.cache /z/z78651/work/workspace/*`
- Keep `~/.profile` with:
```sh
export HISTFILE=/dev/null
```
- Clean Wazi temp dirs after each run: `rm -rf /tmp/wazi-deploy /tmp/wazi-deploy-dev`

---

## 7. Related Docs

- `README.md` - Portfolio front door, Xplore Constraints summary
- `docs/ARCHITECTURE.md` - Components, promotion model
- `docs/CICD.md` - Workflow chain, JFrog source of truth
- `docs/RUNBOOK.md` - INC-10 to INC-19 triage for Phase 2/3
- `docs/SETUP.md` - Reproduce from clone (enterprise LPAR)
