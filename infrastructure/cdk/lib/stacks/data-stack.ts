import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as rds from "aws-cdk-lib/aws-rds";
import * as elasticache from "aws-cdk-lib/aws-elasticache";
import { Construct } from "constructs";
import { EnvironmentConfig } from "../config/environments";
import { PROJECT_NAME, TAGS } from "../config/constants";

export interface DataStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  vpc: ec2.IVpc;
  ecsSecurityGroup: ec2.ISecurityGroup;
}

export class DataStack extends cdk.Stack {
  public readonly dbInstance: rds.DatabaseInstance;
  public readonly dbSecret: cdk.aws_secretsmanager.ISecret;
  public readonly redisEndpoint: string;
  public readonly redisPort: string;

  constructor(scope: Construct, id: string, props: DataStackProps) {
    super(scope, id, props);

    const { config, vpc, ecsSecurityGroup } = props;
    const prefix = `${PROJECT_NAME}-${config.name}`;

    // -------------------------------------------------------------------
    // RDS PostgreSQL 17
    // -------------------------------------------------------------------

    const dbSecurityGroup = new ec2.SecurityGroup(this, "DbSg", {
      vpc,
      securityGroupName: `${prefix}-rds`,
      description: "RDS - ECS tasks ingress only",
      allowAllOutbound: false,
    });
    dbSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcp(5432),
      "PostgreSQL from ECS tasks"
    );

    this.dbInstance = new rds.DatabaseInstance(this, "Postgres", {
      instanceIdentifier: prefix,
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_17,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T4G,
        ec2.InstanceSize.MICRO
      ),
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [dbSecurityGroup],

      databaseName: "llmvault",
      credentials: rds.Credentials.fromGeneratedSecret("llmvault", {
        secretName: `${prefix}/rds-credentials`,
      }),

      allocatedStorage: config.rdsAllocatedStorage,
      maxAllocatedStorage: config.rdsMaxAllocatedStorage,
      storageType: rds.StorageType.GP3,

      multiAz: config.rdsMultiAz,
      deletionProtection: config.rdsDeletionProtection,
      removalPolicy: config.rdsDeletionProtection
        ? cdk.RemovalPolicy.RETAIN
        : cdk.RemovalPolicy.DESTROY,

      backupRetention: cdk.Duration.days(config.rdsBackupRetentionDays),
      preferredBackupWindow: "03:00-04:00",
      preferredMaintenanceWindow: "Mon:04:00-Mon:05:00",

      publiclyAccessible: false,
      storageEncrypted: true,
    });

    this.dbSecret = this.dbInstance.secret!;

    // -------------------------------------------------------------------
    // ElastiCache Redis 7
    // -------------------------------------------------------------------

    const cacheSecurityGroup = new ec2.SecurityGroup(this, "CacheSg", {
      vpc,
      securityGroupName: `${prefix}-redis`,
      description: "Redis - ECS tasks ingress only",
      allowAllOutbound: false,
    });
    cacheSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcp(6379),
      "Redis from ECS tasks"
    );

    const cacheSubnetGroup = new elasticache.CfnSubnetGroup(
      this,
      "RedisSubnetGroup",
      {
        description: `${prefix} Redis subnet group`,
        cacheSubnetGroupName: `${prefix}-redis`,
        subnetIds: vpc.selectSubnets({
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }).subnetIds,
      }
    );

    const redis = new elasticache.CfnCacheCluster(this, "Redis", {
      clusterName: `${prefix}-redis`,
      engine: "redis",
      engineVersion: "7.1",
      cacheNodeType: config.cacheNodeType,
      numCacheNodes: 1,
      cacheSubnetGroupName: cacheSubnetGroup.cacheSubnetGroupName,
      vpcSecurityGroupIds: [cacheSecurityGroup.securityGroupId],
    });
    redis.addDependency(cacheSubnetGroup);

    this.redisEndpoint = redis.attrRedisEndpointAddress;
    this.redisPort = redis.attrRedisEndpointPort;

    // -------------------------------------------------------------------
    // Tags
    // -------------------------------------------------------------------
    cdk.Tags.of(this).add("Environment", config.name);
    Object.entries(TAGS).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));
  }
}
