variable "region" { default = "ap-northeast-2" }
variable "project_name" { default = "k3s-project" }
variable "agent_count" { default = 2 }

# 프리티어 유지를 위해 micro로 설정 (Swap으로 부족한 RAM 보완)
variable "instance_type" { default = "t4g.small" }

variable "key_name" { default = "my-terraform-key" } # 실제 보유한 키페어 이름

# K3s 노드 간 인증을 위한 비밀 토큰
variable "k3s_token" { 
	description = "K3s cluster join token"
	default = "k3s-token-2026-secret" 
}
