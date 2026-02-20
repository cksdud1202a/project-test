#!/bin/bash

set -e

INV="inventory/hosts.aws_ec2.yml"

echo "🚀 K3s 클러스터 통합 배포 시작..."

# 1. Ansible 존재 확인
if ! command -v ansible &> /dev/null; then
    echo "❌ Ansible이 설치되어 있지 않습니다."
    exit 1
fi

# 2. 동적 인벤토리 정상 로딩 확인
echo "🔍 인벤토리 확인 중..."
ansible-inventory -i $INV --graph

# 3. 연결 테스트
echo "🔍 EC2 인스턴스 연결 점검..."
ansible all -i $INV -m ping

# 4. K3s 설치 실행
echo "📦 site.yml 실행 중..."
ansible-playbook -i $INV site.yml

echo ""
echo "✅ K3s 클러스터 배포 완료"
echo ""

# 5. 서버 IP 추출 (jq 없이)
SERVER_IP=$(ansible server -i $INV -m debug -a "var=ansible_host" \
  | grep ansible_host | head -1 | awk '{print $3}')

echo "🔧 접속 방법:"
echo "    ssh ubuntu@$SERVER_IP"
echo "    kubectl get nodes"

echo ""
echo "🔍 클러스터 상태 확인..."
ansible server -i $INV -m shell -a "kubectl get nodes -o wide"

echo ""
echo "🎉 클러스터 준비 완료!"