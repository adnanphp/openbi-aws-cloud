# VPC module for OpenBI on AWS.
#
# Creates a production-shaped VPC:
#   - 1 VPC with DNS hostnames and resolution enabled (required for EKS)
#   - Public subnets in 2+ AZs (ALB, NAT Gateway)
#   - Private subnets in 2+ AZs (EKS nodes, RDS, all workloads)
#   - Internet Gateway for public subnets
#   - NAT Gateway(s) for private subnet egress
#   - Route tables with correct associations
#   - A baseline security group
#   - VPC Flow Logs to CloudWatch
#
# Design notes:
#   - Two AZs minimum is an EKS requirement, not a preference.
#   - EKS private endpoint requires DNS hostnames + resolution to be enabled.
#   - Single NAT Gateway by default (cost); flip to HA with var.single_nat_gateway=false.
#   - No application security groups here; those come with each service module.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# ----------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# ----------------------------------------------------------------------
# Internet Gateway
# ----------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# ----------------------------------------------------------------------
# Public subnets (one per AZ)
# ----------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                     = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  })
}

# ----------------------------------------------------------------------
# Private subnets (one per AZ)
# ----------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                              = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
    Tier                              = "private"
  })
}

# ----------------------------------------------------------------------
# NAT Gateway(s)
# ----------------------------------------------------------------------
# One NAT Gateway per AZ is HA but ~3x the cost. Single NAT is the
# default for dev environments. Production should flip single_nat_gateway
# to false.

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ----------------------------------------------------------------------
# Route tables
# ----------------------------------------------------------------------

# Public route table: everything to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables: one per NAT Gateway (or shared if single NAT)
# Using a single route table per AZ keeps the design explicit and
# makes it easy to switch to HA later.
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-rt-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ----------------------------------------------------------------------
# Baseline security group
# ----------------------------------------------------------------------
# This is the security group attached to resources that need to talk to
# each other (EKS nodes, RDS, etc.). Per-service security groups come
# with their own modules and reference this one as their source.

resource "aws_security_group" "baseline" {
  name_prefix = "${var.name_prefix}-baseline-"
  description = "Baseline security group for OpenBI (intra-VPC traffic)"
  vpc_id      = aws_vpc.this.id

  # All traffic within the security group is allowed. Individual services
  # add more restrictive rules on top of this.
  ingress {
    description = "Self-referencing ingress for intra-VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-baseline-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------------------------------
# VPC Flow Logs
# ----------------------------------------------------------------------
# Flow logs are the first thing you want when debugging "why can't this
# pod reach that service" — they capture source/dest/port/protocol per
# accepted and rejected flow. Enabled by default; production cost can
# be significant at high volume.

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name_prefix}-flow-logs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name_prefix}-flow-logs-"
  role        = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-flow-log"
  })
}
