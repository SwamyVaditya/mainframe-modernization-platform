# SETUP - Reproduce This Project From Clone

> From empty machine to GREEN CI/CD.
> This project was built on IBM Z Xplore (ID Z78651, z/OS 3.1) during a time-limited project window. Wazi Deploy was available on that LPAR during the window and has since been removed. To reproduce the full Wazi steps, use an enterprise LPAR where Wazi Deploy is installed by your sysprog. On Xplore today, you can still reproduce Phase 1 (DBB User Build) and the GitHub Actions structure, but not the Wazi Deploy steps.

---

## 1. What You Need

### 1.1 On Your Workstation

| Tool | Version Used | Notes |
|---|---|---|
| Windows | 11 | Or macOS / Linux, paths below are Windows |
| VS Code | Latest | With IBM Z Open Editor extension |
| Git | 2.42+ | |
| Node.js | 18+ | For Zowe CLI, if used |
| Zowe CLI | 8.x | Optional, for `zowe` commands |
| GitHub account | — | Fork / clone this repo |
| JFrog account | Trial / Corporate | Generic repo `mainframe-loads-local` |

### 1.2 On z/OS

| Tool | Version Used | Location on Xplore |
|---|---|---|
| z/OS | 3.1 | Xplore LPAR |
| COBOL | 6.5.0 | `IGY650.SIGYCOMP` |
| Binder | — | `CEE.SCEELKED` |
| DBB Toolkit | 2.0.2.7 | `/usr/lpp/IBM/dbb/bin/groovyz` |
| zAppBuild | 3.14.0-BASE | `/z/z78651/work/dbb-zappbuild/build.groovy` |
| Python | 3.9.2 | `/usr/lpp/IBM/cyp/v3r9/pyz` |
| Rocket Git | 2.26+ | `/usr/lpp/Rocket/rsusr/ported/bin/` |
| Java | 11 | `/usr/lpp/java/J11.0_64` |
| Wazi Deploy | 3.0.0 | `/usr/lpp/IBM/gdp/` — **time-limited, now removed on Xplore. Use enterprise LPAR to reproduce.** |

### 1.3 GitHub Secrets

Set in Repo → Settings → Secrets and variables → Actions:

| Secret | Example | Used By |
|---|---|---|
| `ZOS_HOST` | `204.90.115.200` | All workflows, SSH to USS |
| `ZOS_USER` | `Z78651` | All workflows |
| `ZOS_PASSWORD` | `********` | All workflows |
| `ZOS_PORT` | `22` | All workflows |
| `JFROG_URL` | `https://trialfh3rbr.jfrog.io` | Package + Deploy |
| `JFROG_USER` | `your-jfrog-user` | Package + Deploy |
| `JFROG_TOKEN` | `********` | Package + Deploy |
| `SONAR_TOKEN` | `********` | DBB Build, SonarCloud |

> Never commit secrets. Never put them in `zowe.config.user.json`. Use GitHub Secrets only.

---

## 2. Clone and First Build (Phase 1 - DBB User Build)

```powershell
# 1. Clone - use a short path, no spaces / brackets
git clone https://github.com/SwamyVaditya/mainframe-modernization-platform.git D:\mf\mainframe-modernization-platform
cd D:\mf\mainframe-modernization-platform

# 2. Open in VS Code
code .

# 3. Check structure
# cobol/ACCTBALA.cbl
# copybook/ACCTREC.cpy
# application-conf/Cobol.properties
# application-conf/application.properties
# application-conf/datasets.properties
# zapp.yaml
# sonar-project.properties
```

### 2.1 Configure `~/.profile` on USS

SSH to USS, edit `~/.profile`:

```sh
export HISTFILE=/dev/null
export PYTHONHOME=/usr/lpp/IBM/cyp/v3r9/pyz
export JAVA_HOME=/usr/lpp/java/J11.0_64
export DBB_HOME=/usr/lpp/IBM/dbb
export PATH=$PYTHONHOME/bin:$JAVA_HOME/bin:$DBB_HOME/bin:/usr/lpp/Rocket/rsusr/ported/bin:$PATH
export GIT_SSL_CAINFO=/usr/lpp/Rocket/rsusr/ported/bin/ca-bundle.crt
# Do NOT add aliases for wazideploy-* here - they do not expand in headless CI shells.
# Do NOT add ~/.local to PYTHONPATH. Use only /usr/lpp/IBM/gdp/dependencies/ if needed.
```

Source it:

```sh
. ~/.profile
git --version
python3 --version
```

### 2.2 Validate Properties

```properties
# application-conf/Cobol.properties - must be:
SIGYCOMP_V6=IGY650.SIGYCOMP
SDFHCOB=IGY650.SIGYCOMP
SCEELKED=CEE.SCEELKED
cobol_BMS_PDS=Z78651.BUILD.COPY
cobol_dependencySearch=${copybookSearch}

# application-conf/application.properties - must be:
copybookSearch=search:${workspace}/?path=${application}/copybook/*.cpy
objectSearch=
```

### 2.3 First User Build

1. In VS Code, open `cobol/ACCTBALA.cbl`
2. Run: `Z Open Editor: Run IBM User Build with Full Upload`
3. Verify on USS:
```sh
ls /z/z78651/work/workspace/logs/
cat /z/z78651/work/workspace/logs/BuildReport.json
# Expect: totalFiles=1, Build State CLEAN, ACCTREC resolved: true
```
4. Incremental: Edit file → `Run IBM User Build` (normal, not Full Upload) → <5 sec

If it fails, see `docs/RUNBOOK.md` Phase 1 triage 1-9.

---

## 3. CI - DBB Build (Phase 2)

### 3.1 Push to `main` via PR

Branch protection blocks direct push to `main` (`GH006`). Always use a PR:

```powershell
git checkout -b feat/my-change
git add .
git commit -m "feat: my change"
git push origin feat/my-change
# Open PR on GitHub -> Merge
```

### 3.2 What `DBB Build` Does

Workflow: `.github/workflows/dbb-build.yml`, name: `DBB Build`

1. SSH to USS, clone / fetch + `git reset --hard origin/main`
2. Incremental build via `git diff` (only changed COBOL / copybooks)
3. DBB Metadata Store (H2) - tracks build state
4. SonarQube Quality Gate via SonarCloud (`sonar-project.properties` in repo root, `sonar.sources=cobol,copybook`, `sonar.cobol.copy.directories=copybook`, `sonar.sourceEncoding=IBM1047`)
5. ZUnit job - **currently a stub** that echoes `12/12 PASS`. See `docs/RUNBOOK.md` INC-18. Do not claim it as a real runner until `zunit.groovy` is wired in.
6. Gitleaks secret scan
7. Build Summary - version `core-banking-app-1.0.<run_number>`

### 3.3 Verify GREEN

- GitHub → Actions → `DBB Build` → GREEN
- SonarCloud → Quality Gate Passed, 0 new issues, Security Rating A
- Build Summary shows `BuildReport.json` with 1 file

### 3.4 SonarQube False Positives

If SonarCloud flags `Use full commit SHA` or `Avoid expanding secrets in run block` on `appleboy/ssh-action@v4` / `sonarqube-scan-action@v3`:

- Do NOT use invalid SHAs from memory - they fail to resolve. Use tags `@v4`, `@v3`, `@v1.0.3`.
- In SonarCloud UI, mark those issues as False Positive / Accepted. They are not real vulnerabilities.

---

## 4. CD - Package and Publish (Phase 3, Part 1)

Workflow: `.github/workflows/package-and-publish.yml`, name: `Package and Publish`

Trigger: `workflow_run: ["DBB Build"]` only, gated on `conclusion == 'success'`.

### 4.1 What It Does

1. Downloads `BuildReport.json` from the triggering `DBB Build` run (not a dummy)
2. Generates `app_manifest.yaml` dynamically via `scripts/generate_manifest.py` from `BuildReport.json` - **do NOT commit `app_manifest.yaml`, it is generated**
3. Uses generic `wazi-deploy/deployment_method.yaml` (application-level, not single-program)
4. Runs `wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml`
5. Verifies: `Found 1 LOAD module(s): ['ACCTBALA']`, `*** 1 item found [ACCTBALA.LOAD]`
6. Creates `deployable.tar` (10240 bytes for ACCTBALA)
7. Publishes to JFrog: `mainframe-loads-local/core-banking-app/1.0.<run_number>/deployable.tar` with SHA256
8. Uploads GitHub Artifact as debug copy only (30-day cache, not source of truth)

### 4.2 Verify JFrog

```sh
curl -u "$JFROG_USER:$JFROG_TOKEN" "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/1.0.120/deployable.tar" -I
# Expect: 200, size 10240, sha256 20c66b2f...
```

### 4.3 Encoding Rules for Wazi Files

- **No emojis** in any YAML, JCL, or workflow `echo` line. Emojis crash `latin-1` encoder.
- **No copy-paste from rendered pages** - it inserts `¦` (U+00A6) which breaks UTF-8.
- **No Jinja2 `{% if %}` in `deployment_method.yaml`** - use plain YAML. `deployment_method.j2` is future template only.
- **Scrub Control-Z:** In Python, `text.replace('\x1a', '')` before writing, then write with `encoding='iso-8859-1', errors='ignore'`.
- **Create files on USS with `cat << 'EOF'` + `chtag -t -c ISO8859-1`**, not Windows paste (CRLF / EBCDIC corruption).
- **Use `ls -l`, not `ls -h`** - USS `ls` has no `-h`.

See `docs/RUNBOOK.md` INC-12, INC-13, INC-14.

---

## 5. CD - Deploy (Phase 3, Part 2)

Workflow: `.github/workflows/deploy.yml`, name: `Deploy`

Trigger: `workflow_run: ["Package and Publish"]` only.

### 5.1 What It Does

1. Downloads **same version** from JFrog via `curl -u "$JFROG_USER:$JFROG_TOKEN" -O "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/1.0.<run_number>/deployable.tar"` - **not** `actions/download-artifact`
2. Verifies SHA256 matches Package step
3. **DEV (auto):** Wazi Deploy to `Z78651.DEV.LOAD`, smoke test `LISTDS`, PASS
4. **TEST (approval):** GitHub Environment approval → `ALLOC` `Z78651.TEST.LOAD` (idempotent, `IGD17001I DUPLICATE` is expected) → `cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"` → smoke test
5. **PROD (approval):** GitHub Environment approval → `ALLOC` `Z78651.PROD.LOAD` (dynamically cataloged if new) → same `cp` bridge → smoke test
6. CD Summary: DEV / TEST / PROD Passed
7. Rollback on failure: re-deploy previous JFrog version

### 5.2 Why `cp` Bridge, Not `OCOPY`

`OCOPY` / `OEXEC` copy MVS ↔ USS, not MVS ↔ MVS, and expect a pre-allocated DDNAME. The two-stage pattern is:

```sh
# 1. Allocate (idempotent)
tsocmd "ALLOC DD(TESTLOAD) DSN('Z78651.TEST.LOAD') TRACKS SPACE(1,5) DSNTYPE(LIBRARY) RECFM(U) BLKSIZE(32760) NEW CATALOG" || echo "Dataset may already exist - continuing"

# 2. Copy via USS filesystem bridge (MVS-to-MVS)
cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"
```

See `docs/RUNBOOK.md` INC-15.

### 5.3 Workflow Names - Critical

`workflow_run.workflows` must match the **workflow `name:`**, not a job name. Use simple names only:

```yaml
# dbb-build.yml
name: DBB Build
# package-and-publish.yml
name: Package and Publish
on:
  workflow_run:
    workflows: ["DBB Build"]
# deploy.yml
name: Deploy
on:
  workflow_run:
    workflows: ["Package and Publish"]
```

Names with `(`, `+`, `->` break `workflow_run` and the chain never triggers. See `docs/RUNBOOK.md` INC-16.

---

## 6. Verify End-to-End

```sh
# On USS
tsocmd "LISTDS 'Z78651.BUILD.LOAD' MEMBERS"
tsocmd "LISTDS 'Z78651.TEST.LOAD' MEMBERS"
tsocmd "LISTDS 'Z78651.PROD.LOAD' MEMBERS"
# Expect: ACCTBALA in all three

# On GitHub
# DBB Build GREEN -> Package and Publish GREEN -> Deploy GREEN
# JFrog: mainframe-loads-local/core-banking-app/1.0.<run>/deployable.tar

# On SonarCloud
# Quality Gate Passed, 0 new issues
```

---

## 7. Backup Before You Lose Access

- Download `deployable.tar` from JFrog for the final version and store it in your portfolio backup.
- Save screenshots: DBB Build GREEN, Package GREEN, Deploy GREEN, SonarCloud Passed, JFrog artifact page.
- This repo is the backup. All workflows, `deployment_method.yaml`, `generate_manifest.py`, and docs are in GitHub.

---

## 8. Troubleshooting

| Symptom | Doc |
|---|---|
| `IGY.V6R4M0.SIGYCOMP NOT FOUND` | `docs/RUNBOOK.md` #2 |
| `ACCTREC resolved: false` | `docs/RUNBOOK.md` #4 |
| `IEWBLINK dir must be 0` | `docs/RUNBOOK.md` #5 |
| `bad magic number` / `No module named 'attr'` | `docs/RUNBOOK.md` INC-11 - use official deps only |
| `0x1a` / `\x1a` YAML error | `docs/RUNBOOK.md` INC-12 |
| `latin-1 codec can't encode` emoji | `docs/RUNBOOK.md` INC-13 |
| `selector was unexpected` | `docs/RUNBOOK.md` INC-14 |
| `MISSING INPUT DDNAME` on promotion | `docs/RUNBOOK.md` INC-15 |
| `workflow_run` never triggers | `docs/RUNBOOK.md` INC-16 |
| Deploy downloads wrong version | `docs/RUNBOOK.md` INC-17 |
| ZUnit 12/12 but no real runner | `docs/RUNBOOK.md` INC-18 - stub, future work |
| `fatal: 'origin' does not appear...` | `docs/RUNBOOK.md` INC-19 |

---

## 9. Related Docs

- `README.md` - Portfolio front door
- `docs/ARCHITECTURE.md` - Components, promotion model
- `docs/CICD.md` - Workflow chain, JFrog source of truth
- `docs/RUNBOOK.md` - Full triage, Phase 1 #1-9 + Phase 2/3 INC-10 to INC-19
- `docs/XPLORE-CONSTRAINTS.md` - What Xplore allows / forbids, Wazi time-limited archival
