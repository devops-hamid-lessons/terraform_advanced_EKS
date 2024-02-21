resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.networking.cidr_block

  tags = {
    Name = "${var.env_prefix}_cluster_vpc"
  }
}

# PUBLIC SUBNETS
resource "aws_subnet" "public_subnets" {
  count                   = var.networking.public_subnets == null || var.networking.public_subnets == "" ? 0 : length(var.networking.public_subnets)
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.networking.public_subnets[count.index]
  availability_zone       = var.networking.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env_prefix}_public_subnet_${var.networking.azs[count.index]}"
  }
}

# PRIVATE SUBNETS
resource "aws_subnet" "private_subnets" {
  count                   = var.networking.private_subnets == null || var.networking.private_subnets == "" ? 0 : length(var.networking.private_subnets)
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.networking.private_subnets[count.index]
  availability_zone       = var.networking.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.env_prefix}_private_subnet_${var.networking.azs[count.index]}"
  }
}

# INTERNET GATEWAY
resource "aws_internet_gateway" "i_gateway" {
  vpc_id = aws_vpc.cluster_vpc.id

  tags = {
    Name = "${var.env_prefix}_i_gateway"
  }
}

# EIPs, one eip is a public random ip
resource "aws_eip" "elastic_ip" {
  count      = var.networking.private_subnets == null || var.networking.nat_gateways == false ? 0 : length(var.networking.private_subnets)
  vpc        = true
  depends_on = [aws_internet_gateway.i_gateway]

  tags = {
    Name = "${var.env_prefix}_eip_${var.networking.azs[count.index]}"
  }
}

# NAT GATEWAYS
resource "aws_nat_gateway" "nats" {
  count             = var.networking.private_subnets == null || var.networking.nat_gateways == false ? 0 : length(var.networking.private_subnets)
  subnet_id         = aws_subnet.public_subnets[count.index].id
  connectivity_type = "public"
  allocation_id     = aws_eip.elastic_ip[count.index].id
  depends_on        = [aws_internet_gateway.i_gateway]
  tags = {
    Name = "${var.env_prefix}_nat_gateway_${var.networking.azs[count.index]}"
  }
}

# PUBLIC ROUTE TABLE
resource "aws_route_table" "public_table" {
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "${var.env_prefix}_public_router"
  }
}

resource "aws_route" "public_routes" {
  route_table_id         = aws_route_table.public_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.i_gateway.id
}

resource "aws_route_table_association" "assoc_public_routes" {
  count          = length(var.networking.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_table.id
}

# PRIVATE ROUTE TABLES
resource "aws_route_table" "private_tables" {
  count  = length(var.networking.azs)
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "${var.env_prefix}_private_router_${var.networking.azs[count.index]}"
  }

}

resource "aws_route" "private_routes" {
  count                  = length(var.networking.private_subnets)
  route_table_id         = aws_route_table.private_tables[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nats[count.index].id
}

resource "aws_route_table_association" "assoc_private_routes" {
  count          = length(var.networking.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_tables[count.index].id
}

# SECURITY GROUPS
resource "aws_security_group" "sec_groups" {
  for_each    = { for sec in var.security_groups : sec.name => sec }
  name        = each.value.name
  description = each.value.description
  vpc_id      = aws_vpc.cluster_vpc.id

  dynamic "ingress" {
    for_each = try(each.value.ingress, [])
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = try(each.value.egress, [])
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
    }
  }
}
