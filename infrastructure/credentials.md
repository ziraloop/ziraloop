

```bash
# run this command to generate env
aws configure export-credentials --format env

# copy and store env in .env file

# run this command to activate env variables in shell
eval $(cat .env)
```

To get pat after deploying zitadel:

```txt
After Deploy: Get Admin PAT

# Check service is running
aws ecs describe-services --cluster llmvault-prod --services zitadel --region us-east-2

# Get admin PAT from logs
aws logs get-log-events \
--log-group-name /ecs/llmvault-prod/zitadel \
--log-stream-name <stream-name> \
--region us-east-2 | grep "admin.pat"

Or check the output:

terraform output zitadel_setup_instructions
```

Credentials for zitadel:

```md
Changes Made

Setting    Before                After
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Username   admin (predictable)   Random 12-char string (e.g., aB3xK9mPqR5n)
Email      admin@llmvault.dev    ops@llmvault.dev

New Secrets

llmvault-prod/zitadel-admin-username  → Random 12-char username
llmvault-prod/zitadel-admin-password  → 24-char secure password

Get Credentials After Deploy

# Get username (random)
aws secretsmanager get-secret-value \
--secret-id llmvault-prod/zitadel-admin-username \
--query SecretString --output text

# Get password
aws secretsmanager get-secret-value \
--secret-id llmvault-prod/zitadel-admin-password \
--query SecretString --output text

Login URL: https://auth.llmvault.dev
Email: ops@llmvault.dev

Deploy now:

eval "$(aws configure export-credentials --format env)"
cd infrastructure/environments/production
terraform apply
```