import * as cdk from "aws-cdk-lib";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";
import { PROJECT_NAME, TAGS } from "../config/constants";

export interface CiStackProps extends cdk.StackProps {
  /** GitHub org/repo, e.g. "llmvault/llmvault" */
  githubRepo: string;
}

export class CiStack extends cdk.Stack {
  public readonly deployRole: iam.Role;

  constructor(scope: Construct, id: string, props: CiStackProps) {
    super(scope, id, props);

    const { githubRepo } = props;

    // -------------------------------------------------------------------
    // GitHub OIDC Provider
    // -------------------------------------------------------------------
    const oidcProvider = new iam.OpenIdConnectProvider(
      this,
      "GitHubOidc",
      {
        url: "https://token.actions.githubusercontent.com",
        clientIds: ["sts.amazonaws.com"],
        thumbprints: ["6938fd4d98bab03faadb97b34396831e3780aea1"],
      }
    );

    // -------------------------------------------------------------------
    // Deploy Role — assumed by GitHub Actions via OIDC
    // -------------------------------------------------------------------
    this.deployRole = new iam.Role(this, "DeployRole", {
      roleName: `${PROJECT_NAME}-github-deploy`,
      assumedBy: new iam.WebIdentityPrincipal(
        oidcProvider.openIdConnectProviderArn,
        {
          StringEquals: {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          },
          StringLike: {
            "token.actions.githubusercontent.com:sub": `repo:${githubRepo}:*`,
          },
        }
      ),
      maxSessionDuration: cdk.Duration.hours(1),
    });

    // Allow updating ECS services (force new deployment)
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          "ecs:UpdateService",
          "ecs:DescribeServices",
        ],
        resources: [
          `arn:aws:ecs:${this.region}:${this.account}:service/${PROJECT_NAME}-*/*`,
        ],
      })
    );

    // -------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------
    new cdk.CfnOutput(this, "DeployRoleArn", {
      value: this.deployRole.roleArn,
      description: "IAM role ARN for GitHub Actions OIDC — use in workflow",
    });

    // -------------------------------------------------------------------
    // Tags
    // -------------------------------------------------------------------
    Object.entries(TAGS).forEach(([k, v]) => cdk.Tags.of(this).add(k, v));
  }
}
