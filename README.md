# PhnyX Lab – Senior Platform Engineer Take-home Assignment #1

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────┐
│  ALB: phnyx-alb                 │
│  phnyx-alb-72999925             │
│  .us-east-1.elb.amazonaws.com   │
│                                 │
│  /service1* → TG service1:5000  │
│  /service2* → TG service2:5001  │
└────────────┬────────────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
┌──────────┐    ┌──────────┐
│ EC2 #1   │    │ EC2 #2   │
│ instance1│    │ instance2│
│ 98.84.   │    │ 18.206.  │
│ 49.245   │    │ 87.98    │
│          │    │          │
│ service1 │    │ service1 │
│ :5000    │    │ :5000    │
│ service2 │    │ service2 │
│ :5001    │    │ :5001    │
└──────────┘    └──────────┘
       │               │
       └──────┬────────┘
              ▼
     ┌─────────────────┐
     │  Amazon ECR     │
     │  service1:latest│
     │  service2:latest│
     └─────────────────┘
              │
     ┌─────────────────┐
     │  test-PhnyX-vpc │
     │  10.0.0.0/16    │
     └─────────────────┘
```

## AWS Region
`us-east-1` (N. Virginia)

## Resources Created

| Resource | ID / Value |
|----------|-----------|
| VPC | vpc-05f8ec76aeb1a1599 |
| EC2 Instance 1 | i-079503dbd0478b951 (98.84.49.245) |
| EC2 Instance 2 | i-072d2b6bc0395030f (18.206.87.98) |
| ALB DNS | phnyx-alb-72999925.us-east-1.elb.amazonaws.com |
| ECR service1 | 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1 |
| ECR service2 | 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2 |
| Target Group 1 | phnyx-tg-service1 (port 5000) |
| Target Group 2 | phnyx-tg-service2 (port 5001) |

## Deployment Steps

### Stage A: Build and Push Docker Images to ECR

```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS \
  --password-stdin 219711034407.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repositories
aws ecr create-repository --repository-name service1 --region us-east-1
aws ecr create-repository --repository-name service2 --region us-east-1

# Build for linux/amd64 (required for EC2 compatibility from macOS)
docker buildx build --platform linux/amd64 \
  -t 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1:latest ./service1/
docker buildx build --platform linux/amd64 \
  -t 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2:latest ./service2/

# Push images
docker push 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1:latest
docker push 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2:latest
```

### Stage B: Launch EC2 Instances

Two `t2.micro` Ubuntu 24.04 instances launched in the same VPC and AZ.

```bash
aws ec2 run-instances \
  --image-id ami-0071174ad8cbb9e17 \
  --instance-type t2.micro \
  --key-name phnyx-key \
  --security-group-ids sg-013546579e5bb1c03 \
  --subnet-id subnet-0f670e7e023374a50 \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=phnyx-instance1}]'
```

Docker installed on each instance:
```bash
sudo apt-get install -y docker.io docker-compose-v2
sudo snap install aws-cli --classic
sudo systemctl start docker
```

### Stage C: Deploy via Docker Compose

On each EC2 instance:
```bash
# ECR login
aws ecr get-login-password --region us-east-1 | sudo docker login \
  --username AWS --password-stdin \
  219711034407.dkr.ecr.us-east-1.amazonaws.com

# Deploy
sudo docker compose -f ~/docker-compose.yml up -d
```

Both services run on every instance:
- service1 → port 5000
- service2 → port 5001

### Stage D: Application Load Balancer

ALB with path-based routing rules:
- `/service1*` → Target Group phnyx-tg-service1 (port 5000)
- `/service2*` → Target Group phnyx-tg-service2 (port 5001)

Both target groups show **healthy** status for both instances.

## Running the Verification Script

```bash
chmod +x verify_endpoints.sh
./verify_endpoints.sh
```

The script tests:
1. ALB path routing for `/service1` and `/service2`
2. Direct health checks on both EC2 instances (ports 5000, 5001)
3. ECR repository verification

Expected output:
```
✅ PASS: http://phnyx-alb-72999925.us-east-1.elb.amazonaws.com/service1
✅ PASS: http://phnyx-alb-72999925.us-east-1.elb.amazonaws.com/service2
✅ PASS: http://98.84.49.245:5000/health
✅ PASS: http://98.84.49.245:5001/health
✅ PASS: http://18.206.87.98:5000/health
✅ PASS: http://18.206.87.98:5001/health
Results: 6 passed, 0 failed
```

## Security Design

- ALB Security Group: allows 80/443 from 0.0.0.0/0
- EC2 Security Group: allows 22 (SSH) from admin IP only, 5000/5001 from anywhere
- IAM: AmazonEC2ContainerRegistryFullAccess attached to devops-engineer user (least-privilege per README guidance)
- No hardcoded secrets in containers; AWS credentials configured via `aws configure`

## Cleanup

All AWS resources to be torn down post-evaluation:
```bash
# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids i-079503dbd0478b951 i-072d2b6bc0395030f

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn <ALB_ARN>

# Delete Target Groups
aws elbv2 delete-target-group --target-group-arn <TG1_ARN>
aws elbv2 delete-target-group --target-group-arn <TG2_ARN>

# Delete ECR repositories
aws ecr delete-repository --repository-name service1 --force
aws ecr delete-repository --repository-name service2 --force
```
