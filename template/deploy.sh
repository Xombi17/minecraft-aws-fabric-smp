#!/usr/bin/env bash
# ==============================================================================
# Modular AWS Minecraft Fabric SMP Provisioner & Bootstrapper
# Usage: ./template/deploy.sh --config my-server.env [--dry-run]
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG_PATH="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: $0 --config <path-to-env> [--dry-run]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]] || {
  echo "[ERROR] Provide a valid --config <file> (see template/deploy.config.env.example)" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$CONFIG_PATH"

AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
PROJECT_NAME="${PROJECT_NAME:-minecraft-smp}"
INSTANCE_TYPE="${INSTANCE_TYPE:-m7i-flex.large}"
INSTANCE_ARCH="${INSTANCE_ARCH:-x86_64}"
EBS_VOLUME_SIZE="${EBS_VOLUME_SIZE:-30}"
EBS_DELETE_ON_TERMINATION="${EBS_DELETE_ON_TERMINATION:-false}"
ALLOCATE_ELASTIC_IP="${ALLOCATE_ELASTIC_IP:-true}"
SSH_ALLOWED_CIDR="${SSH_ALLOWED_CIDR:-auto}"
CREATE_FRIEND_IAM="${CREATE_FRIEND_IAM:-true}"
FRIEND_IAM_PREFIX="${FRIEND_IAM_PREFIX:-$PROJECT_NAME}"
CREATE_BUDGET_ALERT="${CREATE_BUDGET_ALERT:-false}"
BUDGET_AMOUNT_USD="${BUDGET_AMOUNT_USD:-25}"
BUDGET_EMAIL="${BUDGET_EMAIL:-}"
MC_VERSION="${MC_VERSION:-26.3}"
FABRIC_LOADER_VERSION="${FABRIC_LOADER_VERSION:-latest}"
JAVA_VERSION="${JAVA_VERSION:-auto}"
HEAP_MB="${HEAP_MB:-auto}"
GC_MODE="${GC_MODE:-zgc}"
MC_MOTD="${MC_MOTD:-Minecraft Fabric SMP}"
MC_DIFFICULTY="${MC_DIFFICULTY:-easy}"
MC_GAMEMODE="${MC_GAMEMODE:-survival}"
MC_MAX_PLAYERS="${MC_MAX_PLAYERS:-20}"
MC_VIEW_DISTANCE="${MC_VIEW_DISTANCE:-8}"
MC_SIM_DISTANCE="${MC_SIM_DISTANCE:-6}"
MC_WHITELIST="${MC_WHITELIST:-false}"
MC_SEED="${MC_SEED:-}"
MC_SPAWN_PROTECTION="${MC_SPAWN_PROTECTION:-0}"
MC_PAUSE_EMPTY_SECONDS="${MC_PAUSE_EMPTY_SECONDS:-60}"
MOD_LIST_FILE="${MOD_LIST_FILE:-template/modpacks/server-optimization.txt}"
VANILLATWEAKS_CONFIG="${VANILLATWEAKS_CONFIG:-}"
IDLE_TIMEOUT_SECONDS="${IDLE_TIMEOUT_SECONDS:-1200}"
IDLE_CHECK_INTERVAL="${IDLE_CHECK_INTERVAL:-30}"
IDLE_BOOT_GRACE="${IDLE_BOOT_GRACE:-300}"
SSH_KEY_NAME="${SSH_KEY_NAME:-${PROJECT_NAME}-key}"
LOCAL_KEY_DIR="${LOCAL_KEY_DIR:-$HOME/Documents}"
LOCAL_CLI_PATH="${LOCAL_CLI_PATH:-$HOME/Documents/mc-server.sh}"
LOCAL_CLI_CONFIG="${LOCAL_CLI_CONFIG:-$HOME/.config/mc-server/config.env}"

AWS_ARGS=(--region "$AWS_REGION" --profile "$AWS_PROFILE")

echo "=== 1. Resolving AWS Identity & Minecraft ${MC_VERSION} Metadata ==="
ACCOUNT_ID=$(aws sts get-caller-identity "${AWS_ARGS[@]}" --query 'Account' --output text)

read -r RESOLVED_MC RESOLVED_JAVA FABRIC_LOADER_VER FABRIC_INST_VER < <(
python3 - "$MC_VERSION" "$FABRIC_LOADER_VERSION" "$JAVA_VERSION" << 'PYEOF'
import json, sys, urllib.request

mc_req, loader_req, java_req = sys.argv[1], sys.argv[2], sys.argv[3]
def gj(u):
    return json.loads(urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "mc-aws-template/1.0"}), timeout=15).read())

manifest = gj("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
if mc_req == "latest":
    mc_req = manifest["latest"]["release"]
entry = next((v for v in manifest["versions"] if v["id"] == mc_req), None)
if not entry:
    raise SystemExit(f"Minecraft version '{mc_req}' not found in Mojang manifest")
meta = gj(entry["url"])
java_major = str(meta["javaVersion"]["majorVersion"]) if java_req == "auto" else java_req

if loader_req == "latest":
    loaders = gj("https://meta.fabricmc.net/v2/versions/loader")
    loader_ver = next((l["version"] for l in loaders if l.get("stable")), loaders[0]["version"])
else:
    loader_ver = loader_req

insts = gj("https://meta.fabricmc.net/v2/versions/installer")
inst_ver = next((i["version"] for i in insts if i.get("stable")), insts[0]["version"])
print(mc_req, java_major, loader_ver, inst_ver)
PYEOF
)

if [[ "$SSH_ALLOWED_CIDR" == "auto" ]]; then
  SSH_ALLOWED_CIDR="$(curl -fsSL https://checkip.amazonaws.com)/32"
fi

AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${INSTANCE_ARCH}"
AMI_ID=$(aws ssm get-parameter "${AWS_ARGS[@]}" --name "$AMI_PARAM" --query 'Parameter.Value' --output text)
VPC_ID=$(aws ec2 describe-vpcs "${AWS_ARGS[@]}" --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)

echo "AWS Account      : $ACCOUNT_ID (profile=$AWS_PROFILE, region=$AWS_REGION)"
echo "VPC / AL2023 AMI : $VPC_ID / $AMI_ID ($INSTANCE_ARCH)"
echo "Instance / Disk  : $INSTANCE_TYPE / ${EBS_VOLUME_SIZE} GB gp3 (EIP=$ALLOCATE_ELASTIC_IP)"
echo "SSH CIDR         : $SSH_ALLOWED_CIDR"
echo "Minecraft Stack  : MC $RESOLVED_MC | Fabric Loader $FABRIC_LOADER_VER (Installer $FABRIC_INST_VER) | Corretto Java $RESOLVED_JAVA"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "=== DRY-RUN: Mod Compatibility Preview ==="
  python3 "${REPO_ROOT}/template/resolve_mods.py" \
    --mc-version "$RESOLVED_MC" \
    --mod-list "${REPO_ROOT}/${MOD_LIST_FILE}" \
    --manifest-out "/tmp/${PROJECT_NAME}-dryrun-manifest.json"
  rm -f "/tmp/${PROJECT_NAME}-dryrun-manifest.json"
  echo "[DRY-RUN] No AWS resources were created."
  exit 0
fi

# Ensure VPC has an attached IGW
IGW_ATTACHED=$(aws ec2 describe-internet-gateways "${AWS_ARGS[@]}" \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --query 'InternetGateways[0].InternetGatewayId' --output text)
if [[ "$IGW_ATTACHED" == "None" || -z "$IGW_ATTACHED" ]]; then
  DETACHED_IGW=$(aws ec2 describe-internet-gateways "${AWS_ARGS[@]}" --query 'InternetGateways[?length(Attachments)==`0`].InternetGatewayId | [0]' --output text)
  if [[ "$DETACHED_IGW" != "None" && -n "$DETACHED_IGW" ]]; then
    aws ec2 attach-internet-gateway "${AWS_ARGS[@]}" --internet-gateway-id "$DETACHED_IGW" --vpc-id "$VPC_ID"
  else
    NEW_IGW=$(aws ec2 create-internet-gateway "${AWS_ARGS[@]}" --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway "${AWS_ARGS[@]}" --internet-gateway-id "$NEW_IGW" --vpc-id "$VPC_ID"
  fi
fi

# Create SSH Key Pair if missing locally
KEY_FILE="${LOCAL_KEY_DIR}/${SSH_KEY_NAME}.pem"
mkdir -p "$LOCAL_KEY_DIR"
if [[ ! -f "$KEY_FILE" ]]; then
  aws ec2 create-key-pair "${AWS_ARGS[@]}" --key-name "$SSH_KEY_NAME" --key-type ed25519 \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "Created SSH key: $KEY_FILE"
fi

# Create Security Group
SG_NAME="${PROJECT_NAME}-sg"
SG_ID=$(aws ec2 create-security-group "${AWS_ARGS[@]}" \
  --group-name "$SG_NAME" \
  --description "${PROJECT_NAME} Minecraft Fabric SMP" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SG_NAME}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress "${AWS_ARGS[@]}" --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${SSH_ALLOWED_CIDR},Description=Admin SSH}]" \
    "IpProtocol=tcp,FromPort=25565,ToPort=25565,IpRanges=[{CidrIp=0.0.0.0/0,Description=Minecraft Java}]" > /dev/null

# Launch EC2 instance
INSTANCE_ID=$(aws ec2 run-instances "${AWS_ARGS[@]}" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$SSH_KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --instance-initiated-shutdown-behavior stop \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${EBS_VOLUME_SIZE},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":${EBS_DELETE_ON_TERMINATION},\"Encrypted\":true}}]" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}},{Key=Project,Value=${PROJECT_NAME}}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-root},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "Launched EC2 Instance: $INSTANCE_ID"

aws ec2 wait instance-running "${AWS_ARGS[@]}" --instance-ids "$INSTANCE_ID"

if [[ "$ALLOCATE_ELASTIC_IP" == "true" ]]; then
  EIP_ALLOC=$(aws ec2 allocate-address "${AWS_ARGS[@]}" --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT_NAME}-eip},{Key=Project,Value=${PROJECT_NAME}}]" \
    --query 'AllocationId' --output text)
  aws ec2 associate-address "${AWS_ARGS[@]}" --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC" > /dev/null
fi

PUBLIC_IP=$(aws ec2 describe-instances "${AWS_ARGS[@]}" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Public IP: $PUBLIC_IP"

# Optional Friend IAM Policy + Role + User
if [[ "$CREATE_FRIEND_IAM" == "true" ]]; then
  INSTANCE_ARN="arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:instance/${INSTANCE_ID}"
  POL_NAME="${FRIEND_IAM_PREFIX}-operator-policy"
  ROLE_NAME="${FRIEND_IAM_PREFIX}-operator-role"
  USR_NAME="${FRIEND_IAM_PREFIX}-friend"
  POL_ARN=$(aws iam create-policy --profile "$AWS_PROFILE" --policy-name "$POL_NAME" \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2:StartInstances\",\"ec2:StopInstances\"],\"Resource\":\"${INSTANCE_ARN}\"},{\"Effect\":\"Allow\",\"Action\":[\"ec2:DescribeInstances\",\"ec2:DescribeInstanceStatus\"],\"Resource\":\"*\"}]}" \
    --query 'Policy.Arn' --output text)
  ROLE_ARN=$(aws iam create-role --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" \
    --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::${ACCOUNT_ID}:root\"},\"Action\":\"sts:AssumeRole\"}]}" \
    --query 'Role.Arn' --output text)
  aws iam attach-role-policy --profile "$AWS_PROFILE" --role-name "$ROLE_NAME" --policy-arn "$POL_ARN"
  aws iam create-user --profile "$AWS_PROFILE" --user-name "$USR_NAME" > /dev/null
  aws iam put-user-policy --profile "$AWS_PROFILE" --user-name "$USR_NAME" --policy-name "Assume${ROLE_NAME}" \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Resource\":\"${ROLE_ARN}\"}]}"
  CRED_OUT="$HOME/.aws/${PROJECT_NAME}-friend-credentials.json"
  umask 077
  aws iam create-access-key --profile "$AWS_PROFILE" --user-name "$USR_NAME" > "$CRED_OUT"
  chmod 600 "$CRED_OUT"
  echo "Friend IAM Role: $ROLE_ARN (credentials saved privately to $CRED_OUT)"
fi

# Optional Budget Alert
if [[ "$CREATE_BUDGET_ALERT" == "true" && -n "$BUDGET_EMAIL" ]]; then
  aws budgets create-budget --profile "$AWS_PROFILE" --account-id "$ACCOUNT_ID" \
    --budget "{\"BudgetName\":\"${PROJECT_NAME}-Monthly-Budget\",\"BudgetLimit\":{\"Amount\":\"${BUDGET_AMOUNT_USD}\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\",\"CostTypes\":{\"IncludeTax\":true,\"IncludeSubscription\":true,\"UseBlended\":false,\"IncludeRefund\":true,\"IncludeCredit\":false,\"IncludeUpfront\":true,\"IncludeRecurring\":true,\"IncludeOtherSubscription\":true,\"IncludeSupport\":true,\"IncludeDiscount\":true,\"UseAmortized\":false}}" \
    --notifications-with-subscribers "[{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${BUDGET_EMAIL}\"}]}]" || true
fi

# Wait for SSH
echo "Waiting for SSH on ${PUBLIC_IP}..."
for _ in $(seq 1 30); do
  if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes "ec2-user@${PUBLIC_IP}" "true" 2>/dev/null; then
    break
  fi
  sleep 4
done

# Upload scripts, systemd units, and bootstrap env
BOOTSTRAP_ENV=$(mktemp)
cat > "$BOOTSTRAP_ENV" << EOF
MC_VERSION="${RESOLVED_MC}"
FABRIC_LOADER_VERSION="${FABRIC_LOADER_VER}"
FABRIC_INSTALLER_VERSION="${FABRIC_INST_VER}"
JAVA_VERSION="${RESOLVED_JAVA}"
HEAP_MB="${HEAP_MB}"
GC_MODE="${GC_MODE}"
MC_MOTD="${MC_MOTD}"
MC_DIFFICULTY="${MC_DIFFICULTY}"
MC_GAMEMODE="${MC_GAMEMODE}"
MC_MAX_PLAYERS="${MC_MAX_PLAYERS}"
MC_VIEW_DISTANCE="${MC_VIEW_DISTANCE}"
MC_SIM_DISTANCE="${MC_SIM_DISTANCE}"
MC_WHITELIST="${MC_WHITELIST}"
MC_SEED="${MC_SEED}"
MC_SPAWN_PROTECTION="${MC_SPAWN_PROTECTION}"
MC_PAUSE_EMPTY_SECONDS="${MC_PAUSE_EMPTY_SECONDS}"
IDLE_TIMEOUT_SECONDS="${IDLE_TIMEOUT_SECONDS}"
IDLE_CHECK_INTERVAL="${IDLE_CHECK_INTERVAL}"
IDLE_BOOT_GRACE="${IDLE_BOOT_GRACE}"
EOF

SCP_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
scp "${SCP_OPTS[@]}" \
  "$BOOTSTRAP_ENV" \
  "${REPO_ROOT}/template/resolve_mods.py" \
  "${REPO_ROOT}/template/fetch_datapacks.py" \
  "${REPO_ROOT}/template/bootstrap-ec2.sh" \
  "${REPO_ROOT}/systemd/"* \
  "ec2-user@${PUBLIC_IP}:/tmp/"
mv_env_cmd="mv /tmp/$(basename "$BOOTSTRAP_ENV") /tmp/mc-bootstrap.env"
scp "${SCP_OPTS[@]}" "${REPO_ROOT}/${MOD_LIST_FILE}" "ec2-user@${PUBLIC_IP}:/tmp/server-mods.txt"
if [[ -n "$VANILLATWEAKS_CONFIG" && -f "${REPO_ROOT}/${VANILLATWEAKS_CONFIG}" ]]; then
  scp "${SCP_OPTS[@]}" "${REPO_ROOT}/${VANILLATWEAKS_CONFIG}" "ec2-user@${PUBLIC_IP}:/tmp/vanillatweaks.json"
fi
ssh "${SCP_OPTS[@]}" "ec2-user@${PUBLIC_IP}" "mkdir -p /home/ec2-user/minecraft/scripts && $mv_env_cmd"
scp "${SCP_OPTS[@]}" "${REPO_ROOT}/scripts/"* "ec2-user@${PUBLIC_IP}:/home/ec2-user/minecraft/scripts/"
rm -f "$BOOTSTRAP_ENV"

ssh "${SCP_OPTS[@]}" "ec2-user@${PUBLIC_IP}" "bash /tmp/bootstrap-ec2.sh && rm -f /tmp/bootstrap-ec2.sh"

# Write local CLI config
mkdir -p "$(dirname "$LOCAL_CLI_CONFIG")"
cat > "$LOCAL_CLI_CONFIG" << EOF
AWS_REGION="${AWS_REGION}"
AWS_PROFILE="${AWS_PROFILE}"
INSTANCE_ID="${INSTANCE_ID}"
SSH_KEY="${KEY_FILE}"
SSH_USER="ec2-user"
MC_PORT="25565"
MC_DIR="/home/ec2-user/minecraft"
POLL_INTERVAL=5
SSH_WAIT_TIMEOUT=120
MC_WAIT_TIMEOUT=120
EC2_WAIT_TIMEOUT=180
EOF
cp "${REPO_ROOT}/cli/mc-server.sh" "$LOCAL_CLI_PATH"
chmod +x "$LOCAL_CLI_PATH"
mkdir -p "$HOME/.local/bin"
ln -sf "$LOCAL_CLI_PATH" "$HOME/.local/bin/mc-server"

echo ""
echo "=================================================================="
echo "Deployment complete! Connect in Minecraft ${RESOLVED_MC} at: ${PUBLIC_IP}:25565"
echo "Local CLI: mc-server status | start | stop | restart | logs | health"
echo "=================================================================="
