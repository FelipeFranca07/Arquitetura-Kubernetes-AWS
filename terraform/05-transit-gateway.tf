resource "aws_ec2_transit_gateway" "hub" {
  description                    = "hub-multicloud"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags = { Name = "prod-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = [for s in aws_subnet.private : s.id]
}

resource "aws_route" "to_tgw" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.hub.id
}
