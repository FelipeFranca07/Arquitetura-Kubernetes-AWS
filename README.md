# Arquitetura AWS — Rede, Kubernetes e Dados de Ponta a Ponta

Do VPC ao EKS até o dado persistido: a cadeia completa de rede, firewall, orquestração de containers e armazenamento, em Terraform, camada por camada — com o equivalente manual pelo Console da AWS em cada seção.

![Diagrama de arquitetura](diagrams/architecture.svg)

## Terraform

A pasta [`terraform/`](terraform/) contém os 9 arquivos `.tf` na ordem de `apply`, cada um construindo em cima do anterior:

1. `01-main.tf`
2. `02-network.tf`
3. `03-firewall.tf`
4. `04-lb.tf`
5. `05-transit-gateway.tf`
6. `06-eks.tf`
7. `07-rds.tf`
8. `08-s3.tf`
9. `09-dynamodb.tf`

## 01. Rede — VPC

A fundação: um único CIDR que vai abrigar subnets públicas, privadas, o EKS e os bancos de dados.

> Console AWS → VPC → Your VPCs

**Passos pelo console:**
1. No canto superior direito do Console, confirme a região `South America (São Paulo) sa-east-1`.
2. Abra o serviço `VPC` e clique em `Create VPC`.
3. Selecione `VPC only`, dê o nome `prod-vpc`.
4. Em `IPv4 CIDR block`, digite `10.20.0.0/16`.
5. Deixe `Tenancy` como `Default` e clique em `Create VPC`.
6. Com a VPC criada, vá em `Actions → Edit VPC settings` e habilite `Enable DNS hostnames`.

## 02. Subnets — pública e privada, multi-AZ

Duas AZs para tolerância a falha. A subnet pública sai direto para a internet via Internet Gateway; a privada sai por um NAT Gateway, sem IP público.

> Console AWS → VPC → Subnets / Internet Gateways / NAT Gateways

**Passos pelo console:**
1. Em `VPC → Internet Gateways`, clique `Create internet gateway` (nome `prod-igw`), depois `Actions → Attach to VPC` e escolha `prod-vpc`.
2. Em `VPC → Subnets → Create subnet`, crie `public-a` (`10.20.0.0/24`, AZ `sa-east-1a`) e `public-b` (`10.20.1.0/24`, AZ `sa-east-1b`).
3. Repita para as privadas: `private-a` (`10.20.10.0/24`) e `private-b` (`10.20.11.0/24`), nas mesmas duas AZs.
4. Selecione as duas subnets públicas → `Actions → Edit subnet settings` → marque `Enable auto-assign public IPv4 address`.
5. Em `VPC → NAT Gateways → Create NAT gateway`, escolha a subnet `public-a`, aloque um novo `Elastic IP` e crie.
6. Em `Route Tables`, crie `private-rt`, associe as duas subnets privadas, e adicione uma rota `0.0.0.0/0 →` o NAT Gateway criado.

## 03. Firewall — Security Groups e NACLs

Duas camadas: o Security Group controla o que chega no ALB e nos nós do EKS; a NACL age no nível da subnet como uma segunda barreira.

> Console AWS → EC2 → Security Groups / VPC → Network ACLs

**Passos pelo console:**
1. Em `EC2 → Security Groups → Create security group`, nome `alb-sg`, VPC `prod-vpc`.
2. Em `Inbound rules`, adicione `HTTPS (443)` com origem `0.0.0.0/0`; em `Outbound rules` deixe o padrão (tudo liberado).
3. Crie um segundo grupo `eks-nodes-sg`; em `Inbound rules`, adicione uma regra `Custom TCP`, portas `1025-65535`, origem = o próprio `alb-sg` (selecione o security group, não um CIDR).
4. Em `VPC → Network ACLs → Create network ACL`, nome `private-nacl`, associe às duas subnets privadas.
5. Edite as regras de entrada e saída da NACL para permitir todo tráfego (`All traffic`) vindo de `10.20.0.0/16`.

## 04. Load Balancer — Application Load Balancer

Recebe o tráfego pelas subnets públicas e encaminha para os pods expostos via NodePort/Target Group nos nós do EKS.

> Console AWS → EC2 → Load Balancers

**Passos pelo console:**
1. Em `EC2 → Load Balancers → Create load balancer`, escolha `Application Load Balancer`.
2. Nome `prod-alb`, esquema `Internet-facing`, VPC `prod-vpc`, mapeie as subnets `public-a` e `public-b`.
3. Em `Security groups`, selecione `alb-sg`.
4. Crie um `Target group` tipo `IP`, porta `80`, health check no caminho `/health`.
5. No listener, adicione `HTTPS : 443`, anexe o certificado do `ACM` e aponte o `default action` para o target group criado.
6. Finalize em `Create load balancer`.

## 05. Transit Gateway — a rota entre VPCs

Único ponto de saída controlada da VPC: liga esse ambiente a um hub compartilhado com outras VPCs e com o on-premises, sem expor a rede inteira.

> Console AWS → VPC → Transit Gateways

**Passos pelo console:**
1. Em `VPC → Transit Gateways → Create transit gateway`, nome `prod-tgw`, mantenha `Default route table association` e `propagation` habilitados.
2. Em `Transit Gateway Attachments → Create attachment`, tipo `VPC`, selecione `prod-vpc` e as duas subnets privadas.
3. Volte em `Route Tables → private-rt → Routes → Edit routes` e adicione `10.0.0.0/8 →` o Transit Gateway criado.

## 06. Kubernetes gerenciado — EKS

O cluster e o node group vivem na subnet privada, atrás do Security Group já criado — nenhum nó com IP público.

> Console AWS → EKS → Clusters

**Passos pelo console:**
1. Em `EKS → Clusters → Create cluster`, nome `prod-eks`, selecione a IAM role de cluster (crie uma se não existir, com a policy gerenciada `AmazonEKSClusterPolicy`).
2. Em `Networking`, escolha `prod-vpc` e as duas subnets privadas; em `Cluster endpoint access`, marque `Private` e desmarque `Public`.
3. Em `Security groups`, selecione `eks-nodes-sg`.
4. Após o cluster ficar `Active`, vá em `Compute → Add node group`.
5. Nome `app-nodes`, tipo de instância `m6i.large`, escala `min 2 / desired 3 / max 6`, subnets = as duas privadas.

## 07. Banco relacional — RDS

PostgreSQL multi-AZ, alcançável apenas pelos nós do EKS através do subnet group privado.

> Console AWS → RDS → Databases

**Passos pelo console:**
1. Em `RDS → Subnet groups → Create DB subnet group`, nome `prod-db-subnets`, VPC `prod-vpc`, adicione as duas subnets privadas.
2. Crie um novo security group `rds-sg`: `Inbound rules` com `PostgreSQL (5432)`, origem = `eks-nodes-sg`.
3. Em `RDS → Databases → Create database`, escolha `Standard create`, engine `PostgreSQL 16`.
4. Em `Templates`, escolha `Production`; identificador `prod-postgres`, classe `db.m6g.large`, armazenamento `100 GiB`.
5. Marque `Multi-AZ deployment`; em `Connectivity`, selecione a VPC, o subnet group e o security group criados; em `Public access`, escolha `No`.
6. Em `Credentials management`, deixe o `Amazon RDS` gerenciar a senha via Secrets Manager.

## 08. Object Storage — S3

Assets estáticos e backups, versionado e criptografado por padrão.

> Console AWS → S3 → Buckets

**Passos pelo console:**
1. Em `S3 → Create bucket`, nome `prod-app-assets`, região `sa-east-1`.
2. Mantenha `Block all public access` marcado.
3. Em `Bucket Versioning`, selecione `Enable`.
4. Em `Default encryption`, escolha `Server-side encryption with Amazon S3 managed keys (SSE-S3)`.
5. Clique em `Create bucket`.

## 09. NoSQL — DynamoDB

Sessões e estado de baixa latência, fora do banco relacional, com escala sob demanda.

> Console AWS → DynamoDB → Tables

**Passos pelo console:**
1. Em `DynamoDB → Tables → Create table`, nome `app-sessions`.
2. Em `Partition key`, digite `session_id`, tipo `String`.
3. Em `Table settings`, escolha `Customize settings` e, em `Capacity mode`, selecione `On-demand`.
4. Após criar a tabela, vá em `Additional settings → Time to Live (TTL) → Enable` e informe o atributo `expires_at`.

## Aviso

**Ordem de criação:** VPC → subnets/NAT → security groups/NACL → load balancer → Transit Gateway → EKS → RDS → S3 → DynamoDB. Cada etapa depende de recursos criados na anterior (ex: o Target Group do ALB só existe depois da VPC; o node group do EKS só depois do cluster).

Os menus e assistentes do Console da AWS mudam de tempos em tempos — o nome exato de um botão pode ter se movido desde a escrita deste guia, mas a sequência e a lógica de dependência entre os recursos continuam válidas.
