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
│ (manual) │    │ (manual) │
│ 98.84.   │    │ 18.206.  │
│ 49.245   │    │ 87.98    │
├──────────┤    ├──────────┤
│ service1 │    │ service1 │
│ :5000    │    │ :5000    │
│ service2 │    │ service2 │
│ :5001    │    │ :5001    │
└──────────┘    └──────────┘

        ┌──────────────────────┐
        │  Auto Scaling Group  │
        │  phnyx-asg           │
        │  min=2 desired=2     │
        │  max=4               │
        │                      │
        │  Launch Template     │
        │  lt-0ea3384e06e61b533│
        │                      │
        │  Scale-out: CPU >40% │
        └──────────────────────┘
               │
     ┌─────────────────┐
     │  Amazon ECR     │
     │  service1:latest│
     │  service2:latest│
     └─────────────────┘
               │
     ┌─────────────────┐
     │  test-PhnyX-vpc │
     │  vpc-05f8ec76.. │
     │  us-east-1      │
     └─────────────────┘
```

## AWS Region
`us-east-1` (N. Virginia)

## Resources Created

| Resource | ID / Value |
|----------|-----------|
| VPC | vpc-05f8ec76aeb1a1599 |
| EC2 Instance 1 (manual) | i-079503dbd0478b951 (98.84.49.245) |
| EC2 Instance 2 (manual) | i-072d2b6bc0395030f (18.206.87.98) |
| ALB DNS | phnyx-alb-72999925.us-east-1.elb.amazonaws.com |
| ECR service1 | 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1 |
| ECR service2 | 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2 |
| Target Group 1 | phnyx-tg-service1 (port 5000) |
| Target Group 2 | phnyx-tg-service2 (port 5001) |
| Launch Template | lt-0ea3384e06e61b533 |
| Auto Scaling Group | phnyx-asg (min=2, desired=2, max=4) |
| IAM Role | phnyx-ec2-ecr-role (ECR read-only) |

## Repository Structure

```
.
├── README.md
├── docker-compose.yml        # Used on EC2 instances
├── verify_endpoints.sh       # Verification script (6/6 passing)
└── terraform/
    ├── main.tf               # IaC: Launch Template + ASG + IAM + scaling policy
    └── .gitignore
```

## Deployment Steps

### Stage A: Build and Push Docker Images to ECR

```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS \
  --password-stdin 219711034407.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repositories
aws ecr create-repository --repository-name service1 --region us-east-1
aws ecr create-repository --repository-name service2 --region us-east-1

# Build for linux/amd64 (required for EC2 compatibility from macOS ARM)
docker buildx build --platform linux/amd64 \
  -t 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1:latest ./service1/
docker buildx build --platform linux/amd64 \
  -t 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2:latest ./service2/

# Push images
docker push 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1:latest
docker push 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2:latest
```

### Stage B: Launch EC2 Instances

Two `t2.micro` Ubuntu 24.04 instances launched in the same VPC.

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

### Stage E: Verification Script

```bash
chmod +x verify_endpoints.sh
./verify_endpoints.sh
```

Results: **6 passed, 0 failed**

```
✅ PASS: http://phnyx-alb-72999925.us-east-1.elb.amazonaws.com/service1
         Response: {"message":"Hello from Service 1","user_info":"No user info provided"}
✅ PASS: http://phnyx-alb-72999925.us-east-1.elb.amazonaws.com/service2
         Response: {"message":"Hello from Service 2","user_info":"No user info provided"}
✅ PASS: http://98.84.49.245:5000/health   → {"status":"healthy"}
✅ PASS: http://98.84.49.245:5001/health   → {"status":"healthy"}
✅ PASS: http://18.206.87.98:5000/health   → {"status":"healthy"}
✅ PASS: http://18.206.87.98:5001/health   → {"status":"healthy"}
```

## Bonus: Terraform IaC

The `terraform/` directory contains a complete IaC implementation with:

**Launch Template** (`lt-0ea3384e06e61b533`):
- Ubuntu 24.04 AMI, t2.micro
- IAM instance profile with ECR read-only access (no hardcoded credentials)
- User-data script that on boot: installs Docker, authenticates to ECR via IAM role, writes docker-compose.yml, and starts both services

**Auto Scaling Group** (`phnyx-asg`):
- min=2, desired=2, max=4
- Attached to both ALB target groups (service1 and service2)
- ELB health checks with 120s grace period

**CPU Scale-out Policy**:
- Target tracking on `ASGAverageCPUUtilization`
- Scales out when CPU > 40%
- Auto scale-in when load drops

**IAM Role** (`phnyx-ec2-ecr-role`):
- `AmazonEC2ContainerRegistryReadOnly` managed policy
- Attached via instance profile — no credentials stored on instances

### Deploy with Terraform

```bash
cd terraform/
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_DEFAULT_REGION=us-east-1

terraform init
terraform plan
terraform apply -auto-approve
```

### Destroy with Terraform

```bash
terraform destroy -auto-approve
```

## Security Design

- ALB Security Group: allows 80/443 from 0.0.0.0/0
- EC2 Security Group: allows SSH (port 22) from admin IP only, 5000/5001 from anywhere
- ASG instances use IAM role for ECR access — no hardcoded credentials
- Manual instances use `aws configure` with scoped devops-engineer IAM user

## Cleanup

```bash
# 1. Terraform resources (ASG, Launch Template, IAM)
cd terraform && terraform destroy -auto-approve

# 2. Manual EC2 instances
aws ec2 terminate-instances --instance-ids i-079503dbd0478b951 i-072d2b6bc0395030f

# 3. ALB (wait for deletion before removing target groups)
aws elbv2 delete-load-balancer \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:219711034407:loadbalancer/app/phnyx-alb/93b203ec5b655e82
sleep 30
aws elbv2 delete-target-group \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:219711034407:targetgroup/phnyx-tg-service1/d61667bf19f0146a
aws elbv2 delete-target-group \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:219711034407:targetgroup/phnyx-tg-service2/58a84930bd600145

# 4. ECR repositories
aws ecr delete-repository --repository-name service1 --force
aws ecr delete-repository --repository-name service2 --force

# 5. Security groups
aws ec2 delete-security-group --group-id sg-0eb74c0e8f92e4d7b
aws ec2 delete-security-group --group-id sg-013546579e5bb1c03
```
