#!/bin/bash

# 에러 발생 시 즉시 중단
set -e

# 동적 인벤토리 경로 정의
INV="inventory/hosts.aws_ec2.yml"

echo "🚀 K3s 클러스터 통합 배포를 시작합니다 (동적 인벤토리 기반)..."

# 1. Ansible 설치 여부 확인
if ! command -v ansible &> /dev/null; then
    echo "❌ Ansible이 설치되어 있지 않습니다."
    echo "    sudo apt update && sudo apt install ansible -y"
    exit 1
fi

# 2. 모든 노드 연결 테스트
echo "🔍 AWS EC2 인스턴스 연결 점검 중..."
ansible all -i $INV -m ping

# ❌ [삭제됨] CURRENT_IP 추출 로직
# 동적 인벤토리가 자동으로 IP를 파악합니다!

# 3. 전체 플레이북 실행
echo "📦 K3s 전체 설치 프로세스 가동 (site.yml)..."
ansible-playbook -i $INV site.yml

echo ""
echo "✅ K3s 클러스터 배포가 성공적으로 완료되었습니다!"
echo ""

# 4. 클러스터 접근 방법 안내
SERVER_IP=$(ansible-inventory -i $INV --list | jq -r '.servers.hosts[0]' 2>/dev/null || echo "<Server_IP>")

echo "🔧 클러스터 제어 방법:"
echo "    ssh ubuntu@$SERVER_IP"
echo "    kubectl get nodes"
echo ""

# 5. 로컬에서 원격 제어 안내
echo "📋 로컬 PC에서 kubectl을 사용하고 싶다면:"
echo "    mkdir -p ~/.kube"
echo "    scp ubuntu@$SERVER_IP:~/.kube/config ~/.kube/config"

echo ""
echo "🔍 클러스터 상태 최종 확인 중..."
ansible servers -i $INV -m shell -a "kubectl get nodes -o wide"

echo ""
echo "✅ 클러스터 준비 완료!"