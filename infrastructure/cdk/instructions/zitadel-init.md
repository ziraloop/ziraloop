# ZITADEL Manual Initialization

ZITADEL requires a one-time database initialization (`start-from-init`) that creates the schema, first instance, admin users, and a machine user PAT. After init, it also needs a bootstrap script (`init.sh`) to create the project, API app, and OIDC dashboard app.

The ZITADEL container image is distroless (no shell), so we use a temporary EC2 bastion with Docker to run the init against the RDS instance.

## Prerequisites

- AWS CLI configured with credentials for the target account
- The following CDK stacks already deployed:
  - `LlmVault-{Env}-Network`
  - `LlmVault-{Env}-Data`
  - `LlmVault-{Env}-Cluster`
  - `LlmVault-{Env}-Zitadel` (with `desiredCount: 0`)

## Variables

Replace these throughout the guide:

| Variable | Dev Value | Prod Value |
|----------|-----------|------------|
| `ENV` | `dev` | `prod` |
| `VPC_ID` | `vpc-07d35ffc7e341c487` | _(from stack output)_ |
| `PUBLIC_SUBNET` | `subnet-096afda6cdb3ce605` | _(from stack output)_ |
| `RDS_HOST` | `llmvault-dev.cdo0comy6gzs.us-east-2.rds.amazonaws.com` | _(from stack output)_ |
| `AUTH_DOMAIN` | `auth.dev.llmvault.dev` | `auth.llmvault.dev` |
| `DASHBOARD_REDIRECT` | `https://dev.llmvault.dev/api/auth/callback/zitadel` | `https://llmvault.dev/api/auth/callback/zitadel` |
| `DASHBOARD_LOGOUT` | `https://dev.llmvault.dev` | `https://llmvault.dev` |
| `REGION` | `us-east-2` | `us-east-2` |

## Step 1: Find RDS Security Group

```bash
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier llmvault-$ENV \
  --region $REGION --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
echo "RDS SG: $RDS_SG"
```

## Step 2: Get Your Public IP

```bash
MY_IP=$(curl -s ifconfig.me)
echo "My IP: $MY_IP"
```

## Step 3: Create SSH Key Pair

```bash
aws ec2 create-key-pair --key-name llmvault-$ENV-bastion \
  --query 'KeyMaterial' --output text --region $REGION > /tmp/llmvault-bastion.pem
chmod 400 /tmp/llmvault-bastion.pem
```

## Step 4: Create Bastion Security Group

```bash
BASTION_SG=$(aws ec2 create-security-group \
  --group-name llmvault-$ENV-bastion \
  --description "Temporary bastion for ZITADEL init" \
  --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
echo "Bastion SG: $BASTION_SG"

aws ec2 authorize-security-group-ingress \
  --group-id $BASTION_SG --protocol tcp --port 22 \
  --cidr $MY_IP/32 --region $REGION
```

## Step 5: Allow Bastion to Reach RDS

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG --protocol tcp --port 5432 \
  --source-group $BASTION_SG --region $REGION
```

## Step 6: Create IAM Role for Bastion

```bash
aws iam create-role --role-name llmvault-$ENV-bastion-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam put-role-policy --role-name llmvault-$ENV-bastion-role \
  --policy-name secrets-readwrite \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"],
      "Resource": "arn:aws:secretsmanager:'$REGION':*:secret:llmvault-'$ENV'/*"
    }]
  }'

aws iam create-instance-profile --instance-profile-name llmvault-$ENV-bastion-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name llmvault-$ENV-bastion-profile \
  --role-name llmvault-$ENV-bastion-role

# Wait 10s for IAM propagation
sleep 10
```

## Step 7: Launch EC2 Bastion

```bash
AMI=$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-arm64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text --region $REGION)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI --instance-type t4g.micro \
  --key-name llmvault-$ENV-bastion \
  --subnet-id $PUBLIC_SUBNET \
  --security-group-ids $BASTION_SG \
  --iam-instance-profile Name=llmvault-$ENV-bastion-profile \
  --associate-public-ip-address \
  --user-data '#!/bin/bash
yum install -y docker jq postgresql16
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=llmvault-$ENV-bastion}]" \
  --region $REGION --query 'Instances[0].InstanceId' --output text)
echo "Instance: $INSTANCE_ID"

aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

BASTION_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Bastion IP: $BASTION_IP"
```

Wait ~30 seconds for user-data to finish, then verify:

```bash
ssh -o StrictHostKeyChecking=no -i /tmp/llmvault-bastion.pem ec2-user@$BASTION_IP "docker --version"
```

## Step 8: Phase A — ZITADEL Database Init

SSH into the bastion and run:

```bash
ssh -i /tmp/llmvault-bastion.pem ec2-user@$BASTION_IP
```

On the bastion:

```bash
REGION="us-east-2"
ENV="dev"  # or "prod"
RDS_HOST="<rds-endpoint>"
AUTH_DOMAIN="<auth-domain>"

# Fetch secrets (no credentials exposed — IAM role handles auth)
MASTERKEY=$(aws secretsmanager get-secret-value --secret-id llmvault-$ENV/zitadel-masterkey --region $REGION --query SecretString --output text)
ZIT_DB_PASS=$(aws secretsmanager get-secret-value --secret-id llmvault-$ENV/zitadel-db-password --region $REGION --query SecretString --output text)
RDS_PASS=$(aws secretsmanager get-secret-value --secret-id llmvault-$ENV/rds-credentials --region $REGION --query SecretString --output text | jq -r .password)
ADMIN_PASS=$(aws secretsmanager get-secret-value --secret-id llmvault-$ENV/zitadel-admin-password --region $REGION --query SecretString --output text)

# Create host dir for PAT (ZITADEL image is distroless, can't create files)
mkdir -p /tmp/zitadel-pat

# Run ZITADEL start-from-init
sudo docker run -d --name zitadel-init \
  -v /tmp/zitadel-pat:/tmp \
  -p 8080:8080 \
  -e ZITADEL_MASTERKEY="$MASTERKEY" \
  -e ZITADEL_EXTERNALDOMAIN="$AUTH_DOMAIN" \
  -e ZITADEL_EXTERNALPORT=443 \
  -e ZITADEL_EXTERNALSECURE=true \
  -e ZITADEL_TLS_ENABLED=false \
  -e ZITADEL_DATABASE_POSTGRES_HOST="$RDS_HOST" \
  -e ZITADEL_DATABASE_POSTGRES_PORT=5432 \
  -e ZITADEL_DATABASE_POSTGRES_DATABASE=zitadel \
  -e ZITADEL_DATABASE_POSTGRES_USER_USERNAME=zitadel \
  -e ZITADEL_DATABASE_POSTGRES_USER_PASSWORD="$ZIT_DB_PASS" \
  -e ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME=llmvault \
  -e ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD="$RDS_PASS" \
  -e ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE=require \
  -e ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE=require \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME=admin \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_EMAIL=ops@llmvault.dev \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD="$ADMIN_PASS" \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORDCHANGEREQUIRED=false \
  -e ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_USERNAME=llmvault-admin \
  -e "ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_NAME=LLMVault Admin SA" \
  -e ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_EXPIRATIONDATE=2099-01-01T00:00:00Z \
  -e ZITADEL_FIRSTINSTANCE_PATPATH=/tmp/admin.pat \
  ghcr.io/zitadel/zitadel:v4.12.1 start-from-init --masterkeyFromEnv

# Wait for PAT file (2-5 minutes)
echo "Waiting for PAT..."
while [ ! -f /tmp/zitadel-pat/admin.pat ]; do sleep 2; done
echo "PAT found!"

# Store PAT in Secrets Manager
PAT=$(cat /tmp/zitadel-pat/admin.pat | tr -d '[:space:]')
aws secretsmanager put-secret-value \
  --secret-id llmvault-$ENV/zitadel-admin-pat \
  --secret-string "$PAT" --region $REGION
echo "PAT stored."
```

**Important:** The `-v /tmp/zitadel-pat:/tmp` volume mount is critical. The ZITADEL distroless image cannot create files on its own filesystem. Without this mount, the init will fail with `open /tmp/admin.pat: no such file or directory`.

### If init fails midway (AlreadyExists error)

If the init partially completed and you need to retry, reset the database:

```bash
RDS_PASS=$(aws secretsmanager get-secret-value --secret-id llmvault-$ENV/rds-credentials --region $REGION --query SecretString --output text | jq -r .password)
PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -U llmvault -d llmvault -c "DROP DATABASE IF EXISTS zitadel;"
PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -U llmvault -d llmvault -c "DROP ROLE IF EXISTS zitadel;"
sudo docker rm -f zitadel-init
rm -f /tmp/zitadel-pat/admin.pat
```

Then re-run the `docker run` command from Phase A.

## Step 9: Phase B — Bootstrap Project & Apps

Still on the bastion, with ZITADEL still running in Docker on port 8080:

```bash
# Run init.sh in an Alpine container (has curl/jq)
sudo docker run --rm --network host \
  -v /path/to/docker/zitadel/init.sh:/scripts/init.sh:ro \
  -v /tmp/zitadel-pat:/zitadel/bootstrap:ro \
  -e ZITADEL_URL=http://localhost:8080 \
  -e ZITADEL_EXTERNAL_URL=https://$AUTH_DOMAIN \
  -e ZITADEL_HOST_HEADER=$AUTH_DOMAIN \
  -e DASHBOARD_REDIRECT_URI=<dashboard-redirect-uri> \
  -e DASHBOARD_LOGOUT_URI=<dashboard-logout-uri> \
  -e ZITADEL_PAT_FILE=/zitadel/bootstrap/admin.pat \
  -e ZITADEL_DEV_MODE=true \
  alpine:3.19 sh /scripts/init.sh
```

Copy the init.sh to the bastion first:

```bash
# From your local machine
scp -i /tmp/llmvault-bastion.pem docker/zitadel/init.sh ec2-user@$BASTION_IP:/tmp/init.sh
```

Then on the bastion:

```bash
sudo docker run --rm --network host \
  -v /tmp/init.sh:/scripts/init.sh:ro \
  -v /tmp/zitadel-pat:/zitadel/bootstrap:ro \
  -e ZITADEL_URL=http://localhost:8080 \
  -e ZITADEL_EXTERNAL_URL=https://$AUTH_DOMAIN \
  -e ZITADEL_HOST_HEADER=$AUTH_DOMAIN \
  -e DASHBOARD_REDIRECT_URI=https://dev.llmvault.dev/api/auth/callback/zitadel \
  -e DASHBOARD_LOGOUT_URI=https://dev.llmvault.dev \
  -e ZITADEL_PAT_FILE=/zitadel/bootstrap/admin.pat \
  -e ZITADEL_DEV_MODE=true \
  alpine:3.19 sh /scripts/init.sh
```

The script outputs credentials. Store them in Secrets Manager:

```bash
aws secretsmanager put-secret-value --secret-id llmvault-$ENV/zitadel-project-id \
  --secret-string "<PROJECT_ID>" --region $REGION
aws secretsmanager put-secret-value --secret-id llmvault-$ENV/zitadel-api-client-id \
  --secret-string "<API_CLIENT_ID>" --region $REGION
aws secretsmanager put-secret-value --secret-id llmvault-$ENV/zitadel-api-client-secret \
  --secret-string "<API_CLIENT_SECRET>" --region $REGION
aws secretsmanager put-secret-value --secret-id llmvault-$ENV/zitadel-dashboard-client-id \
  --secret-string "<DASHBOARD_CLIENT_ID>" --region $REGION
```

## Step 10: Stop ZITADEL & Exit

```bash
sudo docker rm -f zitadel-init
exit
```

## Step 11: Cleanup Bastion

From your local machine:

```bash
# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION

# Revoke RDS access
aws ec2 revoke-security-group-ingress \
  --group-id $RDS_SG --protocol tcp --port 5432 \
  --source-group $BASTION_SG --region $REGION

# Delete security group
aws ec2 delete-security-group --group-id $BASTION_SG --region $REGION

# Delete key pair
aws ec2 delete-key-pair --key-name llmvault-$ENV-bastion --region $REGION
rm -f /tmp/llmvault-bastion.pem

# Delete IAM resources
aws iam remove-role-from-instance-profile \
  --instance-profile-name llmvault-$ENV-bastion-profile \
  --role-name llmvault-$ENV-bastion-role
aws iam delete-instance-profile --instance-profile-name llmvault-$ENV-bastion-profile
aws iam delete-role-policy --role-name llmvault-$ENV-bastion-role --policy-name secrets-readwrite
aws iam delete-role --role-name llmvault-$ENV-bastion-role
```

## Step 12: Scale Up Services

Update `desiredCount` from `0` to `1` in `zitadel-stack.ts` for both `ZitadelService` and `LoginService`, then:

```bash
cd infrastructure/cdk
npx cdk deploy LlmVault-Dev-Zitadel --require-approval never
```

## Secrets Reference

After completing all steps, these secrets should be populated:

| Secret | Source |
|--------|--------|
| `llmvault-{env}/zitadel-masterkey` | Auto-generated by CDK |
| `llmvault-{env}/zitadel-db-password` | Auto-generated by CDK |
| `llmvault-{env}/zitadel-admin-password` | Auto-generated by CDK |
| `llmvault-{env}/zitadel-admin-pat` | Phase A (start-from-init) |
| `llmvault-{env}/zitadel-project-id` | Phase B (init.sh) |
| `llmvault-{env}/zitadel-api-client-id` | Phase B (init.sh) |
| `llmvault-{env}/zitadel-api-client-secret` | Phase B (init.sh) |
| `llmvault-{env}/zitadel-dashboard-client-id` | Phase B (init.sh) |
