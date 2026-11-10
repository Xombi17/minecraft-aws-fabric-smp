# AWS Cost Estimate & Credit Management (`ap-south-1` Mumbai)

Prices queried directly from the AWS Pricing API for `ap-south-1`.

## Unit Rates (`ap-south-1`)

| Resource | Rate | Notes |
|---|---|---|
| `m7i-flex.large` On-Demand | **`$0.1008 / hour`** | `2 vCPU`, `8 GiB RAM`, x86_64; Free-Plan eligible max-RAM type |
| EBS `gp3` (`30 GB`) | **`$0.0912 / GB-month`** (`$2.74 / month`) | Always billed even while EC2 is stopped; `3,000 IOPS` & `125 MiB/s` included |
| Elastic IP (`43.204.157.116`) | **`$0.005 / IP-hour`** (`$3.65 / month`) | Billed `24/7` whether EC2 is running or stopped |
| Data Transfer Out (Internet) | `$0.00 / GB` first `100 GB/mo`, then `$0.1093 / GB` | Typical 20-player SMP stays well inside `100 GB/mo` free tier |
| Local EBS Backups | `$0.00` extra | Stored compressed inside existing `30 GB` `gp3` volume |

## Monthly Cost Scenarios

| Usage Pattern | Compute (`m7i-flex.large`) | EBS (`30 GB gp3`) | Elastic IP (`24/7`) | Estimated Total / Month |
|---|---|---|---|---|
| **2 hrs/day (~60h/mo)** | `$6.05` | `$2.74` | `$3.65` | **`~$12.44 / mo`** |
| **4 hrs/day (~120h/mo, typical w/ idle shutdown)** | `$12.10` | `$2.74` | `$3.65` | **`~$18.49 / mo`** |
| **8 hrs/day (~240h/mo)** | `$24.19` | `$2.74` | `$3.65` | **`~$30.58 / mo`** |
| 24/7 Always On (`730h/mo`, no auto-shutdown) | `$73.58` | `$2.74` | `$3.65` | `$79.97 / mo` |

## Credit Runway & Important Caveats

- **Starting Remaining Credits on `097690245219` (`FREE` Plan):** `$137.56` (expires `2027-01-23`).
- At `~4 hrs/day` (`~$18.49/mo`), the server consumes only `~$45` of credits over the remaining ~2.5 months before `2027-01-23`.
- **Important Free Plan Caveats:**
  1. When promotional credits expire (`2027-01-23`) or hit `$0`, an AWS **Free Plan** account automatically suspends/closes unless upgraded to a Paid Plan.
  2. **AWS Budgets (`Minecraft-SMP-Monthly-Budget` at `$25.00`) is an alert only, not a hard shutoff.**
  3. Idle auto-shutdown (`20 min` at `0` players) prevents leaving compute running overnight (`$0.1008/hr` saved whenever stopped).
