# Disaster Recovery Testing Checklist

**Purpose:** Ensure disaster recovery procedures are tested regularly and work as documented.

**Frequency:**
- **Production:** Quarterly (every 3 months)
- **Non-Production:** Bi-annually (every 6 months)
- **Full DR Exercise:** Annually (October)

---

## Pre-Test Preparation

### 1 Week Before Test

- [ ] Schedule DR test in team calendar
- [ ] Post announcement in #infrastructure channel
- [ ] Identify test participants (minimum 2 engineers)
- [ ] Select test window (low-traffic period)
- [ ] Review latest SOP_DISASTER_RECOVERY.md
- [ ] Verify backup retention policies
- [ ] Check cross-region replication status

**Announcement Template:**
```
📋 Disaster Recovery Test Scheduled

Date: [DATE]
Time: [TIME] UTC
Environment: [prod/non-prod]
Type: [backup/snapshot/pitr/full]
Duration: ~2 hours

Participants:
- Incident Commander: @name
- Engineers: @name1, @name2

This test will NOT impact production services.
```

### Day Before Test

- [ ] Verify AWS credentials (AWS_PROFILE=lightwave-admin-new)
- [ ] Run pre-test health checks
  ```bash
  make verify-state-nonprod  # or verify-state-prod
  ./scripts/dr-test.sh non-prod backup --dry-run
  ```
- [ ] Review runbooks in SOP_DISASTER_RECOVERY.md
- [ ] Prepare Zoom/Slack war room links
- [ ] Test communication channels
- [ ] Assign roles (IC, scribe, executors)

---

## Quarterly Production DR Test

**Environment:** Production
**Test Type:** Read-only (backup verification, snapshot creation)
**Duration:** 1-2 hours
**Risk Level:** LOW (no destructive operations)

### Test Execution

**Step 1: Verify AWS Access**
- [ ] Set AWS profile: `export AWS_PROFILE=lightwave-admin-new`
- [ ] Verify connectivity: `aws sts get-caller-identity`
- [ ] Confirm account ID matches production

**Step 2: Test Remote State Access**
- [ ] Run: `./scripts/verify-remote-state.sh prod us-east-1`
- [ ] Verify S3 bucket accessible
- [ ] Verify DynamoDB lock table accessible
- [ ] Check S3 versioning enabled

**Step 3: Backup Terraform State**
- [ ] Run: `./scripts/backup-state.sh prod`
- [ ] Verify backup created successfully
- [ ] Check backup file sizes (should match expected)
- [ ] Confirm backup directory: `state-backups/prod/latest`
- [ ] Record backup timestamp: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

**Step 4: Verify RDS Automated Snapshots**
- [ ] Run: `./scripts/dr-test.sh prod snapshot`
- [ ] Verify automated snapshots exist (30-day retention)
- [ ] Record latest snapshot timestamp: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_
- [ ] Check snapshot size and status

**Step 5: Create Manual RDS Snapshot**
- [ ] Create manual snapshot for DR test
- [ ] Tag with: Purpose=DR-Test, Date=[DATE]
- [ ] Wait for snapshot completion (~5-10 minutes)
- [ ] Verify snapshot status: `available`
- [ ] Record snapshot ID: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

**Step 6: Verify Point-in-Time Recovery Window**
- [ ] Run: `./scripts/dr-test.sh prod pitr`
- [ ] Check earliest restorable time
- [ ] Check latest restorable time
- [ ] Verify PITR window covers RPO target (5 minutes)

**Step 7: Check Cross-Region Backups**
- [ ] Verify snapshots exist in us-west-2 (DR region)
- [ ] Check replication lag
- [ ] Confirm snapshot copy automation working

**Step 8: Test Monitoring and Alerting**
- [ ] Verify CloudWatch alarms configured
- [ ] Check RDS enhanced monitoring enabled
- [ ] Test incident notification channels
- [ ] Verify status page access

**Step 9: Document Results**
- [ ] Record test duration: \_\_\_\_\_\_\_\_\_\_
- [ ] Note any issues encountered
- [ ] Update runbooks based on findings
- [ ] Calculate RTO if restore was needed: \_\_\_\_\_\_\_\_\_\_

**Step 10: Cleanup**
- [ ] Delete manual test snapshot (after 24 hours)
  ```bash
  aws rds delete-db-snapshot --db-snapshot-identifier [SNAPSHOT-ID]
  ```
- [ ] Verify automated backups still running
- [ ] Archive test results

---

## Bi-Annual Non-Production DR Test

**Environment:** Non-Production
**Test Type:** Full DR test (backup + restore simulation)
**Duration:** 3-4 hours
**Risk Level:** MEDIUM (destructive operations in non-prod only)

### Test Execution

**Phase 1: Backup Everything**
- [ ] Backup Terraform state: `./scripts/backup-state.sh non-prod`
- [ ] Create RDS snapshot
- [ ] Document current infrastructure state
- [ ] Record resource counts:
  - ECS tasks: \_\_\_\_\_\_
  - RDS instances: \_\_\_\_\_\_
  - S3 buckets: \_\_\_\_\_\_

**Phase 2: Simulate Disaster**
- [ ] Choose disaster scenario:
  - [ ] Data loss (accidental deletion)
  - [ ] Infrastructure destruction
  - [ ] Database corruption
- [ ] Execute simulation safely in non-prod
- [ ] Document failure symptoms

**Phase 3: Execute Recovery**
- [ ] Follow SOP_DISASTER_RECOVERY.md procedures
- [ ] Start timer for RTO calculation
- [ ] Restore Terraform state (if needed)
- [ ] Restore RDS from snapshot
- [ ] Rebuild infrastructure (if destroyed)
- [ ] Stop timer, record RTO: \_\_\_\_\_\_\_\_\_\_

**Phase 4: Verify Recovery**
- [ ] Run: `terragrunt run-all plan` (should show no changes)
- [ ] Check database connectivity
- [ ] Run application smoke tests: `./scripts/smoke-test-nonprod.sh`
- [ ] Verify data integrity
- [ ] Confirm all services operational

**Phase 5: Test Communication Plan**
- [ ] Practice incident declaration
- [ ] Send test status updates (every 15 min)
- [ ] Practice resolution announcement
- [ ] Update status page (if available)

**Phase 6: Document and Improve**
- [ ] Record actual RTO vs target
- [ ] Identify gaps in procedures
- [ ] Update runbooks based on learnings
- [ ] Create action items for improvements
- [ ] Schedule post-test retro

---

## Annual Full DR Exercise (Production-Like)

**Environment:** Production (tabletop) + Non-Production (hands-on)
**Test Type:** Complete disaster recovery exercise
**Duration:** 4-6 hours
**Risk Level:** LOW (mostly simulation)

### Test Execution

**Part 1: Tabletop Exercise (2 hours)**
- [ ] Assemble full team (all engineers + stakeholders)
- [ ] Present disaster scenario: AWS region outage
- [ ] Walk through recovery procedures step-by-step
- [ ] Identify gaps in runbooks
- [ ] Test communication plan
- [ ] Practice incident commander role rotation
- [ ] Review RTO/RPO targets for relevance

**Part 2: Cross-Region Failover Test (2 hours)**
- [ ] Prepare DR region (us-west-2)
- [ ] Deploy infrastructure to DR region
  ```bash
  cd Infrastructure/lightwave-infrastructure-live/non-prod/us-west-2
  terragrunt run-all plan
  ```
- [ ] Simulate primary region failure
- [ ] Restore database from cross-region snapshot
- [ ] Update DNS records (test domain only)
- [ ] Deploy application to DR region
- [ ] Run integration tests
- [ ] Measure failover time: \_\_\_\_\_\_\_\_\_\_
- [ ] Compare to RTO target

**Part 3: Complete Infrastructure Rebuild (2 hours)**
- [ ] Destroy non-prod infrastructure: `make destroy-nonprod`
- [ ] Verify all resources deleted
- [ ] Rebuild from code: `make apply-nonprod`
- [ ] Restore database from backup
- [ ] Deploy application
- [ ] Run full test suite
- [ ] Measure rebuild time: \_\_\_\_\_\_\_\_\_\_

**Part 4: Review and Update**
- [ ] Conduct post-exercise retro
- [ ] Document lessons learned
- [ ] Update all DR procedures
- [ ] Update RTO/RPO targets if needed
- [ ] Create improvement action items
- [ ] Assign owners and deadlines
- [ ] Schedule follow-up training

---

## Post-Test Activities

### Immediately After Test

- [ ] Document test results in `dr-test-results/[TIMESTAMP]/`
- [ ] Share summary in #infrastructure channel
- [ ] Archive test artifacts
- [ ] Update DR testing log spreadsheet

**Summary Template:**
```
✅ DR Test Complete

Environment: [prod/non-prod]
Date: [DATE]
Duration: [TIME]
Result: [PASS/FAIL]

Key Findings:
- [Finding 1]
- [Finding 2]

RTO/RPO Results:
- Target RTO: [TIME]
- Actual RTO: [TIME]
- Target RPO: [TIME]
- Actual RPO: [TIME]

Action Items:
- [ ] [Action 1] (@owner)
- [ ] [Action 2] (@owner)

Full report: dr-test-results/[TIMESTAMP]/summary.txt
```

### Within 1 Week

- [ ] Write detailed post-test report
- [ ] Update SOP_DISASTER_RECOVERY.md with learnings
- [ ] Fix any identified issues
- [ ] Update monitoring/alerting based on findings
- [ ] Share learnings in team meeting
- [ ] Archive test snapshots (delete after 30 days)

### Within 1 Month

- [ ] Complete all action items
- [ ] Verify improvements implemented
- [ ] Schedule next test
- [ ] Train new team members on updated procedures
- [ ] Review and update DR budget estimates

---

## Common Issues and Solutions

### Issue: Backup script fails with "no state found"
**Solution:** Infrastructure may not be deployed yet. Run `terragrunt plan` first.

### Issue: Restore shows unexpected changes
**Solution:** Code may have changed since backup. Review diff carefully before applying.

### Issue: RDS snapshot creation takes too long
**Solution:** Normal for large databases. Plan for 10-15 minutes per snapshot.

### Issue: Cross-region snapshots missing
**Solution:** Check snapshot copy automation. May need to configure manually.

### Issue: Can't access AWS
**Solution:** Verify `AWS_PROFILE=lightwave-admin-new` is set. Check credentials.

---

## Test Schedule

| Test Type | Frequency | Next Due | Owner |
|-----------|-----------|----------|-------|
| Production Backup Test | Quarterly | [DATE] | Platform Team |
| Non-Prod Full DR Test | Bi-annually | [DATE] | Platform Team |
| Annual DR Exercise | Yearly (October) | [DATE] | All Engineers |

---

## Related Documents

- Disaster Recovery SOP: `/Users/joelschaeffer/dev/lightwave-workspace/.agent/sops/SOP_DISASTER_RECOVERY.md`
- DR Test Script: `scripts/dr-test.sh`
- Backup Script: `scripts/backup-state.sh`
- Restore Script: `scripts/restore-from-backup.sh`

---

**Version:** 1.0.0
**Last Updated:** 2025-10-28
**Owner:** Platform Team
**Review Schedule:** Quarterly
