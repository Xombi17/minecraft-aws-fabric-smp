# Troubleshooting & Operations Runbook

## 1. SSH Connection Fails (Your Home IP Changed)

Port `22` is locked to `49.36.107.232/32` for security. If your ISP assigns a new IP:

```bash
NEW_IP="$(curl -s https://checkip.amazonaws.com)/32"
# Inspect existing rule and update Security Group sg-0bf5100492d4d533f:
aws ec2 describe-security-groups --region ap-south-1 --group-ids sg-0bf5100492d4d533f --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
aws ec2 revoke-security-group-ingress --region ap-south-1 --group-id sg-0bf5100492d4d533f --protocol tcp --port 22 --cidr <OLD_IP>/32
aws ec2 authorize-security-group-ingress --region ap-south-1 --group-id sg-0bf5100492d4d533f --protocol tcp --port 22 --cidr "$NEW_IP"
```

## 2. Diagnosing Lag (TPS / MSPT / GC / Memory)

1. Check overall server health from local terminal:
   ```bash
   mc-server health
   ```
2. Run a Spark profiler + health report from SSH (`mc-server connect`):
   ```bash
   /home/ec2-user/minecraft/scripts/mc-cmd.sh "spark health"
   /home/ec2-user/minecraft/scripts/mc-cmd.sh "spark profiler start"
   # Wait 60 seconds during lag, then:
   /home/ec2-user/minecraft/scripts/mc-cmd.sh "spark profiler stop"
   # Check latest.log for the Spark web URL:
   grep "spark.lucko.me" /home/ec2-user/minecraft/logs/latest.log | tail -n 5
   ```
3. Check GC logs (`logs/gc.log`) or OOM events:
   ```bash
   grep -E "OutOfMemory|Allocation Stall" /home/ec2-user/minecraft/logs/gc.log* || true
   ```
4. Check `ServerCore` dynamic throttling live:
   ```bash
   /home/ec2-user/minecraft/scripts/mc-cmd.sh "servercore status"
   ```

## 3. Idle Auto-Shutdown Behavior & Temporary Override

- **Check countdown logs:**
  ```bash
  mc-server connect
  journalctl -u mc-idle-shutdown -n 30 --no-pager
  ```
- **Temporarily pause idle shutdown during maintenance** (e.g., running long Chunky pregen without players online):
  ```bash
  sudo systemctl stop mc-idle-shutdown.service
  # Re-enable when finished:
  sudo systemctl start mc-idle-shutdown.service
  ```
- **Adjust timeout:** Edit `/etc/default/mc-idle-shutdown` (`IDLE_TIMEOUT_SECONDS=1200`) and run `sudo systemctl restart mc-idle-shutdown.service`.

## 4. `mc-server` CLI Cannot Connect or Stuck in `stopping`

- If EC2 is `stopping`, `mc-server start` automatically waits for `stopped` before booting.
- If `minecraft.service` failed to start on EC2, SSH in (`mc-server connect`) and inspect:
  ```bash
  sudo journalctl -u minecraft -n 100 --no-pager
  cat /home/ec2-user/minecraft/logs/latest.log | tail -n 50
  ```

## 5. Rotating Friend IAM Credentials

If a friend credential needs revocation:

```bash
aws iam list-access-keys --user-name mc-friend-operator
aws iam delete-access-key --user-name mc-friend-operator --access-key-id <KEY_ID>
# Create a new key directly to restricted file (chmod 600) if needed
```
