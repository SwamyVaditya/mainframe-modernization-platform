# Wazi Deploy - Application-Level Deployment

> Wazi Deploy 3.0.0 on IBM Z Xplore (z/OS 3.1). Wazi Deploy was available on Xplore during the project window. This doc describes the complete, verified configuration for reproduction on an enterprise LPAR.

## Overview

Application-level deployment using Wazi Deploy with dynamic manifests, not per-program hardcoded files.

One generic `deployment_method.yaml` deploys any LOAD from the manifest. The manifest is generated dynamically from DBB `BuildReport.json` in the pipeline.

## Files

- `deployment_method.yaml` - Generic deployment method (used in pipeline, application-level)
- `deployment_method.j2` - Jinja2 template for environment-specific methods (future only, not used in current pipeline)
- `app_manifest.yaml` - Generated dynamically from `BuildReport.json` in the pipeline. **Not committed.** See below.
- `README.md` - This file

```
wazi-deploy/
├── deployment_method.yaml      # Generic, application-level, used in pipeline
├── deployment_method.j2        # Template for future env-specific methods
└── README.md                   # Documentation
```

**`app_manifest.yaml` is NOT committed - it is generated dynamically in the pipeline from `BuildReport.json`.**

## 1. BuildReport.json -> ApplicationManifest (Dynamic, Not Hardcoded)

**Problem with hardcoded manifests:** A manifest that lists only `ACCTBALA` works for 1 program only.

**This project:** Dynamic from DBB `BuildReport.json` - supports N programs.

```bash
# DBB Build generates BuildReport.json with all built LOADs
# scripts/generate_manifest.py parses it and generates ApplicationManifest
python3 scripts/generate_manifest.py BuildReport.json wazi-deploy/app_manifest.yaml 1.0.123 abc123

# Result: ApplicationManifest contains ALL LOADs from build, not just ACCTBALA
# Example: If build builds ACCTBALA, ACCTDEP, ACCTWDR, manifest has all 3
```

## 2. Generic DeploymentMethod (Application-Level)

**File:** `deployment_method.yaml` - Generic, not per-program

**Pattern:** One method deploys ANY LOAD from manifest via template `{{name}}`, `{{dataset}}`, `{{member}}`

**No hardcoded ACCTBALA** - works for any program from `BuildReport.json`

## 3. Schema-Validated Fix - `is_artifact` + `types` (Critical)

This is the fix that turned packaging from `*** No item found` to `*** 1 item found [ACCTBALA.LOAD]`.

Found by reading the on-system Wazi JSON schema files. In this install's schema:

- `selector` / `selectors` / `type` do NOT exist at Activity, Action, or Step nodes. Using them fails with:
  ```
  Additional properties are not allowed ('selector' was unexpected)
  ```
- Artifact binding is driven by `is_artifact` (boolean) and `types` (array) at the **Activity** level.
- By default `is_artifact` evaluates to `false`. The package engine then treats the method as a generic setup task and skips `app_manifest.yaml` entirely.

**Correct `deployment_method.yaml`:**

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

- `apiVersion` must be `wazideploy.ibm.com/v1` - no space after the dot, no `://` typo.
- Do NOT use `selector` / `selectors` on this install. Use `is_artifact: true` + `types: [{name: LOAD}]` at Activity level.
- Do NOT copy a `deploy.yml` snippet that sets `PYTHONPATH=$HOME/.local/...` or `_BPXK_AUTOCVT=ON`. Use only `/usr/lpp/IBM/gdp/dependencies/`.

See `docs/RUNBOOK.md` INC-14 for full triage.

## 4. Future: Jinja2 Template for Environment-Specific Deployment

**File:** `deployment_method.j2` - Template for DEV / TEST / PROD variations

**Status:** Future only. The current pipeline uses `deployment_method.yaml` directly, because Jinja2 `{% if %}` / filter syntax in YAML breaks PyYAML parsing.

**Usage (future):**

```bash
# DEV: Auto deploy to BUILD.LOAD
python3 -m jinja2 deployment_method.j2 -D env=DEV -D app_version=1.0.123 > deployment_method_dev.yaml

# PROD: Approval-gated deploy
python3 -m jinja2 deployment_method.j2 -D env=PROD -D app_version=1.0.123 > deployment_method_prod.yaml
```

## 5. Wazi Deploy Flow

```
1. DBB Build -> BuildReport.json (contains all built LOADs)
2. scripts/generate_manifest.py BuildReport.json -> wazi-deploy/app_manifest.yaml (dynamic)
3. wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml
4. deployment_plan.yaml + app_manifest.yaml -> deployable.tar
5. Publish deployable.tar to JFrog: mainframe-loads-local/core-banking-app/1.0.123/deployable.tar
6. Deploy: Fetch SAME version from JFrog via curl -> wazideploy-deploy -> Smoke Tests
   Rollback = re-deploy previous JFrog version (e.g. 1.0.122). There is no automatic --rollback flag.
```

## 6. Encoding Handling (USS)

- **No emojis** in any YAML, JCL, or workflow `echo` line. Emojis crash the `latin-1` / ISO8859-1 encoder used by Wazi Deploy.
- **No copy-paste from rendered pages** - it inserts `¦` (U+00A6) which breaks UTF-8 parsing.
- **Scrub Control-Z:** In Python, `text.replace('\x1a', '')` before writing, then write with `encoding='iso-8859-1', errors='ignore'`.
- **Create files on USS with `cat << 'EOF'` + `chtag -t -c ISO8859-1`**, not Windows paste (CRLF / EBCDIC corruption).
- **Use `ls -l`, not `ls -h`** - USS `ls` has no `-h`.

```bash
iconv -f UTF-8 -t ISO8859-1 wazi-deploy/app_manifest.yaml > /tmp/app_manifest.yaml
chtag -t -c ISO8859-1 /tmp/app_manifest.yaml
wazideploy-package -dm /tmp/deployment_method.yaml -m /tmp/app_manifest.yaml -dp deployment_plan.yaml
```

See `docs/RUNBOOK.md` INC-12, INC-13.

## CI/CD Sequence

```
PR Creation -> DBB Build (Quality Gate) -> Review -> Merge to main
-> DBB Build on main -> Package and Publish (BuildReport.json -> Manifest -> Wazi Package -> JFrog)
-> Deploy (JFrog -> DEV (auto) -> TEST (approval) -> PROD (approval))
```

- **DBB Build** triggers only on push / PR, `paths-ignore: README.md, docs/**`
- **Package and Publish** triggers only on `workflow_run: ["DBB Build"]`, gated on success
- **Deploy** triggers only on `workflow_run: ["Package and Publish"]`, gated on success
- Deploy downloads the **same** version from JFrog via `curl`, never from GitHub Artifacts

See `docs/CICD.md` for the full chain.

## Resume Bullet

"Implemented application-level Wazi Deploy with dynamic ApplicationManifest generation from DBB BuildReport.json, supporting N COBOL programs (not hardcoded), generic DeploymentMethod with schema-validated artifact binding (is_artifact + types), and Build Once Deploy Many with JFrog Artifactory versioning"

## Related Docs

- `README.md` - Portfolio front door
- `docs/ARCHITECTURE.md` - Components, promotion model
- `docs/CICD.md` - Workflow chain, JFrog source of truth
- `docs/RUNBOOK.md` - Full triage, INC-14 schema fix
- `docs/SETUP.md` - Reproduce from clone
- `docs/XPLORE-CONSTRAINTS.md` - What Xplore allows / forbids
