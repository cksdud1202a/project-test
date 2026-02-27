# Server 보안 그룹
resource "aws_security_group" "server_sg" {
  name   = "server-sg"
  vpc_id = aws_vpc.main.id

  ingress { # SSH 접속
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { # K3s API 서버 (외부 kubectl 제어용)
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # [변경] Server는 NLB Target에서 제외됐으므로 30080 외부 허용 제거
  # Server NodePort는 내부 통신용으로만 사용
  ingress { 
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow Nginx NodePort internal only"
  }

  ingress { 
    from_port   = 32000
    to_port     = 32000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow Grafana Dashboard Access"
  }

  ingress { # 프라이빗 서브넷(Agent)에서 오는 모든 트래픽 허용 (NAT 역할)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Agent 보안 그룹
resource "aws_security_group" "agent_sg" {
  name   = "agent-sg"
  vpc_id = aws_vpc.main.id

  ingress { # Server로부터의 내부 SSH 및 통신 허용
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.public.cidr_block]
  }

  # [변경] 0.0.0.0/0 → VPC CIDR로 변경
  # NLB는 VPC 내부 통신으로 Agent에 접근하므로 VPC CIDR만 허용하면 됨
  ingress { 
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow NLB to Agent NodePort"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 노드 간 상호 통신 규칙 (SG Peering)
resource "aws_security_group_rule" "allow_agent_to_server" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.server_sg.id
  source_security_group_id = aws_security_group.agent_sg.id
}

resource "aws_security_group_rule" "allow_server_to_agent" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.agent_sg.id
  source_security_group_id = aws_security_group.server_sg.id
}