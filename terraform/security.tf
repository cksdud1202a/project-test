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

  ingress { # 프라이빗 서브넷(Agent)에서 오는 모든 트래픽 허용 (NAT 역할)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private.cidr_block]
  }

  egress { # 모든 외부 출력 허용
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
  
  # --- 추가된 부분: Nginx NodePort 접속 허용 ---
  ingress { 
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Allow Nginx NodePort Access"
  }

  egress { # 모든 외부 출력 허용 (Server를 통해 나감)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

