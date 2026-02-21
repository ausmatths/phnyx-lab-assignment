#!/bin/bash
# verify_endpoints.sh - PhnyX Lab Take-home Assignment #1
# Tests all endpoints and exits with non-zero status on failure

ALB_DNS="phnyx-alb-72999925.us-east-1.elb.amazonaws.com"
PASS=0
FAIL=0

check() {
    local url=$1
    local expected=$2
    local response
    local http_code

    response=$(curl -s -o /tmp/resp.txt -w "%{http_code}" "$url")
    body=$(cat /tmp/resp.txt)

    if [ "$response" == "200" ]; then
        if echo "$body" | grep -q "$expected"; then
            echo "✅ PASS: $url"
            echo "   Response: $body"
            PASS=$((PASS+1))
        else
            echo "❌ FAIL: $url - unexpected body"
            echo "   Response: $body"
            FAIL=$((FAIL+1))
        fi
    else
        echo "❌ FAIL: $url - HTTP $response"
        FAIL=$((FAIL+1))
    fi
}

echo "============================================"
echo " PhnyX Lab - Endpoint Verification Script"
echo " ALB: $ALB_DNS"
echo "============================================"
echo ""

echo "--- Testing ALB Path-based Routing ---"
check "http://$ALB_DNS/service1" "Hello from Service 1"
check "http://$ALB_DNS/service2" "Hello from Service 2"

echo ""
echo "--- Testing Health Endpoints (Direct) ---"
check "http://98.84.49.245:5000/health" "healthy"
check "http://98.84.49.245:5001/health" "healthy"
check "http://18.206.87.98:5000/health" "healthy"
check "http://18.206.87.98:5001/health" "healthy"

echo ""
echo "--- Testing ECR Repositories ---"
echo "service1 URI: $(aws ecr describe-repositories --repository-names service1 --query 'repositories[0].repositoryUri' --output text --region us-east-1)"
echo "service2 URI: $(aws ecr describe-repositories --repository-names service2 --query 'repositories[0].repositoryUri' --output text --region us-east-1)"

echo ""
echo "============================================"
echo " Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
