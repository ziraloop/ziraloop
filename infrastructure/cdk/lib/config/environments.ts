import { AWS_ACCOUNT, AWS_REGION, DOMAIN_NAME } from "./constants";

export interface EnvironmentConfig {
  /** Environment name: "prod" | "dev" */
  name: string;

  /** AWS account + region */
  account: string;
  region: string;

  /** Domain configuration */
  domain: string;
  subdomainPrefix: string; // "" for prod, "dev" for dev

  /** VPC */
  vpcCidr: string;
  maxAzs: number;

  /** RDS */
  rdsInstanceClass: string;
  rdsAllocatedStorage: number;
  rdsMaxAllocatedStorage: number;
  rdsBackupRetentionDays: number;
  rdsDeletionProtection: boolean;
  rdsMultiAz: boolean;

  /** ElastiCache */
  cacheNodeType: string;

  /** ECS */
  zitadelCpu: number;
  zitadelMemory: number;
  zitadelDesiredCount: number;

  apiCpu: number;
  apiMemory: number;
  apiDesiredCount: number;

  /** Feature flags */
  enableContainerInsights: boolean;
  enableNatGateway: boolean;
}

/** Helper to build full subdomain: "auth.llmvault.dev" or "auth.dev.llmvault.dev" */
export function subdomain(
  config: EnvironmentConfig,
  sub: string
): string {
  if (config.subdomainPrefix) {
    return `${sub}.${config.subdomainPrefix}.${config.domain}`;
  }
  return `${sub}.${config.domain}`;
}

/** The "apex" for this env: "llmvault.dev" or "dev.llmvault.dev" */
export function envDomain(config: EnvironmentConfig): string {
  if (config.subdomainPrefix) {
    return `${config.subdomainPrefix}.${config.domain}`;
  }
  return config.domain;
}

// ---------------------------------------------------------------------------
// Environment definitions
// ---------------------------------------------------------------------------

export const prodConfig: EnvironmentConfig = {
  name: "prod",
  account: AWS_ACCOUNT,
  region: AWS_REGION,
  domain: DOMAIN_NAME,
  subdomainPrefix: "",

  // VPC
  vpcCidr: "10.0.0.0/16",
  maxAzs: 2,

  // RDS
  rdsInstanceClass: "db.t4g.micro",
  rdsAllocatedStorage: 20,
  rdsMaxAllocatedStorage: 100,
  rdsBackupRetentionDays: 7,
  rdsDeletionProtection: true,
  rdsMultiAz: false,

  // ElastiCache
  cacheNodeType: "cache.t4g.micro",

  // ECS - ZITADEL
  zitadelCpu: 256,
  zitadelMemory: 1024,
  zitadelDesiredCount: 1,

  // ECS - API
  apiCpu: 256,
  apiMemory: 512,
  apiDesiredCount: 1,

  // Features
  enableContainerInsights: true,
  enableNatGateway: true,
};

export const devConfig: EnvironmentConfig = {
  name: "dev",
  account: AWS_ACCOUNT,
  region: AWS_REGION,
  domain: DOMAIN_NAME,
  subdomainPrefix: "dev",

  // VPC
  vpcCidr: "10.1.0.0/16",
  maxAzs: 2,

  // RDS
  rdsInstanceClass: "db.t4g.micro",
  rdsAllocatedStorage: 20,
  rdsMaxAllocatedStorage: 50,
  rdsBackupRetentionDays: 1,
  rdsDeletionProtection: false,
  rdsMultiAz: false,

  // ElastiCache
  cacheNodeType: "cache.t4g.micro",

  // ECS - ZITADEL
  zitadelCpu: 256,
  zitadelMemory: 1024,
  zitadelDesiredCount: 1,

  // ECS - API
  apiCpu: 256,
  apiMemory: 512,
  apiDesiredCount: 1,

  // Features
  enableContainerInsights: true,
  enableNatGateway: true,
};
