# Monthly Cost Review - [Month YYYY]

**Date:** [Date of Review]
**Attendees:** [List attendees]
**Duration:** 30 minutes
**Next Review:** [First Monday of next month]

---

## 1. Executive Summary

**Total Monthly Spend:** $XXX.XX

| Environment | Budget | Actual | Variance | Status |
|-------------|--------|--------|----------|--------|
| Production  | $500   | $XXX   | ±X%      | ✓/⚠/✗  |
| Non-Prod    | $150   | $XXX   | ±X%      | ✓/⚠/✗  |
| **TOTAL**   | **$650** | **$XXX** | **±X%** | **✓/⚠/✗** |

**Month-over-Month Change:** ±X% ($XXX vs $XXX last month)

**Key Findings:**
- [Bullet point summary of major findings]
- [Unusual cost increases or decreases]
- [Budget concerns or wins]

---

## 2. Cost by Environment

### Production Environment

**Budget:** $500/month | **Actual:** $XXX | **Variance:** ±X%

**Top Cost Drivers:**
1. RDS (PostgreSQL) - $XXX (XX%)
2. ECS Fargate - $XXX (XX%)
3. ElastiCache (Redis) - $XXX (XX%)
4. Application Load Balancer - $XXX (XX%)
5. Data Transfer - $XXX (XX%)

**Notable Changes:**
- [Describe any significant cost changes from last month]

**Action Items:**
- [ ] [Specific action item with owner and due date]

### Non-Production Environment

**Budget:** $150/month | **Actual:** $XXX | **Variance:** ±X%

**Top Cost Drivers:**
1. [Service] - $XXX (XX%)
2. [Service] - $XXX (XX%)
3. [Service] - $XXX (XX%)

**Notable Changes:**
- [Describe any significant cost changes from last month]

**Action Items:**
- [ ] [Specific action item with owner and due date]

---

## 3. Service-Level Analysis

### RDS (Database)

**Monthly Cost:** $XXX
**Change from Last Month:** ±X% ($XXX)
**Instance Types:** db.t3.medium (prod), db.t3.micro (non-prod)

**Metrics:**
- Average CPU Utilization: XX%
- Average Connections: XXX
- Storage Used: XXX GB / XXX GB provisioned

**Optimization Opportunities:**
- [ ] Consider Reserved Instances (save ~40%)
- [ ] Review snapshot retention policy
- [ ] Evaluate Multi-AZ necessity in non-prod

**Estimated Savings:** $XXX/month

### ECS Fargate (Compute)

**Monthly Cost:** $XXX
**Change from Last Month:** ±X% ($XXX)
**Task Definitions:** backend-prod (X tasks), frontend-prod (X tasks)

**Metrics:**
- Average CPU Utilization: XX%
- Average Memory Utilization: XX%
- Task Count: Min X / Max X / Avg X

**Optimization Opportunities:**
- [ ] Right-size task CPU/memory allocations
- [ ] Consider Compute Savings Plans (save ~50%)
- [ ] Review auto-scaling policies

**Estimated Savings:** $XXX/month

### ElastiCache (Redis)

**Monthly Cost:** $XXX
**Change from Last Month:** ±X% ($XXX)
**Node Types:** cache.t3.micro (prod), cache.t3.micro (non-prod)

**Metrics:**
- Average CPU Utilization: XX%
- Cache Hit Rate: XX%
- Network Throughput: XXX MB/s

**Optimization Opportunities:**
- [ ] Evaluate node type sizing
- [ ] Review cache eviction policies
- [ ] Consider Reserved Nodes

**Estimated Savings:** $XXX/month

### S3 Storage

**Monthly Cost:** $XXX
**Change from Last Month:** ±X% ($XXX)
**Total Storage:** XXX GB

**Storage Breakdown:**
- Standard: XXX GB ($XXX)
- Intelligent Tiering: XXX GB ($XXX)
- Glacier: XXX GB ($XXX)

**Optimization Opportunities:**
- [ ] Enable lifecycle policies for media files
- [ ] Move old backups to Glacier
- [ ] Review and delete unused buckets

**Estimated Savings:** $XXX/month

### Data Transfer

**Monthly Cost:** $XXX
**Change from Last Month:** ±X% ($XXX)

**Metrics:**
- Data Transfer Out: XXX GB
- CloudFront: XXX GB
- Inter-Region: XXX GB

**Optimization Opportunities:**
- [ ] Enable CloudFront caching
- [ ] Review VPC peering vs internet egress
- [ ] Optimize API response sizes

**Estimated Savings:** $XXX/month

---

## 4. Idle Resources Found

Run `make check-idle-resources` before review to populate this section.

### Unattached EBS Volumes
- **Count:** X
- **Total Size:** XXX GB
- **Monthly Cost:** $XXX
- **Action:** [Delete / Investigate / Keep]

### Old EBS Snapshots (>90 days)
- **Count:** X
- **Total Size:** XXX GB
- **Monthly Cost:** $XXX
- **Action:** [Delete / Archive / Keep]

### Unused Elastic IPs
- **Count:** X
- **Monthly Cost:** $XXX
- **Action:** [Release / Investigate]

### Stopped RDS Instances
- **Count:** X
- **Monthly Cost:** $XXX (storage only)
- **Action:** [Terminate / Start / Keep]

### Idle Load Balancers
- **Count:** X
- **Monthly Cost:** $XXX
- **Action:** [Delete / Investigate]

**Total Potential Savings from Cleanup:** $XXX/month

---

## 5. Anomalies & Unexpected Costs

### Cost Anomalies Detected

**Date Range:** [Date range analyzed]

1. **[Service Name] - [Date]**
   - **Increase:** $XXX (XX%)
   - **Root Cause:** [Description]
   - **Action Taken:** [Resolution]

2. **[Service Name] - [Date]**
   - **Increase:** $XXX (XX%)
   - **Root Cause:** [Description]
   - **Action Taken:** [Resolution]

### Budget Alert History

- **[Date]:** Production budget reached 85% ($XXX / $500)
- **[Date]:** Non-prod budget reached 100% ($XXX / $150)

**Actions Taken:**
- [Describe any emergency cost control measures]

---

## 6. Reserved Instances & Savings Plans

### Current Commitments

| Type | Service | Term | Monthly Savings | Expires |
|------|---------|------|-----------------|---------|
| RI   | RDS db.t3.medium | 1-year | $XX | YYYY-MM-DD |
| SP   | Compute | 1-year | $XX | YYYY-MM-DD |

**Total Monthly Savings from Commitments:** $XXX

### Recommendations for New Commitments

Based on 90-day usage analysis:

1. **RDS Reserved Instance**
   - Instance: db.t3.medium (production)
   - Term: 1-year All Upfront
   - Current Cost: $XXX/month
   - RI Cost: $XXX/month
   - **Savings:** $XXX/month (XX%)
   - **Break-even:** X months
   - **Recommendation:** [Yes/No/Wait]

2. **Compute Savings Plan**
   - Commitment: $XXX/hour
   - Term: 1-year No Upfront
   - Current Cost: $XXX/month
   - SP Cost: $XXX/month
   - **Savings:** $XXX/month (XX%)
   - **Recommendation:** [Yes/No/Wait]

**Total Potential Additional Savings:** $XXX/month

---

## 7. Optimization Action Items

### Immediate Actions (This Week)

- [ ] Delete X unattached EBS volumes - **Saves $XXX/month** - Owner: [Name]
- [ ] Release X unused Elastic IPs - **Saves $XXX/month** - Owner: [Name]
- [ ] Delete old snapshots >90 days - **Saves $XXX/month** - Owner: [Name]
- [ ] [Additional action item] - **Saves $XXX/month** - Owner: [Name]

**Total Immediate Savings:** $XXX/month

### Short-Term Actions (This Month)

- [ ] Purchase RDS Reserved Instance for prod - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] Implement S3 lifecycle policies - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] Right-size ECS Fargate tasks - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] [Additional action item] - **Saves $XXX/month** - Owner: [Name] - Due: [Date]

**Total Short-Term Savings:** $XXX/month

### Long-Term Actions (This Quarter)

- [ ] Evaluate Compute Savings Plan - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] Migrate dev environment to Spot Instances - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] Implement CloudFront for media delivery - **Saves $XXX/month** - Owner: [Name] - Due: [Date]
- [ ] [Additional action item] - **Saves $XXX/month** - Owner: [Name] - Due: [Date]

**Total Long-Term Savings:** $XXX/month

---

## 8. Cost Forecast

### Next Month Projection

**Projected Total:** $XXX

**Assumptions:**
- [List assumptions: seasonal changes, new features, etc.]
- Current trend continues at X% growth
- [Additional assumptions]

**Risk Factors:**
- [Potential cost increases: new features, traffic spikes, etc.]
- [Mitigation strategies]

### Quarterly Projection

**Q[X] YYYY Projected Total:** $XXX

**Major Changes Expected:**
- [List planned infrastructure changes]
- [New services or features]
- [Decommissioning old services]

---

## 9. Budget Adjustments

### Recommended Budget Changes

| Environment | Current Budget | Recommended | Change | Rationale |
|-------------|----------------|-------------|--------|-----------|
| Production  | $500           | $XXX        | ±$XXX  | [Reason]  |
| Non-Prod    | $150           | $XXX        | ±$XXX  | [Reason]  |

**Approval Required:** [Yes/No]
**Approved By:** [Name/Pending]
**Effective Date:** [Date]

---

## 10. Action Items Summary

### Immediate (This Week)
1. [Action] - Owner: [Name] - Saves: $XXX
2. [Action] - Owner: [Name] - Saves: $XXX
3. [Action] - Owner: [Name] - Saves: $XXX

### Short-Term (This Month)
1. [Action] - Owner: [Name] - Saves: $XXX - Due: [Date]
2. [Action] - Owner: [Name] - Saves: $XXX - Due: [Date]
3. [Action] - Owner: [Name] - Saves: $XXX - Due: [Date]

### Long-Term (This Quarter)
1. [Action] - Owner: [Name] - Saves: $XXX - Due: [Date]
2. [Action] - Owner: [Name] - Saves: $XXX - Due: [Date]

**Total Potential Monthly Savings:** $XXX (XX% cost reduction)

---

## 11. Meeting Notes

**Discussion Points:**
- [Key discussion topics]
- [Decisions made]
- [Questions raised]

**Blockers:**
- [Any blockers to cost optimization]
- [Required approvals or resources]

**Next Steps:**
- Schedule follow-up on action items
- Create JIRA tickets for optimization tasks
- Update budget alert thresholds if needed

---

## 12. Appendices

### A. Cost Reports Generated

- Daily Cost Report: `.agent/cost-reports/daily-cost-YYYY-MM-DD.json`
- Monthly Comparison: `.agent/cost-reports/monthly-comparison-YYYY-MM-DD.md`
- Idle Resources: `.agent/cost-reports/idle-resources-YYYY-MM-DD.txt`

### B. Commands Used

```bash
# Generate daily report
make cost-report-daily

# Monthly comparison
make cost-compare-monthly

# Check idle resources
make check-idle-resources

# View Cost Explorer
open "https://console.aws.amazon.com/cost-management/home#/cost-explorer"
```

### C. References

- [Cost Management SOP](../.agent/sops/SOP_COST_MANAGEMENT.md)
- [Cost Allocation Tags](./COST_ALLOCATION_TAGS.md)
- [CloudWatch Cost Dashboard](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=LightWave-Cost-Monitoring)
- [AWS Budgets Console](https://console.aws.amazon.com/billing/home#/budgets)

---

**Review Completed By:** [Name]
**Next Review Date:** [First Monday of next month]
**Distribution:** [Email list or Slack channel]

---

## How to Use This Template

1. **Before the Meeting:**
   - Run `make cost-report-daily` to get yesterday's costs
   - Run `make cost-compare-monthly` to compare current vs last month
   - Run `make check-idle-resources` to identify waste
   - Review AWS Cost Explorer for anomalies
   - Populate sections 1-5 with actual data

2. **During the Meeting:**
   - Walk through Executive Summary (5 min)
   - Review top cost drivers (10 min)
   - Discuss idle resources and quick wins (5 min)
   - Review optimization opportunities (5 min)
   - Assign action items (5 min)

3. **After the Meeting:**
   - Save completed review to `.agent/cost-reviews/cost-review-YYYY-MM.md`
   - Create JIRA tickets for action items
   - Send summary email to stakeholders
   - Schedule follow-up for action items
   - Update budget thresholds if needed

4. **Between Meetings:**
   - Monitor daily cost reports for anomalies
   - Track progress on action items
   - Respond to budget alerts promptly
   - Document any emergency cost actions

---

**Template Version:** 1.0.0
**Last Updated:** 2025-10-29
**Maintained By:** Platform Team
