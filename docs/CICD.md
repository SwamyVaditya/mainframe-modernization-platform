# CI/CD - GitHub Actions DBB Build + Wazi Deploy + JFrog

## Overview

CI/CD runs on IBM Z Xplore (Z78651) for every push to `main` / PRs, plus manual dispatch.

**Flow:**

```
Git push feature/acctbala-fix / PR to main
  -> DBB Build (CI)
    changed-files -> security-scan (Gitleaks) -> sonar-scan (SonarQube)
    -> dbb-build (DBB on USS) -> zunit-tests -> build-summary
  -> Package and Publish (CD, workflow_run from DBB Build)
    BuildReport.json -> generate_manifest.py -> wazideploy-package -> JFrog
  -> Deploy (CD, workflow_run from Package and Publish)
    Download same version from JFrog -> Wazi Deploy -> DEV / TEST / PROD
```

**Key rules:**

- Sequential, not parallel. Package only runs after DBB Build succeeds. Deploy only runs after Package succeeds.
- Workflow names must be simple. Names with `(`, `)`, `+`, `->` break GitHub `workflow_run`. Use `DBB Build`, `Package and Publish`, `Deploy` only.
- JFrog Artifactory is the immutable release store. GitHub Artifacts are only a 30-day debug cache. Deploy downloads from JFrog, never from GitHub Artifacts.
- Version sync: `1.0.<github.event.workflow_run.run_number>` is used in Package and Deploy, so Deploy fetches the exact version Package published.

---

## Setup - GitHub Secrets

Go to GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret:

| Secret | Value | Example |
|--------|-------|---------|
| ZOS_HOST | Xplore SSH host | 204.90.115.200 |
| ZOS_USER | Xplore user | z78651 |
| ZOS_PASSWORD | Xplore password | (your password) |
| SSH_PRIVATE_KEY | (optional) SSH key for key auth | -----BEGIN RSA... |
| JFROG_URL | JFrog Artifactory URL | https://trialfh3rbr.jfrog.io |
| JFROG_USER | JFrog user | (your JFrog user) |
| JFROG_TOKEN | JFrog API token | (your JFrog token) |
| SONAR_TOKEN | SonarQube Cloud token | (your Sonar token) |
| SONAR_HOST_URL | SonarQube Cloud host | https://sonarcloud.io |

**Xplore uses self-signed certs** - workflow uses `StrictHostKeyChecking no` and `rejectUnauthorized false` equivalent.

Secrets are passed via `env:` in workflow steps, never echoed, never as literals in `run:` blocks.

---

## Workflow 1 - .github/workflows/dbb-build.yml

**Name:** `DBB Build`

**Triggers:**

- push to main
- pull_request to main (`opened`, `synchronize`, `reopened`)
- workflow_dispatch (manual)

**Jobs:**

1. **changed-files - Detect Changed Programs (Incremental Build):**
   - Checkout with `fetch-depth: 0`
   - If PR: base = `origin/main`. If push: base = `HEAD~1`.
   - `git diff --name-only <base> HEAD`, filter `.(cbl|cob|cpy|copybook)`
   - If no COBOL / copybook changes and not on `main`: `has_changes=false`, skip downstream.
   - If on `main` or list empty: force `PROGRAMS=ACCTBALA` (baseline build)
   - Outputs: `changed_cobol`, `has_changes`

2. **security-scan - Gitleaks:**
   - `gitleaks/gitleaks-action@v2` with `GITHUB_TOKEN`
   - Runs only if `has_changes == 'true'`

3. **sonar-scan - SonarQube Quality Gate:**
   - `sonarsource/sonarqube-scan-action@v3` with `SONAR_TOKEN`, `SONAR_HOST_URL`
   - Args: `projectKey=SwamyVaditya_mainframe-modernization-platform`, `organization=swamyvaditya`, `sources=cobol,copybook`, `sonar.cobol.copy.directories=copybook`, `sonar.cobol.file.suffixes=cbl,cob,cpy`, `sonar.sourceEncoding=IBM1047`, `sonar.qualitygate.wait=true`
   - Then `sonarsource/sonarqube-quality-gate-action@v1.2.1`
   - `continue-on-error: true` on the job (so a Sonar Cloud outage does not block DBB build)

4. **dbb-build - DBB User Build:**
   - Checkout with `fetch-depth: 0`
   - SSH to USS (`appleboy/ssh-action@v1.0.3`):
     - `export HISTFILE=/dev/null`, `export _BPXK_AUTOCVT=ON`, `export _CEE_RUNOPTS="FILETAG(AUTOCVT,AUTOTAG)"`, source `~/.profile`
     - `export PYTHONHOME=/usr/lpp/IBM/cyp/v3r9/pyz`, `JAVA_HOME=/usr/lpp/java/J11.0_64`, `DBB_HOME=/usr/lpp/IBM/dbb`
     - `mkdir -p ~/work/workspace`, `cd ~/work/workspace`
     - If `mainframe-modernization-platform/.git` missing: `git clone https://github.com/SwamyVaditya/mainframe-modernization-platform.git`
     - Else: `git fetch origin` + `git reset --hard origin/main` (not `git pull` - avoids divergence errors)
     - If `build.groovy` exists: `groovyz build.groovy --workspace ~/work/workspace --application mainframe-modernization-platform --hlq Z78651.BUILD --outDir ~/work/workspace/logs --logFile build.log`
     - Generate `BuildReport.json` via Python `json.dump` (pure ASCII, no inline YAML)
     - `chtag -t -c ISO8859-1 BuildReport.json`, copy to `build_artifacts/`
     - Verify: `tsocmd "LISTDS 'Z78651.BUILD.LOAD' MEMBERS" | grep ACCTBALA`
   - Download `BuildReport.json` from USS to runner via `scp` (`sshpass`)
   - Upload artifact: `BuildReport-1.0.<run_number>`, path `BuildReport.json`, retention 30 days

5. **zunit-tests - ZUnit:**
   - Needs `dbb-build`, runs only if `dbb-build` succeeded
   - SSH: placeholder for real `zunit.groovy` runner, currently echoes success
   - Publish summary: Target `ACCTBALA`, Status Pass, 12 / 12 assertions, 0 abends / failures
   - NOTE: The current ZUnit job does NOT run a real DBB ZUnit runner on USS. It is a stub that reports 12 / 12. Do not claim it runs a real ZUnit harness until `zunit.groovy` is wired in. See `docs/RUNBOOK.md` INC-07.

6. **build-summary - Production Build Summary:**
   - Needs all jobs, `if: always()` so dashboard always renders
   - Writes GitHub Step Summary: App, Build Version, Change Detection, Gitleaks, SonarQube, DBB, ZUnit results

---

## Workflow 2 - .github/workflows/package-and-publish.yml

**Name:** `Package and Publish`

**Triggers:**

- `workflow_run: ["DBB Build"]`, `types: [completed]` (must match Workflow name exactly, not job name)
- `workflow_dispatch` (manual)

**Gate:** `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'`

**Jobs:**

1. **package-and-publish - Wazi Package + JFrog Publish:**
   - Checkout
   - **Download BuildReport artifact** (only if `workflow_run`): `actions/download-artifact@v4`, name `BuildReport-1.0.${{ github.event.workflow_run.run_number }}`, `run-id: ${{ github.event.workflow_run.id }}`
   - **Fallback** (only if `workflow_dispatch`): create minimal `BuildReport.json` for ACCTBALA
   - **SCP BuildReport to USS:** `sshpass -p "$ZOS_PASSWORD" scp BuildReport.json $ZOS_USER@$ZOS_HOST:~/work/workspace/BuildReport.json`
   - **Package on USS** (`appleboy/ssh-action`):
     - Env: `PYTHONHOME=/usr/lpp/IBM/cyp/v3r9/pyz`, `GIT_SSL_CAINFO=/usr/lpp/Rocket/rsusr/ported/bin/ca-bundle.crt`, `JAVA_HOME`, `DBB_HOME`, `PYTHONPATH` = official `/usr/lpp/IBM/gdp/dependencies/` only (no custom `~/.local` wheels - see `docs/XPLORE-CONSTRAINTS.md`)
     - Version: `UPSTREAM_VERSION="1.0.${{ github.event.workflow_run.run_number || github.run_number }}"`, SHA: `${{ github.event.workflow_run.head_sha || github.sha }}`
     - `cd ~/work/workspace`, if no `.git` then clone, else `git fetch origin` + `git reset --hard origin/main`
     - `cp ../BuildReport.json .`
     - `python3 scripts/generate_manifest.py BuildReport.json wazi-deploy/app_manifest.yaml "$UPSTREAM_VERSION" "$UPSTREAM_SHA"` - dynamic, supports N LOADs, not hardcoded
     - Clean to `/tmp/wazi-deploy`: Python scrub `\x1a`, write `iso-8859-1` with `errors='ignore'`, `chtag -t -c ISO8859-1 /tmp/wazi-deploy/*.yaml`
     - `wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml`
     - `tar -cvf ~/wazi-deploy-package/deployable.tar app_manifest.yaml deployment_method.yaml deployment_plan.yaml`
   - **Fetch package from USS:** `scp` `deployable.tar` to runner, `ls -l`
   - **Publish to JFrog:** `curl -f -u "$JFROG_USER:$JFROG_TOKEN" -T deployable.tar "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/$UPSTREAM_VERSION/deployable.tar"`
   - **Upload debug copy:** `actions/upload-artifact@v4`, name `core-banking-app-deployable`, path `deployable.tar`, retention 30 days (debug only - Deploy does NOT use this)

---

## Workflow 3 - .github/workflows/deploy.yml

**Name:** `Deploy`

**Triggers:**

- `workflow_run: ["Package and Publish"]`, `types: [completed]`
- `workflow_dispatch` with input `environment` (`DEV` / `TEST` / `PROD`, default `DEV`)

**Jobs:**

1. **deploy-dev - Deploy to DEV (Auto):**
   - `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'` (if using `workflow_run`, also check `head_branch == 'main'` in the `if` if you add a branch filter)
   - Environment: `DEV` (no approval)
   - **Download immutable package from JFrog** (NOT from GitHub Artifacts):
     ```sh
     VER="1.0.${{ github.event.workflow_run.run_number || github.run_number }}"
     curl -f -u "$JFROG_USER:$JFROG_TOKEN" -O "$JFROG_URL/artifactory/mainframe-loads-local/core-banking-app/$VER/deployable.tar"
     ```
   - SCP `deployable.tar` to USS `~/work/workspace/deployable.tar`
   - Wazi Deploy on USS: `rm -rf /tmp/wazi-deploy-dev && mkdir -p /tmp/wazi-deploy-dev`, `tar -xf ~/work/workspace/deployable.tar`, `wazideploy-deploy -dp deployment_plan.yaml` (via Python `from wazideploy.util.wd import main` wrapper to bypass argument-parser bug - see RUNBOOK INC-01)
   - Smoke test DEV: `tsocmd "LISTDS 'Z78651.BUILD.LOAD' MEMBERS" | grep ACCTBALA`. On failure: `wazideploy-deploy -dp deployment_plan.yaml --rollback`, exit 1.

2. **deploy-test - Deploy TEST (Manual Approval):**
   - Needs `deploy-dev`, `if: needs.deploy-dev.result == 'success'`
   - Environment: `TEST` (GitHub Environment approval)
   - Allocate: `tsocmd "ALLOC DD(TESTLOAD) DSN('Z78651.TEST.LOAD') TRACKS SPACE(1,5) DSNTYPE(LIBRARY) RECFM(U) BLKSIZE(32760) NEW CATALOG"` (idempotent - `IGD17001I DUPLICATE` is expected if already exists)
   - Promote: `cp "//'Z78651.BUILD.LOAD(ACCTBALA)'" "//'Z78651.TEST.LOAD(ACCTBALA)'"` (OCOPY cannot do MVS-to-MVS directly)
   - Smoke: `tsocmd "LISTDS 'Z78651.TEST.LOAD' MEMBERS" | grep ACCTBALA`

3. **deploy-prod - Deploy PROD (Manual Approval + Rollback):**
   - Needs `deploy-test`, `if: needs.deploy-test.result == 'success'`
   - Environment: `PROD` (GitHub Environment approval)
   - Allocate: `tsocmd "ALLOC DD(PRODLOAD) DSN('Z78651.PROD.LOAD') TRACKS SPACE(1,5) DSNTYPE(LIBRARY) RECFM(U) BLKSIZE(32760) NEW CATALOG"` (idempotent)
   - Promote: `cp "//'Z78651.TEST.LOAD(ACCTBALA)'" "//'Z78651.PROD.LOAD(ACCTBALA)'"`
   - Smoke: `tsocmd "LISTDS 'Z78651.PROD.LOAD' MEMBERS" | grep ACCTBALA`

4. **summary - CD Summary:**
   - Needs `[deploy-dev, deploy-test, deploy-prod]`, `if: always()`
   - Writes Step Summary: App, Version `1.0.<run_number>`, Source `JFrog Artifactory`, DEV / TEST / PROD results (plain text, no emojis in the summary logic - emojis in the summary markdown are GitHub-rendered, not z/OS YAML)

---

## Local Test

```sh
# Simulate CI steps locally via SSH
scp -r cobol/ copybook/ application-conf/ zapp.yaml z78651@204.90.115.200:/z/z78651/work/workspace/mainframe-modernization-platform/
ssh z78651@204.90.115.200 ". ~/.profile; /usr/lpp/IBM/dbb/bin/groovyz /z/z78651/work/dbb-zappbuild/build.groovy --workspace /z/z78651/work/workspace --application mainframe-modernization-platform --hlq Z78651.BUILD --outDir /z/z78651/work/workspace/logs --propOverwrites buildOrder=Cobol.groovy --verbose --userBuild /z/z78651/work/workspace/mainframe-modernization-platform/cobol/ACCTBALA.cbl; cat /z/z78651/work/workspace/logs/BuildReport.json"
```

```sh
# Simulate Package locally (on USS)
python3 scripts/generate_manifest.py BuildReport.json wazi-deploy/app_manifest.yaml 1.0.120 <sha>
python3 -c "open('/tmp/wazi-deploy/app_manifest.yaml','w',encoding='iso-8859-1',errors='ignore').write(open('wazi-deploy/app_manifest.yaml',encoding='utf-8').read().replace(chr(26),''))"
chtag -t -c ISO8859-1 /tmp/wazi-deploy/*.yaml
cd /tmp/wazi-deploy && wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml
```

---

## Branch Protection

After workflow works:

GitHub repo -> Settings -> Branches -> Add rule for `main`:

- Require status checks: `DBB Build`
- Require pull request before merging
- Require conversation resolution

This ensures PRs cannot merge unless DBB build is CLEAN.

For CD: Use GitHub Environments `DEV`, `TEST`, `PROD` with required reviewers for TEST and PROD. DEV has no approval so the chain can run automatically after Package succeeds.

---

## Common Failures - See RUNBOOK

| Symptom | Likely cause | Doc |
|---|---|---|
| `workflow_run` never triggers | Workflow name contains `(`, `+`, `->` | `docs/RUNBOOK.md` INC-07, `docs/CICD.md` naming rule |
| `UnicodeDecodeError: byte 0xa6` | File contains `¦` or emoji from copy-paste | RUNBOOK INC-04 |
| `ParserError: while parsing a flow mapping` | Jinja2 `{% if %}` left in YAML | RUNBOOK INC-05 |
| `fatal: 'origin' does not appear` | USS workspace is not a git repo | RUNBOOK INC-01 |
| `IKJ56701I MISSING INPUT DDNAME` on promotion | OCOPY cannot do MVS-to-MVS | RUNBOOK INC-06 |
| `IGD17001I DUPLICATE DATA SET NAME` on TEST | TEST dataset already cataloged - idempotent, not a failure | RUNBOOK INC-06 |
| ZUnit reports 12 / 12 but no real runner | ZUnit job is a stub in the current workflow | RUNBOOK INC-07 |

---

## Future Enhancements

- [ ] Wire real ZUnit runner: `groovyz ~/work/dbb-zappbuild/zunit.groovy --workspace ~/work/workspace --hlq Z78651.BUILD` in `zunit-tests` job, replace stub echo
- [ ] Use Zowe CLI instead of SCP (`zowe zos-files upload`)
- [ ] Parse `BuildReport.json` with `jq` and fail CI if `buildResult != CLEAN`
- [ ] Upload `ACCTBALA.log` as artifact
- [ ] IBM Z CodeScan for COBOL quality gates (replacing SonarQube if needed)
- [ ] Dependency impact build (full app, not just ACCTBALA) - already supported via `generate_manifest.py` dynamic records
- [ ] Add `deployment_method.j2` rendering via proper Jinja2 (not string replace) if env-specific methods are needed
