#!/bin/bash

# 에러 발생 시 즉시 중단
set -e

# 동적 인벤토리 경로 정의
INV="inventory/hosts.aws_ec2.yml"

echo "🚀 K3s 클러스터 통합 배포를 시작합니다 (동적 인벤토리 기반)..."

# 1. Ansible 및 jq 설치 여부 확인 (jq는 API 파싱에 필수!)
if ! command -v ansible &> /dev/null || ! command -v jq &> /dev/null; then
    echo "❌ Ansible 또는 jq가 설치되어 있지 않습니다. 설치를 먼저 진행해 주세요."
    exit 1
fi

# ---------------------------------------------------------
# [추가된 핵심 로직] 2. AWS API를 통해 서버 IP 추출 및 Proxy 설정
# ---------------------------------------------------------
echo "🔍 AWS API를 통해 서버(Bastion) IP를 조회 중..."

# 인벤토리에서 'server' 그룹의 첫 번째 호스트 이름을 가져옵니다.
HOST_NAME=$(ANSIBLE_DEBUG=0 ANSIBLE_VERBOSITY=0 ansible-inventory -i $INV --list | jq -r '.server.hosts[0]')

# API로부터 'server' 그룹에 속한 첫 번째 호스트의 공인 IP를 직접 가져옵니다.
SERVER_PUBLIC_IP=$(ANSIBLE_DEBUG=0 ANSIBLE_VERBOSITY=0 ansible-inventory -i $INV --list | jq -r '._meta.hostvars[.server.hosts[0]].public_ip_address')
if [ "$SERVER_PUBLIC_IP" == "null" ] || [ -z "$SERVER_PUBLIC_IP" ]; then
    echo "❌ API에서 서버 IP를 찾지 못했습니다. EC2가 'running' 상태인지 확인하세요."
    exit 1
fi

echo "📍 확인된 징검다리 서버 IP: $SERVER_PUBLIC_IP"

# [가장 중요] 사설망 에이전트 접속을 위한 징검다리(Proxy) 환경변수 설정
export ANSIBLE_SSH_COMMON_ARGS="-o ProxyCommand=\"ssh -W %h:%p -q ubuntu@$SERVER_PUBLIC_IP -o StrictHostKeyChecking=no\""
# ---------------------------------------------------------

# 3. 모든 노드 연결 테스트
echo "🔍 AWS EC2 인스턴스 연결 점검 중 (Proxy 적용)..."
ansible all -i $INV -m ping

# 4. 전체 플레이북 실행
echo "📦 K3s 전체 설치 프로세스 가동 (site.yml)..."
ansible-playbook -i $INV site.yml

echo ""
echo "✅ K3s 클러스터 배포가 성공적으로 완료되었습니다!"

# 5. 클러스터 접근 방법 안내 (기존 코드 유지)
echo "🔧 클러스터 제어 방법:"
echo "    ssh ubuntu@$SERVER_PUBLIC_IP"
echo "    kubectl get nodes"

# 6. 로컬 제어 안내 (기존 코드 유지)
echo ""
echo "📋 로컬 PC에서 kubectl을 사용하고 싶다면:"
echo "    mkdir -p ~/.kube"
echo "    scp ubuntu@$SERVER_PUBLIC_IP:~/.kube/config ~/.kube/config"

#echo "📊 [3] 모니터링 대시보드 접속 (Grafana)"
#echo "    URL: http://$SERVER_PUBLIC_IP:32000"
#echo "    ID:  admin"
#echo "    PW:  admin"  # all.yml에서 수정한 경우 해당 값을 입력하세요.
#echo "----------------------------------------------------------------"

echo ""
echo "🔍 클러스터 상태 최종 확인 중..."
# 인벤토리에 정의된 'server' 그룹(그룹명 확인 필요)을 타겟팅합니다.
ansible server -i $INV -m shell -a "kubectl get nodes -o wide"

echo ""
echo "✅ 클러스터 준비 완료!"
