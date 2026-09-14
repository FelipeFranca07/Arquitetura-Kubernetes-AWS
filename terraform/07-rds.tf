resource "aws_db_subnet_group" "app" {
  name       = "prod-db-subnets"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "rds" {
  name   = "rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }
}

resource "aws_db_instance" "app" {
  identifier             = "prod-postgres"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.m6g.large"
  allocated_storage      = 100
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  username               = "app_admin"
  manage_master_user_password = true
}
