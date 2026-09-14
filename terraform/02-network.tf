resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "prod-igw" }
}

resource "aws_subnet" "public" {
  for_each                = { a = "10.20.0.0/24", b = "10.20.1.0/24" }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = "sa-east-1${each.key}"
  map_public_ip_on_launch = true
  tags = { Name = "public-${each.key}", tier = "public" }
}

resource "aws_subnet" "private" {
  for_each          = { a = "10.20.10.0/24", b = "10.20.11.0/24" }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "sa-east-1${each.key}"
  tags = { Name = "private-${each.key}", tier = "private" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags          = { Name = "prod-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
