# Terraform: Ensure subnets do not auto-assign public IPs

This example Terraform module creates a VPC and subnets where `map_public_ip_on_launch` is set to `false`.

Why: For the requirement "EC2 subnets should not automatically assign public IP addresses" ensure that new instances launched into these subnets do not receive a public IP by default.

Files:
- `main.tf` - resources (VPC, subnets) with `map_public_ip_on_launch = false`
- `variables.tf` - parameterize region, CIDRs and AZs
- `terraform.tfvars.example` - example variable values
- `versions.tf` - Terraform version

Usage:
1. Copy `terraform.tfvars.example` -> `terraform.tfvars` and edit values as needed.
2. Run:

```bash
terraform init
terraform plan
terraform apply
```

Note: This module explicitly sets `map_public_ip_on_launch = false` for both public and private subnet resources. If you require public subnets that auto-assign public IPs, set that flag to `true` for the desired subnet resources.


# Import the VPC
terraform import aws_vpc.vpc vpc-0acec743b1bd7bf64

# Import subnets
terraform import aws_subnet.subnet[0] subnet-07d3f5dca35792e97
terraform import aws_subnet.subnet[1] subnet-0c067b66acfca9c0b
terraform import aws_subnet.subnet[2] subnet-04136e92be7f3c6d9
terraform import aws_subnet.subnet[3] subnet-007dc81a7a353fd0a
