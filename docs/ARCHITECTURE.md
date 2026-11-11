# Architecture - Mainframe Modernization Platform

## Overview

Production-grade Core Banking Account Balance service (ACCTBALA) modernized from classic COBOL/VSAM to Git-native delivery using IBM Dependency Based Build (DBB) and VS Code Z Open Editor on IBM Z Xplore.

**Principles:**

- Git as source of truth, not PDS
- DBB dependency resolution (copybook impact)
- Hybrid PDS/PDSE allocation per Xplore ACS rules
- USS workspace isolation per user (Z78651)
- Incremental builds <5s after initial Full Upload
- JFrog Artifactory is the immutable release store; GitHub Artifacts are only a 30-day debug cache
- Workflow names must be simple - names with `(`, `)`, `+`, `->` break GitHub `workflow_run`

**Platform:** IBM Z Xplore (z/OS 3.1), ID Z78651, HLQ Z78651.BUILD
**App:** core-banking-app | **Program:** ACCTBALA

---

## End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Developer Workstation (Windows)                                         │
│  VS Code                                                                │
│   ├─ Zowe Explorer v3.6.0 (profiles: zosmf, ssh)                        │
│   ├─ Z Open Editor v6.9.0 (User Build)                                  │
│   │   └─ zapp.yaml -> application-conf/* -> build.groovy                │
│   └─ Git (main) -> GitHub: SwamyVaditya/mainframe-modernization-platform│
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ z/OSMF REST + SSH (204.90.115.200:10443)
┌──────────────────────────────▼──────────────────────────────────────────┐
│ z/OS 3.1 - Xplore LPAR (Z78651)                                         │
│                                                                         │
│ USS: /z/z78651/work/workspace/                                          │
│  ├─ mainframe-modernization-platform/                                   │
│  │   ├─ cobol/ACCTBALA.cbl (ibm-1047 via .gitattributes)                │
│  │   ├─ copybook/ACCTREC.cpy                                            │
│  │   ├─ application-conf/ (file.properties, Cobol.properties, etc.)     │
│  │   └─ zapp.yaml                                                       │
│  ├─ logs/ (BuildReport.json, ACCTBALA.log)                              │
│  └─ dbb-zappbuild/ (zAppBuild 3.14.0-BASE)                              │
│      ├─ build.groovy --workspace ... --hlq Z78651.BUILD --userBuild     │
│      └─ build-conf/ (default Cobol.properties)                          │
│      └─ languages/Cobol.groovy -> creates MVSExec                       │
│                                                                         │
│ MVS: HLQ Z78651.BUILD                                                   │
│  ├─ BUILD.COBOL (PDS)   <- CopyToPDS from USS cobol/*.cbl               │
│  ├─ BUILD.COPY  (PDS)   <- ACCTREC from copybook/*.cpy (resolved true)  │
│  ├─ BUILD.OBJ   (PDS)   <- IGYCRCTL OBJECT                              │
│  ├─ BUILD.DBRM  (PDS)   <- DBRM (if SQL)                                │
│  └─ BUILD.LOAD  (PDSE LIBRARY) <- IEWBLINK load module                  │
│                                                                         │
│ Compiler: IGY650.SIGYCOMP (COBOL 6.5.0) via TASKLIB                     │
│           Found via LISTALC (not IGY.V6R4M0.SIGYCOMP)                   │
│ Binder:   CEE.SCEELKED via TMP allocation                               │
│           Found via LISTCAT LEVEL(CEE) (not CBC.V2R4M0.SCEELKED)        │
│ Runtime:  CEE.SCEERUN, DSND10.SDSNLOAD (LINKLIST)                       │
│                                                                         │
│ Wazi Deploy 3.0.0 (/usr/lpp/IBM/gdp/)                                   │
│  └─ wazideploy-package / wazideploy-deploy                              │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
GitHub Actions: DBB Build -> Package and Publish -> Deploy
                               │
JFrog Artifactory: trialfh3rbr.jfrog.io
  mainframe-loads-local/core-banking-app/<version>/deployable.tar
                               │
Promotion: Z78651.BUILD.LOAD -> Z78651.TEST.LOAD -> Z78651.PROD.LOAD
```

---

## Components

### 1. IDE Layer - VS Code

| Component | Version | Purpose |
|-----------|---------|---------|
| Zowe Explorer | v3.6.0 | Manage zosmf/ssh profiles, PDS browsing, USS files |
| Z Open Editor | v6.9.0 | User Build (Full Upload + incremental), syntax, zapp.yaml validation |
| zapp.yaml | 1.0 | Defines application, additionalDependencies, buildScriptPath |

**zapp.yaml key:**

```yaml
profiles:
  dbb-user-build:
    buildScriptPath: /z/z78651/work/dbb-zappbuild/build.groovy
    buildScriptArgs: ["--workspace", "/z/...", "--hlq", "Z78651.BUILD", "--propOverwrites", "buildOrder=Cobol.groovy"]
    additionalDependencies:
      - "copybook/ACCTREC.cpy"  # Must include copybook for Full Upload
      - "application-conf/Cobol.properties"  # Xplore fixes: IGY650, CEE.SCEELKED
```

### 2. z/OS USS Layer

- **Workspace:** `/z/z78651/work/workspace` - isolated per Xplore user
- **DBB Toolkit:** `/usr/lpp/IBM/dbb/bin/groovyz` (2.0.2.7) - runs Groovy build scripts
- **zAppBuild:** `/z/z78651/work/dbb-zappbuild/build.groovy` (3.14.0-BASE) - orchestrates build
- **COBOL USS Install:** `/usr/lpp/IBM/cobol/igyv6r4/` and `igyv6r5/` - `cob2` wrapper, not MVS PDS
- **Wazi Deploy:** `/usr/lpp/IBM/gdp/` (3.0.0) - `wazideploy-package`, `wazideploy-deploy`. Dependencies in `/usr/lpp/IBM/gdp/dependencies/`. See `docs/XPLORE-CONSTRAINTS.md`.

**HISTFILE fix:** Xplore USS quota fills with `.zsh_history`. Add to `~/.profile`:

```sh
export HISTFILE=/dev/null
```

### 3. Build Properties - Xplore-Specific Fixes

**From LISTALC discovery:**

| Property | Wrong (default) | Correct (Xplore) | Discovery |
|----------|-----------------|------------------|-----------|
| SIGYCOMP_V6 | IGY.V6R4M0.SIGYCOMP | IGY650.SIGYCOMP | LISTALC shows IGY650 |
| SDFHCOB | IGY.V6R4M0.SIGYCOMP | IGY650.SIGYCOMP | Same |
| SCEELKED | CBC.V2R4M0.SCEELKED | CEE.SCEELKED | LISTCAT LEVEL(CEE) |

**Dependency resolution fix:**

```properties
# Before (broken): search path literal ${objectSearch}
cobol_dependencySearch=${copybookSearch}${objectSearch}
# Log: search:/z/.../copybook/*.cpy${objectSearch} -> resolved false

# After (fixed):
cobol_dependencySearch=${copybookSearch}
copybookSearch=search:${workspace}/?path=${application}/copybook/*.cpy
objectSearch=  # empty
```

**BUILD datasets - Hybrid PDS/PDSE (Xplore ACS rule):**

- COBOL, COPY, OBJ, DBRM: PDS `tracks space(1,1) dsorg(PO) recfm(F,B) dir(5)`
- LOAD: PDSE LIBRARY `tracks space(1,5) dsorg(PO) recfm(U) blksize(32760) dir(5) dsntype(library)`
- BMS: `Z78651.BUILD.COPY` (not `Z78651.BMS.COPY`)

### 4. MVS Layer

**HLQ:** `Z78651.BUILD`

- **Creation:** `BuildUtilities.createLanguageDatasets(langQualifier)` verifies/creates PDS/PDSE if not exist
- **Copy:** `CopyToPDS.createMemberName(buildFile)` + `copySourceFiles()` copies USS file + dependencies (ACCTREC.cpy -> COPY PDS)
- **Compile:** `MVSExec` -> `IGYCRCTL` with `TASKLIB=IGY650.SIGYCOMP`, `SYSLIB=BUILD.COPY`, parms `LIB,SSRANGE`
- **Link:** `IEWBLINK` with `MAP,RENT,COMPAT(PM5)`, `SYSLMOD=BUILD.LOAD`

**RC handling:** `cobol_compileMaxRC=4`, `cobol_linkEditMaxRC=4` -> Build State CLEAN if RC <=4.

### 5. Packaging - Wazi Deploy

| Path | Purpose |
|---|---|
| `scripts/generate_manifest.py` | Parses `BuildReport.json` records -> `ApplicationManifest`. Dynamic: supports N LOAD modules, not hardcoded to ACCTBALA. |
| `wazi-deploy/deployment_method.yaml` | Generic, application-level DeploymentMethod. One method deploys any LOAD from the manifest via `{{name}}`, `{{dataset}}`, `{{member}}`. This is the file the pipeline uses. |
| `wazi-deploy/deployment_method.j2` | Future Jinja2 template for env-specific methods (DEV / TEST / PROD). NOT used in the current pipeline - the pipeline uses `deployment_method.yaml` directly to avoid Jinja2 `{% if %}` / filter syntax breaking PyYAML. |
| `wazi-deploy/app_manifest.yaml` | Generated, not hand-written. Regenerate via `generate_manifest.py`. |

Wazi Deploy packaging command:

```sh
wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml
```

Outputs: `deployment_plan.yaml` + `deployable.tar` (`app_manifest.yaml` + `deployment_method.yaml` + `deployment_plan.yaml`).

### 6. Artifact Store - JFrog Artifactory

- URL: `trialfh3rbr.jfrog.io` (trial)
- Repository: `mainframe-loads-local` (local repo)
- Path: `mainframe-loads-local/core-banking-app/<version>/deployable.tar`
- Version: `1.0.<github.event.workflow_run.run_number>` - same value in Package and Deploy, so Deploy fetches the exact version Package published.
- JFrog is the immutable release store. GitHub Artifacts are only a 30-day debug cache. Deploy downloads from JFrog via `curl -f -u "$JFROG_USER:$JFROG_TOKEN"`, never via `actions/download-artifact`.

### 7. Deploy - Promotion

Deploy command:

```sh
wazideploy-deploy -dp deployment_plan.yaml
```

Promotion model:

```
Z78651.BUILD.LOAD(ACCTBALA)
  -> Z78651.TEST.LOAD(ACCTBALA)
  -> Z78651.PROD.LOAD(ACCTBALA)
```

Two steps, in order, for each target environment:

1. **Allocate target PDSE if it does not exist:**
   ```sh
   tsocmd "ALLOC DD(TESTLOAD) DSN('Z78651.TEST.LOAD') TRACKS SPACE(1,5) DSNTYPE(LIBRARY) RECFM(U) BLKSIZE(32760) NEW CATALOG"
   ```
   If the dataset already exists, this returns `IGD17001I DUPLICATE DATA SET NAME` - expected, not a failure. Handle as idempotent.

2. **Copy via USS bridge:**
   ```sh
   cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"
   ```
   OCOPY / OEXEC cannot do MVS-to-MVS directly. They expect a DDNAME bound via JCL, not a raw dataset string. The USS `cp` with `//'<dataset>(member)'` syntax uses C-library file streaming and works for MVS-to-MVS.

Smoke test after each environment:

```sh
tsocmd "LISTDS 'Z78651.TEST.LOAD' MEMBERS" | grep ACCTBALA
```

---

## Data Flow - ACCTBALA Example

1. **User edits** `cobol/ACCTBALA.cbl` in VS Code (ibm-1047 via `.gitattributes`)

2. **First time:** `Run User Build with Full Upload` uploads:
   - `cobol/ACCTBALA.cbl` -> `/z/.../cobol/ACCTBALA.cbl` (chtag ibm-1047)
   - `copybook/ACCTREC.cpy` -> `/z/.../copybook/ACCTREC.cpy`
   - `application-conf/*` -> `/z/.../application-conf/*` (iso8859-1)
   - `zapp.yaml`

3. **DBB:** `build.groovy --userBuild /z/.../cobol/ACCTBALA.cbl`
   - Loads `build-conf/Cobol.properties` + `application-conf/Cobol.properties` (override)
   - `SearchPathDependencyResolver(dependencySearch)` finds `ACCTREC.cpy` -> `resolved: true`
   - `copySourceFiles()` -> `Z78651.BUILD.COBOL(ACCTBALA)`, `Z78651.BUILD.COPY(ACCTREC)`
   - `MVSJob` -> `compile.execute()` -> `IGYCRCTL` -> `Z78651.BUILD.OBJ(ACCTBALA)`
   - `linkEdit.execute()` -> `IEWBLINK` -> `Z78651.BUILD.LOAD(ACCTBALA)`

4. **Logs:** `/z/.../logs/ACCTBALA.log` (compiler listing), `BuildReport.json` (totalFiles=1, CLEAN)

5. **Download:** Z Open Editor downloads logs to `D:\...\logs\`

6. **Incremental:** Edit file -> `Run User Build` (no Full Upload) -> DBB reuses BUILD PDS, <5s

7. **CI/CD:** `BuildReport.json` -> `generate_manifest.py` -> `app_manifest.yaml` -> `wazideploy-package` -> `deployable.tar` -> JFrog `1.0.<run_number>` -> Deploy downloads same version from JFrog -> `wazideploy-deploy` -> TEST / PROD promotion -> `LISTDS` smoke test.

---

## CI/CD Workflow Chain

| Workflow file | Workflow name | Trigger | Jobs |
|---|---|---|---|
| `.github/workflows/dbb-build.yml` | `DBB Build` | push to main, PR to main, workflow_dispatch | changed-files, sonar-scan, security-scan (gitleaks), dbb-build, zunit-tests, build-summary |
| `.github/workflows/package-and-publish.yml` | `Package and Publish` | `workflow_run: ["DBB Build"]` (completed), workflow_dispatch | Wazi Package + JFrog Publish |
| `.github/workflows/deploy.yml` | `Deploy` | `workflow_run: ["Package and Publish"]` (completed), workflow_dispatch | deploy-dev (auto), deploy-test (approval), deploy-prod (approval), summary |

**Workflow names must be simple.** Names with `(`, `)`, `+`, `->` break GitHub `workflow_run` triggering. The project previously used `DBB Build - Production Grade (Incremental + SonarQube + ZUnit)` and the CD chain never triggered. Fixed to `DBB Build`. See `docs/CICD.md`.

**Sequential, not parallel.** Package only runs after DBB Build succeeds. Deploy only runs after Package succeeds. The `if: github.event.workflow_run.conclusion == 'success'` gate enforces this.

---

## Environments

| Environment | Trigger | Approval | Target dataset | Purpose |
|---|---|---|---|---|
| DEV | Auto, after Package succeeds | None | `Z78651.BUILD.LOAD` (build) | Smoke test, fast feedback |
| TEST | After DEV succeeds | GitHub Environment `TEST` approval | `Z78651.TEST.LOAD` | Isolated staging, duplicate-dataset handling |
| PROD | After TEST succeeds | GitHub Environment `PROD` approval | `Z78651.PROD.LOAD` | Production, dynamic allocation if not exists, rollback on failure |

TEST and PROD are isolated PDSE libraries, not the same dataset as BUILD. Promotion is a copy, not a move. BUILD is never deleted by Deploy.

---

## Security

- **Secrets:** `zowe.config.user.json`, `.vscode/settings.json`, `logs/*.log` in `.gitignore`
- **Secure storage:** `zowe config set --secure` stores in OS credential vault, not file
- **GitHub Actions:** Use `secrets.ZOS_USER/PASSWORD`, `secrets.JFROG_URL/USER/TOKEN`, `secrets.SONAR_TOKEN`, never committed files
- Secrets are passed via `env:` in workflow steps, never echoed, never as literals in `run:` blocks.

---

## Encoding and File Tags

- COBOL source: `ibm-1047` (EBCDIC) via `.gitattributes`.
- YAML for Wazi Deploy: `ISO8859-1` (ASCII) via `chtag -t -c ISO8859-1`.
- Generated YAML: written in Python with `encoding='iso-8859-1', errors='ignore'`, after stripping `\x1a` Control-Z.
- No emojis in YAML, JCL, or workflow `echo` lines. Emojis crash the `latin-1` encoder.
- No Jinja2 `{% if %}` in YAML that Wazi Deploy parses. Use `deployment_method.yaml` directly.

---

## Phase 1 vs Phase 2 vs Phase 3

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** | DBB User Build in VS Code, single file ACCTBALA, CLEAN build, Xplore fixes, GitHub push, docs | Complete |
| **Phase 2** | GitHub Actions CI: DBB Build - incremental, Gitleaks, SonarQube gate, ZUnit 12/12, Build Summary | Complete - GREEN |
| **Phase 3** | GitHub Actions CD: Package and Publish (Wazi + JFrog) + Deploy (DEV / TEST / PROD, JFrog download, rollback) | Complete - GREEN |

---

## What Is Out of Scope

- No VSAM, DB2, CICS in the current pipeline beyond ACCTBALA's VSAM KSDS read. ACCTBALA is a balance inquiry, not a full transaction system.
- No Wazi Deploy GUI, no Z CodeScan. SonarQube is used for static analysis.
- No `deployment_method.j2` rendering in the pipeline. It is a future template, not a runtime dependency.
- No custom Python wheels in `~/.local`. See `docs/XPLORE-CONSTRAINTS.md`.

---

## References

- IBM DBB Docs: https://www.ibm.com/docs/en/dbb/2.0.2
- zAppBuild 3.14: https://github.com/IBM/dbb-zappbuild
- Z Xplore: https://ibm.com/z/xplore
- VS Code Z Open Editor: https://marketplace.visualstudio.com/items?itemName=IBM.zopeneditor
- Related docs: `docs/CICD.md`, `docs/RUNBOOK.md`, `docs/XPLORE-CONSTRAINTS.md`, `README.md`

