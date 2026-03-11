export const PROJECT_NAME = "llmvault";

export const AWS_ACCOUNT = process.env.CDK_DEFAULT_ACCOUNT!;
export const AWS_REGION = "us-east-2";

export const DOMAIN_NAME = "llmvault.dev";

export const TAGS = {
  Project: PROJECT_NAME,
  ManagedBy: "cdk",
} as const;
