# Mainframe Modernization Platform

> Production-grade Core Banking Account Balance Service - modernized from classic COBOL/VSAM to Git-native delivery using IBM DBB, Wazi Deploy, JFrog Artifactory, and GitHub Actions.

**Team:** Z78651 | **HLQ:** Z78651.BUILD | **Platform:** IBM Z Xplore (z/OS 3.1)
**App:** core-banking-app | **Program:** ACCTBALA | **Status:** DBB Build GREEN, Package and Publish GREEN, Deploy GREEN

---

## Evidence

Verified GREEN runs with screenshots + logs: [docs/EVIDENCE.md](docs/EVIDENCE.md)

- `*** 1 item found [ACCTBALA.LOAD]` - schema fix for Wazi Deploy
- JFrog `1.0.115 / deployable.tar` - SHA256 `20c66b2f...332`
- DEV / TEST / PROD - all Passed, `Z78651.PROD.LOAD` verified

---

## What This Is

A complete, end-to-end mainframe CI/CD platform:

```
PR -> DBB Build -> Package and Publish -> JFrog Artifactory -> Deploy -> DEV / TEST / PROD
```

| Stage | What happens | Source of truth |
|---|---|---|
| DBB Build | Incremental COBOL build, SonarQube gate, ZUnit tests | `BuildReport.json` |
| Package and Publish | `BuildReport.json` -> ApplicationManifest (dynamic) -> Wazi Deploy package -> JFrog | JFrog `mainframe-loads-local/core-banking-app/<version>/deployable.tar` |
| Deploy | Download same immutable version from JFrog -> Wazi Deploy -> Smoke tests -> Rollback on failure | JFrog (not GitHub Artifacts) |

GitHub Artifacts are only a 30-day debug cache. JFrog Artifactory is the immutable release store. Deploy downloads from JFrog, never from GitHub Artifacts.

---

## Architecture

```
VS Code [Zowe Explorer + Z Open Editor 6.9.0]
   |
   +-- z/OSMF (REST) + SSH (zosmf / ssh profiles)
   |
z/OS USS: /z/z78651/work/workspace
   |
   +-- DBB Toolkit 2.0.2.7 (/usr/lpp/IBM/dbb/bin/groovyz)
   +-- zAppBuild 3.14.0-BASE (/z/z78651/work/dbb-zappbuild/build.groovy)
   +-- BUILD PDS: Z78651.BUILD.* (COBOL/COPY/OBJ/DBRM/LOAD)
   |
MVS: Batch Compile IGYCRCTL + IEWBLINK
   |
GitHub Actions -> JFrog Artifactory -> Wazi Deploy 3.0.0 -> Z78651.TEST.LOAD / Z78651.PROD.LOAD
```

**Stack:** COBOL 6.5.0, VSAM KSDS, JCL, DBB 2.0.2.7, zAppBuild 3.14, Wazi Deploy 3.0.0, JFrog Artifactory, SonarQube, ZUnit, GitHub Actions

**Repo layout:**

```
cobol/ACCTBALA.cbl              # Batch COBOL + VSAM KSDS
copybook/ACCTREC.cpy            # 01 ACCT-RECORD
application-conf/               # Cobol.properties, application.properties, datasets.properties
zapp.yaml                       # DBB user-build profile, HLQ Z78651.BUILD
.github/workflows/
  dbb-build.yml                 # Name: DBB Build
  package-and-publish.yml       # Name: Package and Publish
  deploy.yml                    # Name: Deploy
wazi-deploy/
  deployment_method.yaml        # Generic, application-level, not per-program
  deployment_method.j2          # Future template for env-specific methods
  README.md                     # Wazi Deploy notes
scripts/
  generate_manifest.py          # BuildReport.json -> ApplicationManifest (dynamic)
docs/
  ARCHITECTURE.md
  CICD.md
  RUNBOOK.md
  XPLORE-CONSTRAINTS.md
```

---

## Program: ACCTBALA

- **Type:** Batch COBOL + VSAM KSDS (INDEXED, RANDOM)
- **Copybook:** ACCTREC.cpy - 01 ACCT-RECORD (ACCT-NUMBER, BALANCE COMP-3, STATUS, etc.)
- **Purpose:** Account balance inquiry - production-grade example for portfolio
- **Design:** DBB dependency resolution demo, original code (not SAM1)

```
cobol/ACCTBALA.cbl      -> Z78651.BUILD.COBOL(ACCTBALA) -> OBJ -> LOAD
copybook/ACCTREC.cpy    -> Z78651.BUILD.COPY(ACCTREC)   -> SYSLIB resolution
```

---

## Phase 1 - DBB User Build Workflow - COMPLETE

### Final Build Status: CLEAN

```
** Build State : CLEAN
** Total files processed : 1
** Total build time  : 10.544 seconds
*** Physical dependencies: ACCTREC resolved: true
```

### How to Run (VS Code)

1. **Clean USS workspace (first time / when stuck):**

   ```sh
   ssh zosmf
   rm -rf /z/z78651/work/workspace/* && mkdir -p /z/z78651/work/workspace/logs
   ```

2. **Fix Xplore HISTFILE issue** - Add to `~/.profile`:

   ```sh
   export HISTFILE=/dev/null
   ```

3. **VS Code settings.json** (`zopeneditor.userbuild.userSettings`):

   ```json
   "dbbWorkspace": "/z/z78651/work/workspace",
   "dbbHlq": "Z78651.BUILD",
   "dbbLogDir": "/z/z78651/work/workspace/logs"
   ```

4. **First build - MUST use Full Upload:**
   - Open `cobol/ACCTBALA.cbl`
   - Command Palette: `Z Open Editor: Run IBM User Build with Full Upload`
   - This uploads `application-conf/*`, `copybook/*`, `zapp.yaml`

5. **Verify:**
   - `logs/ACCTBALA.log` -> RC 0 or 4, `ACCTREC` resolved
   - `logs/BuildReport.json` -> totalFiles=1

6. **Incremental builds (after first success):**
   - Edit `ACCTBALA.cbl` -> `Run IBM User Build` (not Full Upload) -> <5 sec

### Critical Fixes Applied (Xplore-Specific)

These were discovered via `LISTALC`, `LISTCAT`, `cob2 --help` on Xplore. Documented for team Z78651.

| Issue | Error | Fix | Discovery |
|---|---|---|---|
| **Compiler PDS** | `alloc dd(TASKLIB) dsn(IGY.V6R4M0.SIGYCOMP) shr` NOT IN CATALOG | `SIGYCOMP_V6=IGY650.SIGYCOMP` | `LISTALC` showed `IGY650.SIGYCOMP` - COBOL 6.5.0 short name, not V6R4M0 long name |
| **Binder PDS** | `alloc dd(TMP00002) dsn(CBC.V2R4M0.SCEELKED) shr` | `SCEELKED=CEE.SCEELKED` | `LISTCAT LEVEL(CEE)` -> `CEE.SCEELKED` exists, CBC version does not |
| **Copybook resolution** | `ACCTREC resolved: false`, `IGYLI0048-S member not found` | `cobol_dependencySearch=${copybookSearch}` (remove `${objectSearch}`) | Log showed `search:.../*.cpy${objectSearch}` literal not expanded; `objectSearch` undefined |
| **BUILD datasets ACS** | `Load module IEWBLINK failed, dir must be 0 for PDSE` | Hybrid: PDS for COBOL/COPY/OBJ/DBRM, PDSE LIBRARY for LOAD | Xplore ACS rule: LOAD must be PDSE `dsntype(library) dir(5)`, others PDS |
| **BMS COPY PDS** | `alloc dd(TMP00001) dsn(Z78651.BMS.COPY) shr` | `cobol_BMS_PDS=Z78651.BUILD.COPY` | Default `Z78651.BMS.COPY` does not exist, use BUILD.COPY |
| **zapp.yaml dependencies** | Copybook not uploaded | Add `copybook/ACCTREC.cpy` to `additionalDependencies` | Full Upload must include copybooks |

**Final Xplore Allocation Map (from LISTALC):**

```
ZXP.PUBLIC.LOAD
DSND10.DBDG.SDSNEXIT
DSND10.SDSNLOAD
DSND10.SDSNLOD2
CEE.SCEERUN
IGY650.SIGYCOMP   <- COBOL 6.5.0 compiler (correct)
CEE.SCEELKED     <- Binder (correct)
Z78651.BUILD.COBOL / COPY / OBJ / DBRM (PDS) / LOAD (PDSE LIBRARY)
```

**Properties - Final Working Versions:**

`application-conf/Cobol.properties`:
```properties
cobol_dependencySearch=${copybookSearch}
SIGYCOMP_V6=IGY650.SIGYCOMP
SDFHCOB=IGY650.SIGYCOMP
SCEELKED=CEE.SCEELKED
cobol_BMS_PDS=Z78651.BUILD.COPY
cobol_loadOptions=tracks space(1,5) dsorg(PO) recfm(U) blksize(32760) dir(5) dsntype(library)
```

`application-conf/application.properties`:
```properties
copybookSearch=search:${workspace}/?path=${application}/copybook/*.cpy
objectSearch=
```

`application-conf/datasets.properties` - Hybrid PDS/PDSE:
```properties
cobol_srcDatasets=Z78651.BUILD.COBOL,Z78651.BUILD.COPY,Z78651.BUILD.OBJ,Z78651.BUILD.DBRM
cobol_loadOptions=... dsntype(library)  # PDSE for LOAD
```

### Repository Standards

- All COBOL encoded `ibm-1047` via `.gitattributes`
- Original code, not IBM SAM1 samples
- Enterprise properties files - no hardcoded HLQs in Groovy
- Git-native: `.gitignore` excludes `logs/*.log` binaries

---

## Phase 2 - CI/CD - COMPLETE

### Workflow chain (sequential, no race condition)

| Workflow file | Workflow name | Trigger | Purpose |
|---|---|---|---|
| `.github/workflows/dbb-build.yml` | `DBB Build` | push to main, PR to main, workflow_dispatch | Change detection, Gitleaks, SonarQube gate, DBB build, ZUnit, Build Summary |
| `.github/workflows/package-and-publish.yml` | `Package and Publish` | `workflow_run: ["DBB Build"]`, workflow_dispatch | BuildReport.json -> ApplicationManifest -> Wazi Deploy package -> JFrog |
| `.github/workflows/deploy.yml` | `Deploy` | `workflow_run: ["Package and Publish"]`, workflow_dispatch | Download same version from JFrog -> Wazi Deploy -> DEV / TEST / PROD |

**Critical lesson - workflow names must be simple:** Names with `(`, `)`, `+`, `->` break GitHub `workflow_run` triggering. Example that failed: `DBB Build - Production Grade (Incremental + SonarQube + ZUnit)`. Fixed to `DBB Build`. See `docs/CICD.md`.

### DBB Build - GREEN

- Change Detection: incremental, only builds changed COBOL / copybook files, `ACCTBALA` fallback on main
- Security Scan: Gitleaks
- SonarQube: Quality Gate Check, `sonar.projectKey=SwamyVaditya_mainframe-modernization-platform`, encoding IBM1047
- DBB Build: real `groovyz` build, `git fetch origin` + `git reset --hard origin/main`, `BuildReport.json` generated on USS, downloaded to runner as artifact
- ZUnit: 12 / 12 assertions pass, 0 abends
- Build Summary: dashboard in GitHub Step Summary

### Package and Publish - GREEN

- Downloads `BuildReport.json` artifact from the triggering DBB Build run (not a dummy, not inline YAML)
- SCPs `BuildReport.json` to USS
- Runs `scripts/generate_manifest.py BuildReport.json wazi-deploy/app_manifest.yaml <version> <sha>` - dynamic, supports N LOAD modules, not hardcoded to ACCTBALA
- Sanitizes encoding: strips `\x1a` Control-Z, writes ISO8859-1 with `errors='ignore'` (no emojis in YAML)
- Runs `wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml`
- Creates `deployable.tar` (`app_manifest.yaml` + `deployment_method.yaml` + `deployment_plan.yaml`)
- Publishes immutable package to JFrog: `mainframe-loads-local/core-banking-app/<version>/deployable.tar`
- Also uploads a 30-day debug copy to GitHub Artifacts

Version sync: `1.0.${{ github.event.workflow_run.run_number }}` is used in Package and Deploy so Deploy fetches the exact version Package published.

### Deploy - GREEN

- Downloads the **same immutable version** from JFrog via `curl -f -u "$JFROG_USER:$JFROG_TOKEN"`, not from GitHub Artifacts
- SCPs `deployable.tar` to USS, unpacks to `/tmp/wazi-deploy-dev`
- Runs `wazideploy-deploy -dp deployment_plan.yaml`
- Promotion: `Z78651.BUILD.LOAD -> Z78651.TEST.LOAD -> Z78651.PROD.LOAD`
  - Pre-allocate target PDSE: `ALLOC DSN('Z78651.TEST.LOAD') ... DSNTYPE(LIBRARY)`
  - Copy via USS bridge: `cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"` (OCOPY cannot do MVS-to-MVS directly)
- Environments: DEV auto, TEST manual approval, PROD manual approval + rollback on smoke-test failure
- Verified: `*** 1 item found [ACCTBALA.LOAD]` in Wazi Deploy packaging, smoke test `LISTDS 'Z78651.BUILD.LOAD' MEMBERS` contains ACCTBALA

---

## Phase 3 - Wazi Deploy - COMPLETE

- `wazi-deploy/deployment_method.yaml` - Generic, application-level, not per-program. One method deploys any LOAD from the manifest via `{{name}}`, `{{dataset}}`, `{{member}}`.
- `wazi-deploy/deployment_method.j2` - Future Jinja2 template for env-specific methods (DEV / TEST / PROD). Not used in the current pipeline; the pipeline uses `deployment_method.yaml` directly to avoid Jinja2 `{% if %}` / filter syntax breaking PyYAML.
- `scripts/generate_manifest.py` - Parses `BuildReport.json` records, emits `ApplicationManifest` with all LOAD artifacts.

---

## Xplore Constraints - Read Before Reproducing

Xplore is a free, multi-tenant educational LPAR. It has no internet access to `pypi.org`.

- **Do NOT upload custom wheels to `~/wheels/` and extract them to `~/.local/`.** Xplore provides the toolchain in `/usr/lpp/`. Adding your own packages to `~/.local` conflicts with the managed environment and violates LPAR usage policy for a shared educational system. Use only official dependencies in `/usr/lpp/IBM/gdp/dependencies/`.
- **Use only official dependencies in `/usr/lpp/IBM/gdp/dependencies/`.** Wazi Deploy 3.0.0 lives in `/usr/lpp/IBM/gdp/`.
- **No emojis in YAML, JCL, or workflow `echo` lines.** Emojis (for example U+1F447) crash the `latin-1` / ISO8859-1 encoder used by Wazi Deploy. Use plain ASCII only.
- **No Control-Z (`\x1a`) in generated files.** Strip it in Python before writing YAML.
- **Use `git fetch origin` + `git reset --hard origin/main`** on USS instead of `git pull` when the workspace may have diverged. See `docs/RUNBOOK.md`.
- Full constraints: `docs/XPLORE-CONSTRAINTS.md`

---

## Troubleshooting - RUNBOOK

See `docs/RUNBOOK.md` for detailed triage.

**Common errors:**

1. `HISTFILE permission denied` -> Add `HISTFILE=/dev/null` to `~/.profile`
2. `IGY.V6R4M0.SIGYCOMP NOT IN CATALOG` -> Use `IGY650.SIGYCOMP` from LISTALC
3. `ACCTREC not found` -> Check `dependencySearch` has no `${objectSearch}` suffix
4. `IEWBLINK dir must be 0` -> LOAD must be PDSE LIBRARY, others PDS
5. `0 files processed` -> Use Full Upload first time to push `application-conf/*`
6. `workflow_run` never triggers -> Workflow name contains `(`, `+`, `->`. Use simple names: `DBB Build`, `Package and Publish`, `Deploy`
7. `UnicodeDecodeError: ... byte 0xa6` -> File contains `¦` or emoji from copy-paste. Regenerate as plain ASCII, `errors='ignore'`
8. `ParserError: while parsing a flow mapping` -> Jinja2 `{% if %}` left in YAML. Use `deployment_method.yaml` directly, not `.j2`
9. `fatal: 'origin' does not appear to be a git repository` -> USS workspace is not a git repo. Re-clone or reset remote, see RUNBOOK INC-01
10. `IKJ56701I MISSING INPUT DDNAME` on promotion -> OCOPY cannot do MVS-to-MVS. Allocate target PDSE, then `cp "//'...'" "//'...'"`

**Diagnostics:**
```sh
tsocmd "LISTALC"
tsocmd "LISTCAT LEVEL(CEE)" | grep LKED
tsocmd "LISTCAT LEVEL(IGY)"
/usr/lpp/IBM/cobol/igyv6r4/bin/cob2 --help
```

---

## Docs

- `docs/ARCHITECTURE.md` - Components, data flow, promotion model
- `docs/CICD.md` - Workflow chain, version sync, JFrog as source of truth
- `docs/RUNBOOK.md` - INC-01 to INC-06 triage, corrected fixes
- `docs/XPLORE-CONSTRAINTS.md` - What Xplore allows / forbids
- `docs/SETUP.md` - Reproduce from clone

---

## Author

**Swamy Vaditya** - Mainframe Modernization Engineer | IBM Z Xplore (Z78651)

Portfolio project demonstrating enterprise-grade DBB User Build + GitHub Actions + Wazi Deploy + JFrog modernization on IBM Z.

- Original work: ACCTBALA.cbl + ACCTREC.cpy are original production-grade examples (not IBM SAM1 samples)
- Built on IBM Z Xplore - HLQ Z78651.BUILD
- Stack: COBOL 6.5.0, VSAM KSDS, DBB 2.0.2.7, zAppBuild 3.14, Z Open Editor 6.9.0, Wazi Deploy 3.0.0, JFrog Artifactory, SonarQube, ZUnit, GitHub Actions

**Contact:** [LinkedIn: https://www.linkedin.com/in/swamyvaditya/] | [GitHub: SwamyVaditya] | swamyvaditya@gmail.com

> This repository is part of my mainframe modernization portfolio, showcasing Git-native DevOps transformation of classic COBOL/VSAM to modern CI/CD.
