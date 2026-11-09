# Evidence - Verified GREEN Runs

> All runs on `main` branch. JFrog is source of truth. GitHub Artifacts are 30-day debug cache only.

## 1. DBB Build - GREEN

- Workflow: DBB Build
- Run: 42323647719
- Commit: 74f0dbe
- Result: ZUnit 12/12 (stub), SonarQube Passed
- Screenshot: ./evidence/01-dbb-build-green.png

## 2. Package and Publish - GREEN

- Version: 1.0.115
- Fix: `*** 1 item found [ACCTBALA.LOAD]` (was `*** No item found`)
- Schema: `is_artifact: true` + `types: [{name: LOAD}]` at Activity level
- JFrog: `mainframe-loads-local/core-banking-app/1.0.115/deployable.tar`
- Size: 10240, SHA256: `20c66b2f88c07bb4084d841304bc047853e8f848645cbf3c8f2f767983062332`
- Screenshot: ./evidence/04-1-item-found.png
- Screenshot: ./evidence/06-jfrog-upload.png

## 3. Deploy - GREEN

- Version: 1.0.120
- DEV: Wazi Deploy + smoke `ACCTBALA` PASS
- TEST: `Z78651.TEST.LOAD` verified (IGD17001I duplicate = expected, idempotent)
- PROD: `Z78651.PROD.LOAD` verified
- Rollback: Re-deploy previous JFrog version. No --rollback flag.
- Screenshot: ./evidence/07-deploy-green.png

## 4. Chain - Build Once, Deploy Many

- DBB Build (workflow_run) -> Package and Publish (workflow_run) -> Deploy
- Deploy downloads SAME version from JFrog via `curl`, not from GitHub Artifacts
- Screenshot: ./evidence/12-jfrog-download-curl.png