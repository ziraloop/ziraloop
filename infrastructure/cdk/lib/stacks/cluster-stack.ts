import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as elbv2 from "aws-cdk-lib/aws-elasticloadbalancingv2";
import * as acm from "aws-cdk-lib/aws-certificatemanager";
import { Construct } from "constructs";
import {
  EnvironmentConfig,
  envDomain,
  subdomain,
} from "../config/environments";
import { PROJECT_NAME, TAGS } from "../config/constants";

export interface ClusterStackProps extends cdk.StackProps {
  config: EnvironmentConfig;
  vpc: ec2.IVpc;
  albSecurityGroup: ec2.ISecurityGroup;
}

export class ClusterStack extends cdk.Stack {
  public readonly cluster: ecs.ICluster;
  public readonly alb: elbv2.IApplicationLoadBalancer;
  public readonly httpsListener: elbv2.IApplicationListener;
  public readonly certificate: acm.ICertificate;
  public readonly apiTargetGroup: elbv2.ApplicationTargetGroup;
  public readonly zitadelTargetGroup: elbv2.ApplicationTargetGroup;
  public readonly zitadelLoginTargetGroup: elbv2.ApplicationTargetGroup;
  constructor(scope: Construct, id: string, props: ClusterStackProps) {
    super(scope, id, props);

    const { config, vpc, albSecurityGroup } = props;
    const prefix = `${PROJECT_NAME}-${config.name}`;
    const domain = envDomain(config);

    // -------------------------------------------------------------------
    // ECS Cluster
    // -------------------------------------------------------------------
    this.cluster = new ecs.Cluster(this, "Cluster", {
      clusterName: prefix,
      vpc,
      containerInsightsV2: config.enableContainerInsights
        ? ecs.ContainerInsights.ENHANCED
        : ecs.ContainerInsights.DISABLED,
    });

    // -------------------------------------------------------------------
    // ACM Certificate — DNS-validated wildcard for the env domain
    // Since domain is on Cloudflare, validation is manual.
    // CDK will output the CNAME records you need to add.
    // -------------------------------------------------------------------
    const sans = [
      subdomain(config, "auth"),
      subdomain(config, "api"),
      subdomain(config, "connect"),
      subdomain(config, "proxy"),
    ];

    this.certificate = new acm.Certificate(this, "Certificate", {
      domainName: domain,
      subjectAlternativeNames: sans,
      validation: acm.CertificateValidation.fromDns(), // no hosted zone — manual
    });

    // -------------------------------------------------------------------
    // Application Load Balancer
    // -------------------------------------------------------------------
    this.alb = new elbv2.ApplicationLoadBalancer(this, "Alb", {
      loadBalancerName: prefix,
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
    });

    // HTTP listener — redirect to HTTPS
    this.alb.addListener("HttpRedirect", {
      port: 80,
      defaultAction: elbv2.ListenerAction.redirect({
        protocol: "HTTPS",
        port: "443",
        permanent: true,
      }),
    });

    // HTTPS listener — default 404
    this.httpsListener = this.alb.addListener("Https", {
      port: 443,
      certificates: [this.certificate],
      defaultAction: elbv2.ListenerAction.fixedResponse(404, {
        contentType: "text/plain",
        messageBody: "Not Found",
      }),
    });

    // -------------------------------------------------------------------
    // Target Groups (empty — services register into these)
    // -------------------------------------------------------------------

    // API target group: api.llmvault.dev (or api.dev.llmvault.dev)
    this.apiTargetGroup = new elbv2.ApplicationTargetGroup(
      this,
      "ApiTargetGroup",
      {
        targetGroupName: `${prefix}-api`,
        vpc,
        port: 8080,
        protocol: elbv2.ApplicationProtocol.HTTP,
        targetType: elbv2.TargetType.IP,
        healthCheck: {
          path: "/healthz",
          interval: cdk.Duration.seconds(30),
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
        deregistrationDelay: cdk.Duration.seconds(30),
      }
    );

    this.httpsListener.addTargetGroups("ApiRule", {
      targetGroups: [this.apiTargetGroup],
      priority: 10,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([subdomain(config, "api")]),
      ],
    });

    // Proxy subdomain → same API target group
    // proxy.llmvault.dev routes to the API service (handles /v1/proxy)
    this.httpsListener.addTargetGroups("ProxyRule", {
      targetGroups: [this.apiTargetGroup],
      priority: 11,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([subdomain(config, "proxy")]),
      ],
    });

    // ZITADEL target group: auth.llmvault.dev
    this.zitadelTargetGroup = new elbv2.ApplicationTargetGroup(
      this,
      "ZitadelTargetGroup",
      {
        vpc,
        port: 8080,
        protocol: elbv2.ApplicationProtocol.HTTP,
        protocolVersion: elbv2.ApplicationProtocolVersion.HTTP2,
        targetType: elbv2.TargetType.IP,
        healthCheck: {
          path: "/debug/ready",
          interval: cdk.Duration.seconds(30),
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
        deregistrationDelay: cdk.Duration.seconds(30),
      }
    );

    // ZITADEL needs gRPC-web support — enable stickiness
    this.zitadelTargetGroup.setAttribute(
      "stickiness.enabled",
      "true"
    );
    this.zitadelTargetGroup.setAttribute(
      "stickiness.type",
      "lb_cookie"
    );
    this.zitadelTargetGroup.setAttribute(
      "stickiness.lb_cookie.duration_seconds",
      "86400"
    );

    // ZITADEL Login v2 target group: auth.llmvault.dev/ui/v2/login/*
    // Must be HIGHER priority (lower number) than the catch-all ZITADEL rule
    this.zitadelLoginTargetGroup = new elbv2.ApplicationTargetGroup(
      this,
      "ZitadelLoginTargetGroup",
      {
        targetGroupName: `${prefix}-zitadel-login`,
        vpc,
        port: 3000,
        protocol: elbv2.ApplicationProtocol.HTTP,
        targetType: elbv2.TargetType.IP,
        healthCheck: {
          path: "/ui/v2/login/healthy",
          interval: cdk.Duration.seconds(30),
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
        deregistrationDelay: cdk.Duration.seconds(30),
      }
    );

    this.httpsListener.addTargetGroups("ZitadelLoginRule", {
      targetGroups: [this.zitadelLoginTargetGroup],
      priority: 15,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([subdomain(config, "auth")]),
        elbv2.ListenerCondition.pathPatterns(["/ui/v2/login", "/ui/v2/login/*"]),
      ],
    });

    // ZITADEL API catch-all: auth.llmvault.dev (everything except /ui/v2/login/*)
    this.httpsListener.addTargetGroups("ZitadelRule", {
      targetGroups: [this.zitadelTargetGroup],
      priority: 20,
      conditions: [
        elbv2.ListenerCondition.hostHeaders([subdomain(config, "auth")]),
      ],
    });

    // -------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------
    new cdk.CfnOutput(this, "AlbDnsName", {
      value: this.alb.loadBalancerDnsName,
      description:
        "ALB DNS name — create CNAME records in Cloudflare pointing to this",
    });

    new cdk.CfnOutput(this, "CertificateArn", {
      value: this.certificate.certificateArn,
      description:
        "ACM certificate ARN — add DNS validation records in Cloudflare",
    });

    // -------------------------------------------------------------------
    // Tags
    // -------------------------------------------------------------------
    cdk.Tags.of(this).add("Environment", config.name);
    Object.entries(TAGS).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));
  }
}
