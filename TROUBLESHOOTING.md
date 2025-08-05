# 🔧 Troubleshooting Guide - AWS 3-Tier Architecture

This guide helps you diagnose and resolve common issues when deploying the 3-tier architecture.

## 📋 Common Issues and Solutions

### 1. CloudFormation Stack Deployment Failures

#### Issue: Stack creation fails with permission errors
```
User: arn:aws:iam::123456789012:user/username is not authorized to perform: cloudformation:CreateStack
```

**Solution:**
- Ensure your IAM user/role has the following permissions:
  - `CloudFormationFullAccess`
  - `EC2FullAccess`
  - `RDSFullAccess`
  - `ELBv2FullAccess`
  - `VPCFullAccess`
  - `IAMFullAccess` (for creating service roles)

#### Issue: Key pair not found error
```
The key pair 'sshbastion' does not exist
```

**Solution:**
1. Create the key pair in your AWS region:
   ```bash
   aws ec2 create-key-pair --key-name sshbastion --region us-east-1
   ```
2. Or set a different key pair name:
   ```bash
   export KEY_PAIR_NAME=your-existing-key-pair
   ```

### 2. Networking Issues

#### Issue: EC2 instances cannot connect to the internet
**Symptoms:**
- Instances in private subnets cannot download packages
- Application deployment fails during user data execution

**Solution:**
1. Verify NAT Gateway is properly configured:
   ```bash
   aws ec2 describe-nat-gateways --region us-east-1
   ```
2. Check route tables for private subnets:
   ```bash
   aws ec2 describe-route-tables --filters "Name=tag:Name,Values=*Private*"
   ```
3. Ensure Elastic IP is attached to NAT Gateway

#### Issue: Load balancer health checks failing
**Symptoms:**
- ALB shows all targets as unhealthy
- Application is not accessible via ALB DNS name

**Solution:**
1. Check security group rules for web tier:
   - Ensure port 80 is open from ALB security group
2. Verify application is running on correct port:
   ```bash
   ssh -i your-key.pem ec2-user@instance-ip
   sudo systemctl status httpd
   curl localhost:80
   ```
3. Check ALB target group health:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <your-target-group-arn>
   ```

### 3. Database Connection Issues

#### Issue: Application cannot connect to RDS database
**Symptoms:**
- Database connection timeouts
- Application logs show connection errors

**Solution:**
1. Verify RDS security group allows connections from app tier:
   ```bash
   aws rds describe-db-instances --db-instance-identifier <your-db-identifier>
   ```
2. Check database subnet group configuration
3. Ensure database is in available state:
   ```bash
   aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'
   ```
4. Test connectivity from app tier instance:
   ```bash
   telnet <rds-endpoint> 3306
   ```

### 4. Application Deployment Issues

#### Issue: User data script fails during instance launch
**Symptoms:**
- Instances launch but application is not installed
- SSH shows incomplete setup

**Solution:**
1. Check cloud-init logs:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   sudo cat /var/log/cloud-init.log
   ```
2. Verify internet connectivity for package downloads
3. Check if all required packages are available in the region's repositories

#### Issue: Application shows database connection errors
**Solution:**
1. Update application configuration with correct RDS endpoint
2. Verify database credentials and security groups
3. Check application logs:
   ```bash
   sudo tail -f /var/log/httpd/error_log
   ```

### 5. Performance Issues

#### Issue: High response times or timeouts
**Symptoms:**
- Load balancer returns 504 Gateway Timeout
- Slow application response

**Solution:**
1. **Scale out**: Increase number of instances in Auto Scaling Groups
2. **Scale up**: Use larger instance types (t3.medium instead of t3.micro)
3. **Database optimization**:
   - Consider RDS read replicas for read-heavy workloads
   - Upgrade to larger RDS instance class
   - Enable Multi-AZ for better performance
4. **Monitor CloudWatch metrics**:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/ApplicationELB \
     --metric-name ResponseTime \
     --start-time 2023-01-01T00:00:00Z \
     --end-time 2023-01-01T23:59:59Z \
     --period 3600 \
     --statistics Average
   ```

### 6. Security Group Troubleshooting

#### Issue: Cannot SSH to instances
**Solution:**
1. Verify security group allows SSH (port 22) from your IP:
   ```bash
   curl ifconfig.me  # Get your public IP
   ```
2. Check NACLs (Network ACLs) are not blocking traffic
3. Ensure instances have public IPs (for bastion) or use Session Manager

#### Issue: Inter-tier communication problems
**Solution:**
1. Web tier → App tier: Ensure app tier security group allows HTTP from web tier SG
2. App tier → Database: Ensure RDS security group allows MySQL (3306) from app tier SG
3. Use CloudFormation outputs to verify security group IDs

## 🔍 Debugging Commands

### CloudFormation Stack Information
```bash
# Get stack status
aws cloudformation describe-stacks --stack-name 3tier-app-network

# Get stack events (shows deployment progress)
aws cloudformation describe-stack-events --stack-name 3tier-app-network

# Get stack resources
aws cloudformation describe-stack-resources --stack-name 3tier-app-network
```

### EC2 Instance Debugging
```bash
# List instances
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]'

# Get instance console output
aws ec2 get-console-output --instance-id i-1234567890abcdef0

# Check system logs via Session Manager
aws ssm start-session --target i-1234567890abcdef0
```

### Load Balancer Debugging
```bash
# Get ALB information
aws elbv2 describe-load-balancers

# Check target group health
aws elbv2 describe-target-health --target-group-arn <arn>

# Get ALB access logs (if enabled)
aws s3 ls s3://your-alb-logs-bucket/
```

### RDS Debugging
```bash
# Get RDS status
aws rds describe-db-instances

# Check recent events
aws rds describe-events --source-type db-instance --max-records 20
```

## 📊 Monitoring and Logging

### Enable CloudWatch Detailed Monitoring
```bash
# Enable detailed monitoring for EC2 instances
aws ec2 monitor-instances --instance-ids i-1234567890abcdef0
```

### Set up CloudWatch Alarms
```bash
# CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "High-CPU-Utilization" \
  --alarm-description "Alarm when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## 🆘 Emergency Procedures

### Rollback Deployment
```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name 3tier-app-app
aws cloudformation delete-stack --stack-name 3tier-app-web
aws cloudformation delete-stack --stack-name 3tier-app-alb
aws cloudformation delete-stack --stack-name 3tier-app-database
aws cloudformation delete-stack --stack-name 3tier-app-network
```

### Quick Health Check Script
```bash
#!/bin/bash
# Save as health-check.sh

echo "=== 3-Tier Architecture Health Check ==="

# Check ALB health
ALB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 describe-target-health --target-group-arn $ALB_ARN

# Check RDS status
aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'

# Check EC2 instances
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'
```

## 📞 Getting Help

If you're still experiencing issues:

1. **Check AWS Service Health**: [AWS Service Health Dashboard](https://status.aws.amazon.com/)
2. **AWS Support**: Create a support case if you have a support plan
3. **Community Forums**: [AWS Developer Forums](https://forums.aws.amazon.com/)
4. **Documentation**: [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)

## 🔄 Regular Maintenance

### Weekly Tasks
- Review CloudWatch metrics and alarms
- Check for AWS service updates
- Review security group rules
- Monitor costs in AWS Cost Explorer

### Monthly Tasks
- Update AMIs to latest versions
- Review and rotate access keys
- Audit IAM permissions
- Review backup and disaster recovery procedures