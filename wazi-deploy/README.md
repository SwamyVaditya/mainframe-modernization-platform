# Wazi Deploy - Production-Grade Application-Level Deployment

## Overview
Production-grade mainframe deployment using Wazi Deploy with application-level manifests, not per-program hardcoded.

## Enterprise Patterns

### 1. BuildReport.json -> ApplicationManifest (Dynamic, Not Hardcoded)
**Problem:** Tutorial hardcodes `ACCTBALA` in manifest - only works for 1 program
**Production:** Dynamic from DBB BuildReport.json - supports N programs

```bash
# DBB Build generates BuildReport.json with all built LOADs
# scripts/generate_manifest.py parses it and generates ApplicationManifest
python3 scripts/generate_manifest.py BuildReport.json wazi-deploy/app_manifest.yaml 1.0.123 abc123

# Result: ApplicationManifest contains ALL LOADs from build, not just ACCTBALA
# Example: If build builds ACCTBALA, ACCTDEP, ACCTWDR, manifest has all 3
```

### 2. Generic DeploymentMethod (Application-Level)
**File:** `deployment_method.yaml` - Generic, not per-program
**Pattern:** One method deploys ANY LOAD from manifest via template `{{name}}`, `{{dataset}}`, `{{member}}`
**No hardcoded ACCTBALA** - works for any program from BuildReport.json

### 3. Future: Jinja2 Template for Environment-Specific Deployment
**File:** `deployment_method.j2` - Template for DEV/TEST/PROD variations
**Usage:**
```bash
# DEV: Auto deploy to BUILD.LOAD
python3 -m jinja2 deployment_method.j2 -D env=DEV -D app_version=1.0.123 > deployment_method_dev.yaml

# PROD: Blue-Green with backup
python3 -m jinja2 deployment_method.j2 -D env=PROD -D app_version=1.0.123 > deployment_method_prod.yaml
```

### 4. Wazi Deploy Flow (Production)
```
1. DBB Build -> BuildReport.json (contains all built LOADs)
2. scripts/generate_manifest.py BuildReport.json -> wazi-deploy/app_manifest.yaml (dynamic)
3. wazideploy-package -dm deployment_method.yaml -m app_manifest.yaml -dp deployment_plan.yaml
4. deployment_plan.yaml + app_manifest.yaml -> deployable.tar
5. Publish deployable.tar to JFrog: mainframe-loads-local/core-banking-app/1.0.123/deployable.tar
6. Deploy: Fetch from JFrog -> wazideploy-deploy -> Smoke Tests -> Rollback if fails
```

### 5. Encoding Handling (USS)
USS files are EBCDIC (IBM-1047), Wazi Deploy expects ISO8859-1:
```bash
iconv -f UTF-8 -t ISO8859-1 wazi-deploy/app_manifest.yaml > /tmp/app_manifest.yaml
chtag -t -c ISO8859-1 /tmp/app_manifest.yaml
wazideploy-package -dm /tmp/deployment_method.yaml -m /tmp/app_manifest.yaml -dp deployment_plan.yaml
```

## Files
- `deployment_method.yaml` - Generic deployment method (production, application-level)
- `deployment_method.j2` - Jinja2 template for environment-specific methods (future)
- `app_manifest.yaml` - Generated dynamically from BuildReport.json (not committed, generated in pipeline)
- `README.md` - This file

## Production CI/CD Sequence
```
PR Creation -> DBB Build (Quality Gate) -> Review -> Merge to main
-> DBB Build on main -> Package + Publish (BuildReport.json -> Manifest -> Wazi Package -> JFrog)
-> Deploy (JFrog -> DEV (auto) -> TEST (approval) -> PROD (approval + blue-green + rollback))
```

## Resume Bullet
"Implemented application-level Wazi Deploy with dynamic ApplicationManifest generation from DBB BuildReport.json, supporting N COBOL programs (not hardcoded), generic DeploymentMethod, Jinja2 templating for environment promotion, and Build Once Deploy Many with JFrog Artifactory versioning"

---

### **Complete Structure:**

```
wazi-deploy/
├── deployment_method.yaml      # Generic, production
├── deployment_method.j2        # Template for future env-specific
└── README.md                   # Documentation
```

**`app_manifest.yaml` is NOT committed - it's generated dynamically in pipeline from BuildReport.json! That's production pattern!**

---
