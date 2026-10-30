# RUNBOOK - DBB User Build

## Triage: No space left on device (ENOSPC)
Symptom: `FSUZ0112 failed to write history file /z/z78651/.zsh_history.new: eDC5133I No space left on device`
Fix:
1. setopt noincappendhistory; HISTFILE=/dev/null
2. rm -rf ~/.npm ~/.zsh_history* ~/.vscode-server ~/.cache /z/z78651/work/workspace
3. Lean dbb-zappbuild: rm -rf img samples docs test .git
4. df -k /z -> need >5000 free

## Triage: 0 files built
Symptom: Step 5 Additional Dependencies No matched files found, copybooks 0, BuildReport totalFiles 0
Root Causes:
1. Windows path with spaces/brackets: d:\[1]. DEVOPS\... breaks glob matcher. Use D:\mf\...
2. file.properties wrong: Must map cobol=cobol/*.cbl copybook=copybook/*.cpy
3. Missing .gitattributes encoding: cobol must be ibm-1047
4. Did not run Full Upload first time - dependency cache not seeded

## Triage: BuildReport.html not downloading
DBB 2.0.2.7 writes logs to /z/z78651/work/workspace/logs/*.log only if compile runs. If scanner fails, no .log created. Check USS directly: ls /z/z78651/work/workspace/logs/BuildReport.json

## User Build Sequence
1. Pristine workspace
2. Validate zapp.yaml
3. First run: Full Upload
4. Verify BuildReport
5. Incremental runs: Normal Run
