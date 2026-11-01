# CI/CD - GitHub Actions DBB Build

## Overview

Phase 2 CI pipeline runs DBB User Build on IBM Z Xplore (Z78651) for every push to `main` / `feature/**` and PRs.

**Flow:**
```
Git push feature/acctbala-fix
  -> GitHub Actions (ubuntu-latest)
  -> appleboy/scp-action: Upload cobol/, copybook/, application-conf/, zapp.yaml to /z/z78651/work/workspace/mainframe-modernization-platform/
  -> appleboy/ssh-action: groovyz /z/z78651/work/dbb-zappbuild/build.groovy --userBuild ACCTBALA.cbl
  -> Parse BuildReport.json (CLEAN + 1 file)
  -> Post PR comment
```

---

## Setup - GitHub Secrets

Go to GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret:

| Secret | Value | Example |
|--------|-------|---------|
| ZOS_HOST | Xplore SSH host | 204.90.115.200 |
| ZOS_USER | Xplore user | z78651 |
| ZOS_PASSWORD | Xplore password | (your password) |
| SSH_PRIVATE_KEY | (optional) SSH key for key auth | -----BEGIN RSA... |

**Xplore uses self-signed certs** - workflow uses `StrictHostKeyChecking no` and `rejectUnauthorized false` equivalent.

---

## Workflow - .github/workflows/dbb-build.yml

**Triggers:**
- push to main, feature/**, fix/**
- pull_request to main
- workflow_dispatch (manual)

**Jobs:**

1. **dbb-user-build:**
   - Checkout
   - tj-actions/changed-files: Detect changed cobol/*.cbl, copybook/*.cpy, application-conf/*
   - SCP upload to USS (only if changed)
   - SSH: chtag + groovyz build.groovy --userBuild ACCTBALA.cbl
   - Download BuildReport.json
   - Check CLEAN state

2. **security-scan (placeholder):** Future ZCodeScan

---

## Local Test

```sh
# Simulate CI steps locally via SSH
scp -r cobol/ copybook/ application-conf/ zapp.yaml z78651@204.90.115.200:/z/z78651/work/workspace/mainframe-modernization-platform/
ssh z78651@204.90.115.200 ". ~/.profile; /usr/lpp/IBM/dbb/bin/groovyz /z/z78651/work/dbb-zappbuild/build.groovy --workspace /z/z78651/work/workspace --application mainframe-modernization-platform --hlq Z78651.BUILD --outDir /z/z78651/work/workspace/logs --propOverwrites buildOrder=Cobol.groovy --verbose --userBuild /z/z78651/work/workspace/mainframe-modernization-platform/cobol/ACCTBALA.cbl; cat /z/z78651/work/workspace/logs/BuildReport.json"
```

---

## Branch Protection

After workflow works:

GitHub repo -> Settings -> Branches -> Add rule for `main`:
- Require status checks: dbb-user-build
- Require pull request before merging
- Require conversation resolution

This ensures PRs can't merge unless DBB build is CLEAN.

---

## Future Enhancements

- [ ] Use Zowe CLI instead of SCP (zowe zos-files upload)
- [ ] Parse BuildReport.json with jq and fail CI if not CLEAN
- [ ] Upload ACCTBALA.log as artifact
- [ ] Wazi Deploy to test LPAR
- [ ] IBM Z CodeScan for COBOL quality gates
- [ ] Dependency impact build (full app, not just ACCTBALA)
