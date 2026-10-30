# Mainframe Modernization Platform
> Production-grade portfolio repository maintained by Mainframe Engineering & Modernization Team

### Business Context
Core Banking Account Balance Service - modernized from classic COBOL/VSAM to Git-native delivery using IBM DBB and Zowe.

### Architecture
VS Code [Zowe Explorer v3.6.0 + Z Open Editor v6.9.0] -> z/OSMF/SSH -> z/OS USS 3.1 [DBB 2.0.2.7 + zAppBuild 3.14.0-BASE] -> HLQ Z78651.BUILD

### Stack
- Language: COBOL, VSAM KSDS, JCL
- Build: IBM Dependency Based Build with zAppBuild
- IDE: IBM Developer for z/OS on VS Code
- SCM: Git + GitHub
- Future: GitHub Actions CI, Wazi Deploy, ZCodeScan

### Phase 1 - DBB User Build Workflow
1. Clean USS: `rm -rf /z/z78651/work/workspace/* && mkdir -p logs`
2. Ensure `HISTFILE=/dev/null` in ~/.profile (Xplore space issue)
3. Configure VS Code settings.json userbuild.userSettings
4. Open cobol/ACCTBALA.cbl -> Run IBM User Build **with full upload** (first time)
5. Verify BuildReport.json -> totalFiles=1, logs downloaded
6. Subsequent edits -> Run IBM User Build (incremental)

See docs/RUNBOOK.md for triage.

### Repository Standards
- All COBOL encoded ibm-1047 via .gitattributes
- Original code, not IBM SAM1 samples
- Enterprise properties files
