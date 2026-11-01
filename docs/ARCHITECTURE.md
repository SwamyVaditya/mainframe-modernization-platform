# Architecture - Mainframe Modernization Platform

## Overview

Production-grade Core Banking Account Balance service (ACCTBALA) modernized from classic COBOL/VSAM to Git-native delivery using IBM Dependency Based Build (DBB) and VS Code Z Open Editor on IBM Z Xplore.

**Principles:**
- Git as source of truth, not PDS
- DBB dependency resolution (copybook impact)
- Hybrid PDS/PDSE allocation per Xplore ACS rules
- USS workspace isolation per user (Z78651)
- Incremental builds <5s after initial Full Upload

---

## End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Developer Workstation (Windows)                                         │
│  VS Code                                                                │
│   ├─ Zowe Explorer v3.6.0 (profiles: zosmf, ssh)                         │
│   ├─ Z Open Editor v6.9.0 (User Build)                                   │
│   │   └─ zapp.yaml -> application-conf/* -> build.groovy                │
│   └─ Git (main) -> GitHub: SwamyVaditya/mainframe-modernization-platform│
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ z/OSMF REST + SSH (204.90.115.200:10443)
┌──────────────────────────────▼──────────────────────────────────────────┐
│ z/OS 3.1 - Xplore LPAR (Z78651)                                          │
│                                                                          │
│ USS: /z/z78651/work/workspace/                                           │
│  ├─ mainframe-modernization-platform/                                     │
│  │   ├─ cobol/ACCTBALA.cbl (ibm-1047 via .gitattributes)                 │
│  │   ├─ copybook/ACCTREC.cpy                                              │
│  │   ├─ application-conf/ (file.properties, Cobol.properties, etc.)      │
│  │   └─ zapp.yaml                                                         │
│  ├─ logs/ (BuildReport.json, ACCTBALA.log)                                │
│  └─ dbb-zappbuild/ (zAppBuild 3.14.0-BASE)                                │
│      ├─ build.groovy --workspace ... --hlq Z78651.BUILD --userBuild      │
│      └─ build-conf/ (default Cobol.properties)                           │
│      └─ languages/Cobol.groovy -> creates MVSExec                        │
│                                                                          │
│ MVS: HLQ Z78651.BUILD                                                    │
│  ├─ BUILD.COBOL (PDS)   <- CopyToPDS from USS cobol/*.cbl               │
│  ├─ BUILD.COPY  (PDS)   <- ACCTREC from copybook/*.cpy (resolved true)  │
│  ├─ BUILD.OBJ   (PDS)   <- IGYCRCTL OBJECT                                │
│  ├─ BUILD.DBRM  (PDS)   <- DBRM (if SQL)                                  │
│  └─ BUILD.LOAD  (PDSE LIBRARY) <- IEWBLINK load module                   │
│                                                                          │
│ Compiler: IGY650.SIGYCOMP (COBOL 6.5.0) via TASKLIB                       │
│           Found via LISTALC (not IGY.V6R4M0.SIGYCOMP)                    │
│ Binder:   CEE.SCEELKED via TMP allocation                                 │
│           Found via LISTCAT LEVEL(CEE) (not CBC.V2R4M0.SCEELKED)          │
│ Runtime:  CEE.SCEERUN, DSND10.SDSNLOAD (LINKLIST)                         │
└──────────────────────────────────────────────────────────────────────────┘
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

---

## Security

- **Secrets:** `zowe.config.user.json`, `.vscode/settings.json`, `logs/*.log` in `.gitignore`
- **Secure storage:** `zowe config set --secure` stores in OS credential vault, not file
- **GitHub Actions (Phase 2):** Use `secrets.ZOSMF_USER/PASSWORD`, not committed files

---

## Phase 1 vs Phase 2

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** | DBB User Build in VS Code, single file ACCTBALA, CLEAN build, Xplore fixes, GitHub push, docs | ✅ Complete |
| **Phase 2** | GitHub Actions CI: push to feature/* -> DBB build on Xplore via SSH, PR protection, Wazi Deploy, ZCodeScan | Next |

---

## References

- IBM DBB Docs: https://www.ibm.com/docs/en/dbb/2.0.2
- zAppBuild 3.14: https://github.com/IBM/dbb-zappbuild
- Z Xplore: https://ibm.com/z/xplore
- VS Code Z Open Editor: https://marketplace.visualstudio.com/items?itemName=IBM.zopeneditor
