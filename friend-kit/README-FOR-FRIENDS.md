# Friend Access Guide — Minecraft 26.3 Fabric SMP

You can start, stop, and check the server status using the scoped AWS IAM Role (`MinecraftServerOperatorRole`), which only permits starting, stopping, and checking this single EC2 instance (`i-005bf9e3f493f2118`).

## 1. One-Time AWS CLI Setup

1. Install AWS CLI v2 (`aws --version`).
2. Configure the base friend credential profile using the Access Key ID and Secret Key shared privately by the server admin:

```bash
aws configure --profile mc-friend-base
# Enter Access Key ID and Secret Access Key
# Default region name: ap-south-1
# Default output format: json
```

3. Add the `mc-friend` role profile to `~/.aws/config`:

```ini
[profile mc-friend]
role_arn = arn:aws:iam::097690245219:role/MinecraftServerOperatorRole
source_profile = mc-friend-base
region = ap-south-1
```

## 2. Usage

```bash
chmod +x mc-friend.sh
./mc-friend.sh status   # Check if EC2 & Minecraft are online
./mc-friend.sh start    # Boot EC2 and wait until 43.204.157.116:25565 is ready
./mc-friend.sh stop     # Gracefully save & stop EC2 when finished
```

## 3. Joining the Server

- **Minecraft Version:** Java Edition `26.3` (vanilla client works; no client mods required)
- **Server Address:** `43.204.157.116` (port `25565`)
- **Idle Shutdown:** If all players leave, the server automatically saves the world and shuts down EC2 after 20 minutes to save AWS credits. Run `./mc-friend.sh start` whenever you want to play again.
