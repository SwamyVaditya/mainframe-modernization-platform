# Mainframe Modernization Platform
> Production-grade Core Banking Account Balance Service - modernized from classic COBOL/VSAM to Git-native delivery using IBM DBB and Z Open Editor

**Team:** Z78651 | **HLQ:** Z78651.BUILD | **Platform:** IBM Z Xplore (z/OS 3.1)

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
```

**Stack:** COBOL 6.5.0, VSAM KSDS, JCL, DBB, Git, VS Code, GitHub Actions (Phase 2)

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

## Phase 1 - DBB User Build Workflow - COMPLETE ✅

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
|-------|-------|-----|-----------|
| **Compiler PDS** | `alloc dd(TASKLIB) dsn(IGY.V6R4M0.SIGYCOMP) shr` NOT IN CATALOG | `SIGYCOMP_V6=IGY650.SIGYCOMP` | `LISTALC` showed `IGY650.SIGYCOMP` - COBOL 6.5.0 short name, not V6R4M0 long name |
| **Binder PDS** | `alloc dd(TMP00002) dsn(CBC.V2R4M0.SCEELKED) shr` | `SCEELKED=CEE.SCEELKED` | `LISTCAT LEVEL(CEE)` -> `CEE.SCEELKED` exists, CBC version does not |
| **Copybook resolution** | `ACCTREC resolved: false`, `IGYLI0048-S member not found` | `cobol_dependencySearch=${copybookSearch}` (remove `${objectSearch}`) | Log showed `search:.../*.cpy${objectSearch}` literal not expanded; `objectSearch` undefined |
| **BUILD datasets ACS** | `Load module IEWBLINK failed, dir must be 0 for PDSE` | Hybrid: PDS for COBOL/COPY/OBJ/DBRM, PDSE LIBRARY for LOAD | Xplore ACS rule: LOAD must be PDSE `dsntype(library) dir(5)`, others PDS |
| **BMS COPY PDS** | `alloc dd(TMP00001) dsn(Z78651.BMS.COPY) shr` | `cobol_BMS_PDS=Z78651.BUILD.COPY` | Default `Z78651.BMS.COPY` doesn't exist, use BUILD.COPY |
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

## Phase 2 - CI/CD (Next)

- [ ] GitHub Actions workflow `.github/workflows/dbb-build.yml`
  - Trigger: push to `feature/*`, PR to `main`
  - Steps: Zowe CLI upload + DBB build via SSH (`/usr/lpp/IBM/dbb/bin/groovyz`)
  - Secrets: `ZOSMF_HOST`, `ZOSMF_USER`, `SSH_KEY`
- [ ] Branch protection: Require DBB build CLEAN
- [ ] Wazi Deploy + ZCodeScan integration

---

## Troubleshooting - RUNBOOK

See `docs/RUNBOOK.md` for detailed triage.

**Common errors:**

1. `HISTFILE permission denied` -> Add `HISTFILE=/dev/null` to `~/.profile`
2. `IGY.V6R4M0.SIGYCOMP NOT IN CATALOG` -> Use `IGY650.SIGYCOMP` from LISTALC
3. `ACCTREC not found` -> Check `dependencySearch` has no `${objectSearch}` suffix
4. `IEWBLINK dir must be 0` -> LOAD must be PDSE LIBRARY, others PDS
5. `0 files processed` -> Use Full Upload first time to push `application-conf/*`

**Diagnostics:**

```sh
tsocmd "LISTALC"
tsocmd "LISTCAT LEVEL(CEE)" | grep LKED
tsocmd "LISTCAT LEVEL(IGY)"
/usr/lpp/IBM/cobol/igyv6r4/bin/cob2 --help
```

---

## Author

**Swamy Vaditya** - Mainframe Modernization Engineer | IBM Z Xplore (Z78651)

Portfolio project demonstrating enterprise-grade DBB User Build + GitHub Actions modernization on IBM Z.

- Original work: ACCTBALA.cbl + ACCTREC.cpy are original production-grade examples (not IBM SAM1 samples)
- Built on IBM Z Xplore - HLQ Z78651.BUILD
- Stack: COBOL 6.5.0, VSAM KSDS, DBB 2.0.2.7, zAppBuild 3.14, Z Open Editor 6.9.0, GitHub Actions

**Contact:** [LinkedIn: https://www.linkedin.com/in/swamyvaditya/] | [GitHub: SwamyVaditya] | swamyvaditya@gmail.com

> This repository is part of my mainframe modernization portfolio, showcasing Git-native DevOps transformation of classic COBOL/VSAM to modern CI/CD.