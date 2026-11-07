# RUNBOOK - DBB User Build + CI/CD + Wazi Deploy

> Triage guide for IBM Z Xplore (Z78651), z/OS 3.1, DBB 2.0.2.7 + Wazi Deploy 3.0.0 + JFrog Artifactory.
> Phase 1 = DBB User Build in VS Code. Phase 2/3 = GitHub Actions CI/CD.

---

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
Z78651.TEST.LOAD (PDSE LIBRARY, promotion target)
Z78651.PROD.LOAD (PDSE LIBRARY, promotion target)
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

**Root Cause 2:** `zapp.yaml` missing copybook in `additionalDependencies` -> Full Upload does not push copybook to USS.

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

**Root Cause:** Default `cobol_BMS_PDS=Z78651.BMS.COPY` (team-level) does not exist.

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

---

## Triage Guide - Phase 2/3 Issues Solved

### INC-10. Shell Execution - Positional Argument Dropping in SSH

**Symptom:**
```
-c: error: unrecognized arguments: wazideploy-package
```
Or silently dropped `-dm` / `-dp` parameters.

**Root Cause:** Standard UNIX shell aliases are not expanded in non-interactive, non-login headless shells (GitHub Actions via `appleboy/ssh-action`). Zsh array slicing in interactive shells collides with argument passing in headless shells.

**Fix:** Do NOT use `alias wazideploy-package=...` in `~/.profile`. Use POSIX shell functions or direct Python module invocation in the workflow:

```sh
# In workflow, not in ~/.profile:
python3 -c "
from wazideploy.util.wd import main
import sys
sys.argv = ['wazideploy-deploy', '-dm', '/tmp/wazi-deploy-dev/deployment_method.yaml', '-m', '/tmp/wazi-deploy-dev/app_manifest.yaml', '-dp', '/tmp/wazi-deploy-dev/deployment_plan.yaml']
main()
"
```

**Prevention:** Never rely on interactive aliases in CI. Every command in `appleboy/ssh-action` must be self-contained.

---

### INC-11. Python bad magic number / Module Mismatch - ANTI-PATTERN, DO NOT USE

**Symptom:**
```
ImportError: bad magic number in 'wazideploy'
ModuleNotFoundError: No module named 'attr'
```

**What was tried (WRONG PATTERN - DO NOT USE):**
Uploading wheels `attrs-26.1.0`, `jsonschema-4.17.3`, `pyrsistent-0.20.0`, `Whoosh-2.7.4` to `~/wheels/` and extracting them to `~/.local/lib/python3.9/site-packages/` with `_BPXK_AUTOCVT=ON`. Auto-conversion treated `.pyc` binaries as text, corrupting them with `

`. A `git reset --hard` also purged untracked dependency dirs.

Xplore is a shared educational LPAR with no `pypi.org` access. Adding custom packages to `~/.local` conflicts with the managed environment in `/usr/lpp/` and violates LPAR usage policy. Do not use this pattern.

**Correct fix - Use official dependencies only:****
```sh
# DO NOT create ~/wheels/, DO NOT extract to ~/.local/
# Use only:
ls /usr/lpp/IBM/gdp/dependencies/
# Wazi Deploy 3.0.0 in /usr/lpp/IBM/gdp/
export PYTHONPATH=/usr/lpp/IBM/gdp/dependencies:$PYTHONPATH
```

**Cleanup if you ever did the wrong pattern:**
```sh
rm -rf ~/wheels/
rm -rf ~/.local/lib/python3.9/site-packages/attrs* ~/.local/lib/python3.9/site-packages/jsonschema* ~/.local/lib/python3.9/site-packages/pyrsistent* ~/.local/lib/python3.9/site-packages/whoosh* ~/.local/lib/python3.9/site-packages/wazideploy*
```

**Lesson:** On a multi-tenant educational LPAR, installing custom packages is a policy violation, not a technical fix. Document it as a lesson, never as a recommended step.

---

### INC-12. PyYAML Parser Failure - Control-Z (\x1a)

**Symptom:**
```
yaml.reader.ReaderError: unacceptable character #x001a: special characters are not allowed
```

**Root Cause:** Python manifest generator used multi-line `f"""..."""` strings. During file compilation on the mainframe filesystem, a hidden Control-Z (`\x1a`) End-of-File byte was appended to the text stream. PyYAML rejects it.

**Fix:** Sanitize in Python before writing to disk, in the workflow:

```python
with open('wazi-deploy/app_manifest.yaml', 'r', encoding='utf-8') as f:
    text = f.read().replace('\x1a', '')
with open('/tmp/wazi-deploy/app_manifest.yaml', 'w', encoding='iso-8859-1', errors='ignore') as f:
    f.write(text)
```

**Prevention:** Never use `iconv -f UTF-8 -t ISO8859-1` alone on a file that may contain `\x1a`. Always scrub in Python first.

---

### INC-13. Unicode Transcoding Collision - latin-1 Codec Crash

**Symptom:**
```
UnicodeEncodeError: 'latin-1' codec can't encode character '\U0001f447' in position 562
```
`\U0001f447` is the down-arrow emoji.

**Root Cause:** Template files (`deployment_method.j2`, `deployment_method.yaml`, `README.md`) contained decorative emojis in comments / descriptions. Wazi Deploy mandates single-byte `iso-8859-1` / `latin-1`. Emojis are multi-byte and crash the encoder. A second cause is copy-paste from a rendered page that inserts `¦` (U+00A6, byte 0xa6) from entity tags - that byte alone is invalid UTF-8.

**Fix:**
- Remove all emojis from YAML, JCL, and workflow `echo` lines. Use plain ASCII only.
- In Python, write with `errors='ignore'` to drop unmappable symbols:
```python
with open('/tmp/wazi-deploy/deployment_method.yaml', 'w', encoding='iso-8859-1', errors='ignore') as f:
    f.write(clean_method)
```
- If a file shows `0xa6` on `od -c`, regenerate it as plain ASCII, do not copy-paste from a rendered page.

---

### INC-14. Wazi Deploy Schema Violation - `*** No item found` - Root Cause: `is_artifact` + `types`

**Symptom:**
```
** Collecting items for Deploy COBOL Artifacts/Deploy LOAD Modules/Deploy LOAD Module
*** No item found
```
`deployment_plan.yaml` has `artifacts: []` - empty, even though `app_manifest.yaml` lists ACCTBALA.

**What was tried first (WRONG):**
```yaml
# Legacy templates - rejected by Wazi 3.0 strict schema
selector: {type: LOAD}   # at action level - invalid
selectors:               # at step level - also invalid for this install
  - type: LOAD
```
Error:
```
Additional properties are not allowed ('selector' was unexpected) - Path: $.activities[0].actions[0]
```

**Root Cause - Found by reading the on-system JSON schema:**
The Wazi Deploy JSON schema files on z/OS define the structural model for `DeploymentMethod`. In that schema:
- `selector` / `selectors` / `type` do NOT exist at Activity, Action, or Step nodes.
- Artifact binding is driven by `is_artifact` (boolean) and `types` (array) at the **Activity** level.
- By default `is_artifact` evaluates to `false`. The package engine then treats the method as a generic setup task (clear folder, allocate dataset) and skips `app_manifest.yaml` entirely - hence `*** No item found`.

**Fix - Schema-validated `deployment_method.yaml`:**
```yaml
apiVersion: wazideploy.ibm.com/v1
kind: DeploymentMethod
metadata:
  name: core-banking-deploy-method
  version: 1.0.0
  description: Core Banking Platform - Generic deployment for any COBOL LOADs - Application-level, not per-program
activities:
  - name: Deploy COBOL Artifacts
    description: Deploy all COBOL LOAD modules from ApplicationManifest
    is_artifact: true
    types:
      - name: LOAD
    actions:
      - name: Deploy LOAD Modules
        description: Generic action that deploys any LOAD from manifest - handles N programs
        steps:
          - name: Deploy LOAD Module
            description: Deploy single LOAD - template handles any program dynamically
            properties:
              - key: template
                value: |
                  echo "Deploying {{name}} (Type: {{type}})"
                  echo "Source: {{dataset}}({{member}})"
                  echo "Build: {{version}}"
```

**Verification - GREEN:**
```
** Collecting items for Deploy COBOL Artifacts/Deploy LOAD Modules/Deploy LOAD Module
*** 1 item found [ACCTBALA.LOAD]
```
In `deployment_plan.yaml`:
```yaml
artifacts:
  - name: ACCTBALA
    type: LOAD
    hash: hash_acctbala_1c348d9
```

**Prevention:**
- Validate `apiVersion: wazideploy.ibm.com/v1` - no space after the dot, no `://` typo. The string `apiVersion: ://ibm.com` in some drafts is invalid.
- Do NOT use `selector` / `selectors` on this install. Use `is_artifact: true` + `types: [{name: LOAD}]` at Activity level.
- Do NOT copy a `deploy.yml` snippet that sets `PYTHONPATH=$HOME/.local/...` or `_BPXK_AUTOCVT=ON` - that is the forbidden `~/.local` pattern. Use only `/usr/lpp/IBM/gdp/dependencies/`.

### INC-15. Cross-Partition Promotion - MVS Allocation Mismatches

**Symptom:**
```
IKJ56701I MISSING INPUT DDNAME
BPXF101E RETURN CODE 00000004 RECEIVED DURING PARSING OF THE COMMAND
```
Smoke test fails - member missing from target library.

**Root Cause:** `OCOPY` / `OEXEC` are designed to copy between MVS PDS/PDSE and USS filesystem. They cannot copy directly MVS-to-MVS. They expect a pre-allocated DDNAME via JCL, not a raw dataset string. Also, `Z78651.TEST.LOAD` and `Z78651.PROD.LOAD` do not exist by default on Xplore - any copy before allocation returns a catalog failure.

**Fix:** Two-stage promotion in `deploy.yml`:

1. **Dynamic allocation (idempotent):**
```sh
tsocmd "ALLOC DD(TESTLOAD) DSN('Z78651.TEST.LOAD') TRACKS SPACE(1,5) DSNTYPE(LIBRARY) RECFM(U) BLKSIZE(32760) NEW CATALOG" || echo "Dataset may already exist - continuing"
```

2. **USS filesystem copy bridge (MVS-to-MVS):**
```sh
cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"
```

**Verified outcome:**
```
=== Step 1: Allocating Isolated TEST Staging Partition ===
=== Step 2: Executing Package Promotion to TEST ===
=== Step 3: Running Post-Deployment TEST Smoke Tests ===
TEST promotion verified successful. Binary isolated inside Z78651.TEST.LOAD.
```

**Note on TEST duplicate:** If TEST already exists, `ALLOC` returns `IGD17001I DUPLICATE DATA SET NAME ON VOLUME ZXPM03`. That is expected, not a failure. Handle as `|| echo "continuing"`. For PROD, the dataset usually does not exist yet, so `ALLOC` creates and catalogs it dynamically.

---

### INC-16. workflow_run Never Triggers - Special Characters in Workflow Names

**Symptom:** `DBB Build` goes GREEN on merge, but `Package and Publish` never triggers. Same for `Deploy`.

**Root Cause:** GitHub `workflow_run` does not reliably match workflow names containing `(`, `)`, `+`, `->`. The project used:
- `DBB Build - Production Grade (Incremental + SonarQube + ZUnit)` - never triggered CD
- `Package + Publish - Production (BuildReport.json -> Wazi + JFrog)` - never triggered Deploy

Copying the job name (`DBB User Build`) instead of the workflow name also fails. `workflow_run.workflows` must contain the workflow `name:` at the top of the file, not a job name.

**Fix:** Use simple names only:
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

**Verification:** After renaming, the chain triggers on the next merge. For the first run after a rename, manually run `Package and Publish` via `workflow_dispatch` to unblock, then auto-trigger works on the next DBB Build.

**Prevention:** Never use `(`, `+`, `->`, `/` in a workflow `name:` that is referenced by `workflow_run`.

---

### INC-17. JFrog vs GitHub Artifacts - Deploy Downloaded from Wrong Store

**Symptom:** Package uploads to JFrog, but Deploy downloads from GitHub Artifacts. A reviewer asks: "Why does CD trust temporary storage instead of the immutable release?"

**Root Cause:** Early `deploy.yml` used `actions/download-artifact@v4` with `name: core-banking-app-deployable`. That is a 30-day debug cache, not an immutable release. If GitHub deletes it, Deploy cannot reproduce the same version. If Package and Deploy use different versions, promotion is not auditable.

**Fix:** Deploy downloads the same immutable version from JFrog:

```sh
VER="1.0.${{ github.event.workflow_run.run_number || github.run_number }}"
curl -f -u "$JFROG_USER:$JFROG_TOKEN" -O "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/$VER/deployable.tar"
```

Keep the GitHub Artifact upload in Package as a debug copy only. Do not let Deploy consume it.

**Verification:** JFrog response for 1.0.120 shows `repo: mainframe-loads-local`, `path: /core-banking-app/1.0.120/deployable.tar`, `size: 10240`, `sha256: 20c66b2f...`. Deploy must log the same version and SHA.

---

### INC-18. ZUnit Tests - Stub, Not a Real Runner (Honest Status)

**Symptom:** Workflow reports `ZUnit 12 / 12 PASS`, but no real ZUnit harness runs on USS.

**Root Cause:** The current `zunit-tests` job in `dbb-build.yml` is a placeholder:
```sh
echo "ZUnit automated test runners completed successfully with zero transaction failures."
```
It does not run `groovyz ~/work/dbb-zappbuild/zunit.groovy`.

**Correct status:** Do NOT claim a real ZUnit harness until the runner is wired in. The honest summary is: "ZUnit job reports 12 / 12 (stub - to be replaced with real `zunit.groovy` runner)".

**Future fix (not yet done):**
```sh
/usr/lpp/IBM/dbb/bin/groovyz ~/work/dbb-zappbuild/zunit.groovy --workspace ~/work/workspace --hlq Z78651.BUILD
```

**Lesson:** A stub that reports PASS is worse than a job that says `SKIPPED - not implemented`. Future work must replace the stub.

---

### INC-19. Git Workspace Divergence on USS

**Symptom:**
```
fatal: 'origin' does not appear to be a git repository
```
Or: `git pull` fails because USS workspace has diverged commits.

**Root Cause:** USS workspace `/z/z78651/work/workspace/mainframe-modernization-platform` is a git clone that may have local commits / untracked files. `git pull` tries to merge and fails.

**Fix:** In every workflow, use fetch + hard reset, not pull:
```sh
cd ~/work/workspace
if [ ! -d "mainframe-modernization-platform/.git" ]; then
  git clone https://github.com/SwamyVaditya/mainframe-modernization-platform.git
  cd mainframe-modernization-platform
else
  cd mainframe-modernization-platform
  git fetch origin
  git reset --hard origin/main
fi
```

**Prevention:** Never commit on USS. USS is a build workspace, not a dev workspace. All commits happen on Windows / GitHub.

---

## Phase 2/3 Complete Checklist

- [x] Simple workflow names: `DBB Build`, `Package and Publish`, `Deploy`
- [x] Sequential `workflow_run` chain, gated on `conclusion == 'success'`
- [x] BuildReport.json downloaded from triggering run, not dummy
- [x] Manifest generated dynamically via `generate_manifest.py`, not hardcoded
- [x] Wazi Deploy package: `*** 1 item found [ACCTBALA.LOAD]`
- [x] JFrog publish: `mainframe-loads-local/core-banking-app/<version>/deployable.tar`, SHA256 recorded
- [x] Deploy downloads same version from JFrog, not GitHub Artifacts
- [x] DEV auto, TEST / PROD approval, smoke test `LISTDS`, rollback on failure
- [x] Promotion: ALLOC + `cp "//'...'"` bridge, TEST duplicate handled, PROD dynamic catalog
- [x] No emojis in YAML, no `~/wheels/` / `~/.local` installs, official deps only
- [ ] ZUnit real runner - STUB, see INC-18, future work

---

## Diagnostics - Phase 2/3

```sh
# Check workflow names
grep "^name:" .github/workflows/*.yml

# Check JFrog version
curl -u "$JFROG_USER:$JFROG_TOKEN" "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/1.0.120/deployable.tar" -I

# Check Wazi Deploy
ls /usr/lpp/IBM/gdp/
ls /usr/lpp/IBM/gdp/dependencies/

# Check USS workspace
ls ~/work/workspace/mainframe-modernization-platform/BuildReport.json
cat ~/work/workspace/mainframe-modernization-platform/BuildReport.json

# Check promotion
tsocmd "LISTDS 'Z78651.BUILD.LOAD' MEMBERS"
tsocmd "LISTDS 'Z78651.TEST.LOAD' MEMBERS"
tsocmd "LISTDS 'Z78651.PROD.LOAD' MEMBERS"
```
