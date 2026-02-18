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
  
  ingress { 
	  from_port   = 30080
	  to_port     = 30080
	  protocol    = "tcp"
	  cidr_blocks = ["0.0.0.0/0"] 
	  description = "Allow Nginx NodePort on Server Node"
	}

  ingress { # 프라이빗 서브넷(Agent)에서 오는 모든 트래픽 허용 (NAT 역할)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
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
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  
  # --- 추가된 부분: Nginx NodePort 접속 허용 ---
  ingress { 
    from_port   = 30080 #쿠버네티스(K3s)에서 외부로 서비스를 노출할 때 사용하는 NodePort의 기본 범위(30000~32767)에 속하는 포트
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

# [핵심] 노드 간 상호 통신 규칙 (SG Peering)
#보안 그룹끼리 서로 허용: 반드시 aws_security_group_rule로 분리해서 작성해야 함
# Server는 Agent 보안 그룹을 가진 노드의 모든 포트 접속을 허용합니다.
resource "aws_security_group_rule" "allow_agent_to_server" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.server_sg.id
  source_security_group_id = aws_security_group.agent_sg.id
}

# Agent는 Server 보안 그룹을 가진 노드의 모든 포트 접속을 허용합니다.
resource "aws_security_group_rule" "allow_server_to_agent" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.agent_sg.id
  source_security_group_id = aws_security_group.server_sg.id
}
