import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { Construct } from "constructs";
import { EnvironmentConfig } from "../config/environments";
import { PROJECT_NAME, TAGS } from "../config/constants";

export interface NetworkStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
}

export class NetworkStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly ecsSecurityGroup: ec2.ISecurityGroup;
  public readonly albSecurityGroup: ec2.ISecurityGroup;

  constructor(scope: Construct, id: string, props: NetworkStackProps) {
    super(scope, id, props);

    const { config } = props;
    const prefix = `${PROJECT_NAME}-${config.name}`;

    // -------------------------------------------------------------------
    // VPC — 2 AZs, public + private subnets, single NAT for cost
    // -------------------------------------------------------------------
    this.vpc = new ec2.Vpc(this, "Vpc", {
      vpcName: prefix,
      ipAddresses: ec2.IpAddresses.cidr(config.vpcCidr),
      maxAzs: config.maxAzs,
      natGateways: config.enableNatGateway ? 1 : 0,
      subnetConfiguration: [
        {
          name: "Public",
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: "Private",
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // -------------------------------------------------------------------
    // Security Groups
    // -------------------------------------------------------------------

    // ALB — accepts 80/443 from the internet
    this.albSecurityGroup = new ec2.SecurityGroup(this, "AlbSg", {
      vpc: this.vpc,
      securityGroupName: `${prefix}-alb`,
      description: "ALB - public HTTP/HTTPS",
      allowAllOutbound: true,
    });
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      "HTTP"
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      "HTTPS"
    );

    // ECS Tasks — only accepts traffic from ALB
    this.ecsSecurityGroup = new ec2.SecurityGroup(this, "EcsTasksSg", {
      vpc: this.vpc,
      securityGroupName: `${prefix}-ecs-tasks`,
      description: "ECS tasks - ALB ingress only",
      allowAllOutbound: true,
    });
    this.ecsSecurityGroup.addIngressRule(
      this.albSecurityGroup,
      ec2.Port.allTcp(),
      "All TCP from ALB"
    );

    // -------------------------------------------------------------------
    // Tags
    // -------------------------------------------------------------------
    cdk.Tags.of(this).add("Environment", config.name);
    Object.entries(TAGS).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));
  }
}
