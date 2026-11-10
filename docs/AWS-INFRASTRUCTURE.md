# AWS Infrastructure

## Account & Region

- **Account ID:** `097690245219` (`FREE` plan; `$137.56` promotional credits remaining at setup, expiring `2027-01-23`)
- **Region:** `ap-south-1` (Mumbai)

## Compute & Storage

| Resource | Identifier / Setting | Notes |
|---|---|---|
| EC2 Instance | `i-005bf9e3f493f2118` | `m7i-flex.large` (`2 vCPU`, `8 GiB RAM`, x86_64, 3.2 GHz Intel Sapphire Rapids) |
| AMI | `ami-05fbd65e334e88c16` | Amazon Linux 2023 Kernel 6.18 (`al2023-ami-kernel-default-x86_64`) |
| Shutdown Behavior | `stop` | `poweroff` stops EC2 without terminating or deleting storage |
| Metadata Service | IMDSv2 required | `HttpTokens=required` |
| Root EBS Volume | `30 GB` `gp3` (`/dev/xvda`) | Encrypted, `DeleteOnTermination=false` |
| Elastic IP | `43.204.157.116` (`eipalloc-0e8c03234120d16c2`) | Stable public IPv4 address |

## Networking & Security Group

- **VPC:** `vpc-040da55c2074a1c49` (Default VPC, Internet Gateway `igw-013fa1d621aa35123`, Route Table `rtb-01cbf634a1e1f642e`)
- **Security Group:** `mc-26-3-sg` (`sg-0bf5100492d4d533f`)

| Port | Protocol | Source CIDR | Purpose |
|---|---|---|---|
| `22` | TCP | `49.36.107.232/32` | Admin SSH only |
| `25565` | TCP | `0.0.0.0/0` | Public Minecraft Java Edition |

RCON (`25575`) is disabled in `server.properties` and not exposed in the Security Group.

## SSH Access

- **EC2 Key Pair:** `mc-26-3-key` (`ed25519`)
- **Local Private Key Path:** `/home/varad/Documents/minecraft-26.3-key.pem` (permissions `0400`)
- **SSH Command:** `mc-server connect` (or `ssh -i ~/Documents/minecraft-26.3-key.pem ec2-user@43.204.157.116`)

## Scoped Friend Access (IAM Policy, Role & User)

To let friends start/stop/check the server without root or admin permissions:

- **IAM Policy:** `arn:aws:iam::097690245219:policy/MinecraftServerOperatorPolicy`
  - Allows `ec2:StartInstances`, `ec2:StopInstances` **only** on `arn:aws:ec2:ap-south-1:097690245219:instance/i-005bf9e3f493f2118`
  - Allows `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus` (`*`)
  - Denies all other EC2 actions (e.g., `TerminateInstances`, volume deletion, new launches) and all other AWS services
- **IAM Role:** `arn:aws:iam::097690245219:role/MinecraftServerOperatorRole` (attaches `MinecraftServerOperatorPolicy`)
- **IAM User:** `mc-friend-operator` (permitted only to call `sts:AssumeRole` on `MinecraftServerOperatorRole`)
- **Local Credential Storage (NOT in docs):** `/home/varad/.aws/mc-friends-credentials.json` (`chmod 600`)
- **Friend CLI Bundle:** `/home/varad/Documents/minecraft server/friend-kit/` (`mc-friend.sh` + `README-FOR-FRIENDS.md`)

## AWS Budget Alerts

- `My Zero-Spend Budget` (`$1.00` monthly net threshold)
- `Minecraft-SMP-Monthly-Budget` (`$25.00` monthly gross usage threshold excluding credits; alerts `varadaj47@gmail.com` at `80%` actual and `100%` forecasted)

> **Note:** AWS Budget alerts send notifications only; they are not a hard spending limit.
