# RUNBOOK - DBB User Build - Phase 1 Complete

## Quick Reference - Xplore Z78651 Allocation Map

From `tsocmd "LISTALC"` + `LISTCAT LEVEL(CEE)`:

```
ZXP.PUBLIC.LOAD
DSND10.DBDG.SDSNEXIT
DSND10.SDSNLOAD
DSND10.SDSNLOD2
CEE.SCEERUN
CEE.SCEELKED      <- Binder (IEWBLINK) - use for SCEELKED
IGY650.SIGYCOMP   <- COBOL 6.5.0 compiler - use for SIGYCOMP_V6/SDFHCOB
Z78651.BUILD.COBOL / COPY / OBJ / DBRM (PDS) / LOAD (PDSE LIBRARY)
```

**Final working properties:**

```properties
# Cobol.properties
SIGYCOMP_V6=IGY650.SIGYCOMP
SDFHCOB=IGY650.SIGYCOMP
SCEELKED=CEE.SCEELKED
cobol_BMS_PDS=Z78651.BUILD.COPY
cobol_dependencySearch=${copybookSearch}
cobol_loadOptions=tracks space(1,5) dsorg(PO) recfm(U) blksize(32760) dir(5) dsntype(library)

# application.properties
copybookSearch=search:${workspace}/?path=${application}/copybook/*.cpy
objectSearch=
```

---

## Triage Guide - Phase 1 Issues Solved

### 1. No space left on device (ENOSPC)

**Symptom:**
```
FSUZ0112 failed to write history file /z/z78651/.zsh_history.new: eDC5133I No space left on device
zsh: FSUZ0135 locking failed for /dev/null
```

**Root Cause:** Xplore USS home `/z/z78651` quota full - `.zsh_history`, `~/.npm`, `~/.vscode-server`, `/z/z78651/work/workspace` fill up.

**Fix:**
```sh
# In ~/.profile add:
export HISTFILE=/dev/null
setopt noincappendhistory 2>/dev/null
setopt noappendhistory 2>/dev/null

# Clean
rm -rf ~/.npm ~/.zsh_history* ~/.vscode-server ~/.cache /z/z78651/work/workspace/*
mkdir -p /z/z78651/work/workspace/logs
rm -rf /z/z78651/work/dbb-zappbuild/img /z/z78651/work/dbb-zappbuild/samples /z/z78651/work/dbb-zappbuild/docs

# Verify
df -k /z | head -5  # need >5000 free 1K blocks
```

---

### 2. TASKLIB allocation fails - IGY.V6R4M0.SIGYCOMP NOT IN CATALOG

**Symptom:**
```
com.ibm.dbb.build.BuildException: BGZTK0016E An error occurred running BPXWDYN command 'alloc dd(TASKLIB) dsn(IGY.V6R4M0.SIGYCOMP) shr'.
IDC3012I ENTRY IGY.V6R4M0.SIGYCOMP NOT FOUND
```

**Root Cause:** Xplore does NOT catalog COBOL as `IGY.V6R4M0.SIGYCOMP`. USS install is `/usr/lpp/IBM/cobol/igyv6r4/`, MVS PDS is `IGY650.SIGYCOMP` short name.

**Discovery:**
```sh
tsocmd "LISTALC"  # Shows IGY650.SIGYCOMP
tsocmd "LISTCAT LEVEL(IGY)"  # Empty - not in user catalog
ls /usr/lpp/IBM/cobol/igyv6r4/bin/  # Shows cob2 wrapper
```

**Fix:** In `application-conf/Cobol.properties` and `datasets.properties`:
```properties
SIGYCOMP_V6=IGY650.SIGYCOMP
SIGYCOMP_V4=IGY650.SIGYCOMP
SDFHCOB=IGY650.SIGYCOMP
```

---

### 3. Binder allocation fails - CBC.V2R4M0.SCEELKED NOT IN CATALOG

**Symptom:**
```
BGZTK0016E An error occurred running BPXWDYN command 'alloc dd(TMP00002) dsn(CBC.V2R4M0.SCEELKED) shr'.
```

**Root Cause:** Binder PDS not `CBC.V2R4M0.SCEELKED` on Xplore.

**Discovery:**
```sh
tsocmd "LISTALC" | grep SCEELKED  # Shows nothing, but LISTCAT LEVEL(CEE) shows it
tsocmd "LISTCAT LEVEL(CEE)" | grep LKED
# NONVSAM ------- CEE.SCEELKED
```

**Fix:**
```properties
SCEELKED=CEE.SCEELKED
SCEELKEX=CEE.SCEELKED
```

Binder is in LINKLIST too, but DBB requires property.

---

### 4. Copybook ACCTREC not found - resolved: false

**Symptom:**
```
*** Physical dependencies: ACCTREC resolved: false
IGYLI0048-S The member "ACCTREC" was not found in the "COPY" library.
Return code 12
```

**Root Cause 1:** `cobol_dependencySearch=${copybookSearch}${objectSearch}` where `${objectSearch}` is undefined -> literal string `${objectSearch}` appended to search path, breaking resolver.

**Log shows:**
```
Resolution rules: search:/z/.../copybook/*.cpy${objectSearch}  <- literal not expanded
```

**Fix:**
```properties
# Cobol.properties
cobol_dependencySearch=${copybookSearch}

# application.properties
copybookSearch=search:${workspace}/?path=${application}/copybook/*.cpy
objectSearch=   # define as empty
```

**Root Cause 2:** `zapp.yaml` missing copybook in `additionalDependencies` -> Full Upload doesn't push copybook to USS.

**Fix:** `zapp.yaml`:
```yaml
additionalDependencies:
  - "copybook/ACCTREC.cpy"
  - "application-conf/Cobol.properties"
  # ...
```

---

### 5. LOAD dataset PDSE vs PDS - IEWBLINK dir must be 0

**Symptom:**
```
IEWBLINK failed, dir must be 0 for PDSE
or
Load module allocation failed
```

**Root Cause:** Xplore ACS rule: HLQ `Z78651.BUILD.LOAD` must be PDSE (LIBRARY), but COBOL/COPY/OBJ must be PDS. Default `cyl space(1,1) dsorg(PO) recfm(U) blksize(32760) dsntype(library)` for LOAD is PDSE, but if set to PDS with dir, binder fails. If set to PDS for all, ACS may force PDSE.

**Fix:** Hybrid model:

```properties
# datasets.properties
cobol_srcDatasets=Z78651.BUILD.COBOL,Z78651.BUILD.COPY,Z78651.BUILD.OBJ,Z78651.BUILD.DBRM  # PDS
cobol_srcOptions=tracks space(1,1) lrecl(80) dsorg(PO) recfm(F,B) dir(5)  # PDS, no dsntype
cobol_loadOptions=tracks space(1,5) dsorg(PO) recfm(U) blksize(32760) dir(5) dsntype(library)  # PDSE LIBRARY
```

- COBOL, COPY, OBJ, DBRM: PDS `dir(5)`
- LOAD: PDSE LIBRARY `dsntype(library) dir(5)` (dir ignored for PDSE but required)

---

### 6. BMS COPY PDS not found

**Symptom:**
```
alloc dd(TMP00001) dsn(Z78651.BMS.COPY) shr failed
```

**Root Cause:** Default `cobol_BMS_PDS=Z78651.BMS.COPY` (team-level) doesn't exist.

**Fix:**
```properties
cobol_BMS_PDS=Z78651.BUILD.COPY
```

---

### 7. 0 files built - No matched files

**Symptom:**
```
Step 5 Additional Dependencies No matched files found, copybooks 0, BuildReport totalFiles 0
```

**Root Causes:**

1. Windows path with spaces/brackets: `d:\[1]. DEVOPS\...` breaks glob matcher. Use `D:\mf\...` no spaces/brackets.
2. `file.properties` wrong: Must map `cobol=cobol/*.cbl` and `copybook=copybook/*.cpy`
3. Missing `.gitattributes` encoding: COBOL must be `ibm-1047` for USS `chtag`
4. Did not run **Full Upload** first time - dependency cache not seeded in USS workspace

**Fix:** 
- First build ALWAYS `Run IBM User Build with Full Upload`
- Subsequent edits: `Run IBM User Build` (incremental)

---

### 8. BuildReport.html not downloading

**Symptom:** No `.log` files in `logs/`, `BuildReport.html` missing.

**Root Cause:** DBB 2.0.2.7 writes logs to `/z/.../logs/*.log` only if compile runs. If scanner fails (dependency resolution), no .log created.

**Fix:** Check USS directly:
```sh
ls /z/z78651/work/workspace/logs/
cat /z/z78651/work/workspace/logs/BuildReport.json
```

---

### 9. Secrets committed - zowe.config.user.json with password

**Symptom:** `zowe.config.user.json` contains password and is committed.

**Fix (if not pushed):**
```sh
git rm --cached zowe.config.user.json zowe.schema.json logs/ACCTBALA.log .vscode/settings.json
# Add to .gitignore
# .vscode/settings.json
# zowe.config.user.json
# zowe.schema.json
# logs/
git add .gitignore
git commit --amend
```

**Fix (if pushed):** Rotate Xplore password immediately + `git filter-repo --invert-paths --path zowe.config.user.json --force` + force push.

**Secure alternative:**
```sh
zowe config set "profiles.zosmf.properties.user" "z78651" --user-config
zowe config set "profiles.zosmf.properties.password" "NEW_PASS" --user-config --secure
# Stores in OS credential vault, not file
```

---

## User Build Sequence - Final (Phase 1)

1. **Pristine workspace:**
   ```sh
   rm -rf /z/z78651/work/workspace/* && mkdir -p /z/z78651/work/workspace/logs
   ```

2. **Validate:**
   - `~/.profile` has `HISTFILE=/dev/null`
   - `zapp.yaml` has `copybook/ACCTREC.cpy` in `additionalDependencies`
   - `application-conf/Cobol.properties` has `IGY650.SIGYCOMP` and `CEE.SCEELKED`
   - `application-conf/application.properties` has `objectSearch=` empty

3. **First run:** `Z Open Editor: Run IBM User Build with Full Upload` on `cobol/ACCTBALA.cbl`

4. **Verify:**
   - `logs/ACCTBALA.log` RC 0 or 4
   - `logs/BuildReport.json` totalFiles=1, Build State CLEAN
   - Resolution rules: `search:/z/.../copybook/*.cpy` (no `${objectSearch}` suffix)
   - Physical dependencies: `ACCTREC resolved: true`

5. **Incremental:** Edit file -> `Run IBM User Build` (normal, not Full Upload) -> <5 sec

---

## Diagnostics Commands

```sh
# Compiler PDS
tsocmd "LISTALC"
tsocmd "LISTCAT LEVEL(CEE)" | grep -E "LKED|RUN"
tsocmd "LISTCAT LEVEL(IGY)"

# USS COBOL install
ls /usr/lpp/IBM/cobol/igyv6r4/bin/
 /usr/lpp/IBM/cobol/igyv6r4/bin/cob2 --help | head -20

# Workspace
ls /z/z78651/work/workspace/logs/
cat /z/z78651/work/workspace/logs/ACCTBALA.log | grep -E "ACCTREC|RC|IGYLI"

# DBB
cat /z/z78651/work/dbb-zappbuild/build-conf/Cobol.properties | grep required
```

---

## Phase 1 Complete Checklist

- [x] IGY650.SIGYCOMP from LISTALC (not V6R4M0)
- [x] CEE.SCEELKED from LISTCAT LEVEL(CEE)
- [x] cobol_dependencySearch=${copybookSearch} (no objectSearch)
- [x] Hybrid PDS/PDSE for BUILD datasets
- [x] cobol_BMS_PDS=Z78651.BUILD.COPY
- [x] zapp.yaml includes copybook
- [x] .gitignore for secrets
- [x] Build State CLEAN, 1 file, 10.5s
- [x] GitHub repo pushed, secrets purged
