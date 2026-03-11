import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as elbv2 from "aws-cdk-lib/aws-elasticloadbalancingv2";
import * as logs from "aws-cdk-lib/aws-logs";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as kms from "aws-cdk-lib/aws-kms";
import { Construct } from "constructs";
import {
  EnvironmentConfig,
  subdomain,
} from "../config/environments";
import { PROJECT_NAME, TAGS } from "../config/constants";

export interface ApiStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  vpc: ec2.IVpc;
  cluster: ecs.ICluster;
  ecsSecurityGroup: ec2.ISecurityGroup;
  apiTargetGroup: elbv2.IApplicationTargetGroup;
  dbSecret: cdk.aws_secretsmanager.ISecret;
  dbEndpoint: string;
  redisEndpoint: string;
  redisPort: string;
  zitadelDomain: string;
}

export class ApiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    const { config, vpc, cluster, ecsSecurityGroup } = props;
    const prefix = `${PROJECT_NAME}-${config.name}`;

    // -------------------------------------------------------------------
    // KMS key for envelope encryption (replaces dev AEAD)
    // -------------------------------------------------------------------
    const kmsKey = new kms.Key(this, "KmsKey", {
      alias: `${prefix}/api-encryption`,
      description: `LLMVault ${config.name} API envelope encryption key`,
      enableKeyRotation: true,
    });

    // -------------------------------------------------------------------
    // Secrets
    // -------------------------------------------------------------------
    const jwtSigningKey = new secretsmanager.Secret(this, "JwtSigningKey", {
      secretName: `${prefix}/jwt-signing-key`,
      description: "JWT signing key for proxy tokens",
      generateSecretString: {
        passwordLength: 64,
        excludePunctuation: true,
      },
    });

    // -------------------------------------------------------------------
    // Task Definition
    // -------------------------------------------------------------------

    const taskDef = new ecs.FargateTaskDefinition(this, "TaskDef", {
      family: `${prefix}-api`,
      cpu: config.apiCpu,
      memoryLimitMiB: config.apiMemory,
      runtimePlatform: {
        cpuArchitecture: ecs.CpuArchitecture.ARM64,
        operatingSystemFamily: ecs.OperatingSystemFamily.LINUX,
      },
    });

    // KMS grant on task role (used at runtime by the app)
    kmsKey.grantEncryptDecrypt(taskDef.taskRole);
    // Note: execution role grants for secrets are handled automatically
    // by CDK when using ecs.Secret.fromSecretsManager() in container defs.

    const logGroup = new logs.LogGroup(this, "Logs", {
      logGroupName: `/ecs/${prefix}/api`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    taskDef.addContainer("api", {
      containerName: "api",
      image: ecs.ContainerImage.fromRegistry("ghcr.io/llmvault/llmvault:latest"),
      portMappings: [{ containerPort: 8080, protocol: ecs.Protocol.TCP }],
      environment: {
        // Server
        PORT: "8080",
        ENVIRONMENT: config.name,

        // Database — built from secret at runtime
        DB_HOST: props.dbEndpoint,
        DB_PORT: "5432",
        DB_NAME: "llmvault",
        DB_SSLMODE: "require",

        // Redis
        REDIS_ADDR: `${props.redisEndpoint}:${props.redisPort}`,

        // KMS — AWS KMS for production envelope encryption
        KMS_TYPE: "awskms",
        KMS_KEY: kmsKey.keyArn,
        AWS_REGION: config.region,

        // ZITADEL
        ZITADEL_DOMAIN: props.zitadelDomain,
        ZITADEL_PORT: "443",
        ZITADEL_SECURE: "true",
      },
      secrets: {
        DB_USERNAME: ecs.Secret.fromSecretsManager(props.dbSecret, "username"),
        DB_PASSWORD: ecs.Secret.fromSecretsManager(props.dbSecret, "password"),
        JWT_SIGNING_KEY: ecs.Secret.fromSecretsManager(jwtSigningKey),
      },
      logging: ecs.LogDrivers.awsLogs({
        logGroup,
        streamPrefix: "api",
      }),
      // No container health check — distroless image has no shell.
      // ALB target group health check at /healthz handles liveness.
    });

    // -------------------------------------------------------------------
    // Fargate Service
    // -------------------------------------------------------------------

    const service = new ecs.FargateService(this, "Service", {
      serviceName: `${prefix}-api`,
      cluster,
      taskDefinition: taskDef,
      desiredCount: config.apiDesiredCount,
      securityGroups: [ecsSecurityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      assignPublicIp: false,
      circuitBreaker: { enable: true, rollback: true },
      enableExecuteCommand: true,
    });

    service.attachToApplicationTargetGroup(
      props.apiTargetGroup as elbv2.ApplicationTargetGroup
    );

    // -------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------
    new cdk.CfnOutput(this, "KmsKeyArn", {
      value: kmsKey.keyArn,
      description: "KMS key ARN for envelope encryption",
    });

    // -------------------------------------------------------------------
    // Tags
    // -------------------------------------------------------------------
    cdk.Tags.of(this).add("Environment", config.name);
    Object.entries(TAGS).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));
  }
}
