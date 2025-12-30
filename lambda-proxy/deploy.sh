#!/bin/bash
# Bedrock Proxy Deployment Script
# Purpose: Deploy Lambda + API Gateway for secure Bedrock access
# Organization: 3 Big Things

set -e  # Exit on error

# Configuration
REGION="ap-southeast-2"
FUNCTION_NAME="redactor-bedrock-proxy"
ROLE_NAME="redactor-bedrock-proxy-role"
API_NAME="redactor-bedrock-api"
STAGE_NAME="prod"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================="
echo "Deploying Bedrock Proxy"
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo "=========================================="

# Step 1: Create IAM Role for Lambda
echo ""
echo "Step 1: Creating IAM Role..."

# Trust policy for Lambda
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Check if role exists
if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "Role $ROLE_NAME already exists"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for Redactor Bedrock Proxy Lambda"
    echo "Created role $ROLE_NAME"
fi

# Attach policies
echo "Attaching policies..."

# Basic Lambda execution (CloudWatch logs)
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

# Bedrock access (use existing policy)
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/BedrockAccessPolicy 2>/dev/null || true

# Wait for role to propagate
echo "Waiting for role to propagate..."
sleep 10

# Step 2: Package and Deploy Lambda Function
echo ""
echo "Step 2: Deploying Lambda Function..."

cd "$(dirname "$0")"
zip -j /tmp/lambda-function.zip lambda_function.py

# Check if function exists
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION 2>/dev/null; then
    echo "Updating existing function..."
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb:///tmp/lambda-function.zip \
        --region $REGION
else
    echo "Creating new function..."
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.12 \
        --role arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda-function.zip \
        --timeout 60 \
        --memory-size 256 \
        --region $REGION \
        --description "Secure proxy for Bedrock API calls"
fi

# Wait for function to be active
echo "Waiting for function to be active..."
aws lambda wait function-active --function-name $FUNCTION_NAME --region $REGION

# Step 3: Create API Gateway
echo ""
echo "Step 3: Creating API Gateway..."

# Check if API exists
EXISTING_API=$(aws apigateway get-rest-apis --region $REGION --query "items[?name=='$API_NAME'].id" --output text)

if [ -n "$EXISTING_API" ]; then
    API_ID=$EXISTING_API
    echo "Using existing API: $API_ID"
else
    API_ID=$(aws apigateway create-rest-api \
        --name $API_NAME \
        --description "Redactor Bedrock Proxy API" \
        --endpoint-configuration types=REGIONAL \
        --region $REGION \
        --query 'id' --output text)
    echo "Created API: $API_ID"
fi

# Get root resource ID
ROOT_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query "items[?path=='/'].id" --output text)

# Create /invoke resource if it doesn't exist
INVOKE_RESOURCE=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query "items[?path=='/invoke'].id" --output text)

if [ -z "$INVOKE_RESOURCE" ]; then
    INVOKE_RESOURCE=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_ID \
        --path-part "invoke" \
        --region $REGION \
        --query 'id' --output text)
    echo "Created /invoke resource"
fi

# Create POST method with API key required
echo "Configuring POST method..."
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $INVOKE_RESOURCE \
    --http-method POST \
    --authorization-type NONE \
    --api-key-required \
    --region $REGION 2>/dev/null || true

# Set up Lambda integration
echo "Setting up Lambda integration..."
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $INVOKE_RESOURCE \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region $REGION

# Add Lambda permission for API Gateway
echo "Adding Lambda permission..."
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" \
    --region $REGION 2>/dev/null || true

# Deploy API
echo "Deploying API to $STAGE_NAME stage..."
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $STAGE_NAME \
    --region $REGION

# Step 4: Create API Key and Usage Plan
echo ""
echo "Step 4: Creating API Key and Usage Plan..."

# Create usage plan if it doesn't exist
USAGE_PLAN_NAME="redactor-usage-plan"
USAGE_PLAN_ID=$(aws apigateway get-usage-plans --region $REGION --query "items[?name=='$USAGE_PLAN_NAME'].id" --output text)

if [ -z "$USAGE_PLAN_ID" ]; then
    USAGE_PLAN_ID=$(aws apigateway create-usage-plan \
        --name $USAGE_PLAN_NAME \
        --description "Usage plan for Redactor app" \
        --throttle burstLimit=100,rateLimit=50 \
        --quota limit=10000,period=DAY \
        --api-stages apiId=$API_ID,stage=$STAGE_NAME \
        --region $REGION \
        --query 'id' --output text)
    echo "Created usage plan: $USAGE_PLAN_ID"
else
    echo "Using existing usage plan: $USAGE_PLAN_ID"
fi

# Create API key
API_KEY_NAME="redactor-api-key"
EXISTING_KEY=$(aws apigateway get-api-keys --region $REGION --query "items[?name=='$API_KEY_NAME'].id" --output text)

if [ -n "$EXISTING_KEY" ]; then
    API_KEY_ID=$EXISTING_KEY
    echo "Using existing API key"
else
    API_KEY_ID=$(aws apigateway create-api-key \
        --name $API_KEY_NAME \
        --description "API key for Redactor app" \
        --enabled \
        --region $REGION \
        --query 'id' --output text)
    echo "Created API key: $API_KEY_ID"

    # Associate key with usage plan
    aws apigateway create-usage-plan-key \
        --usage-plan-id $USAGE_PLAN_ID \
        --key-id $API_KEY_ID \
        --key-type API_KEY \
        --region $REGION
fi

# Get the actual API key value
API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --region $REGION --query 'value' --output text)

# Step 5: Output results
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "API Endpoint:"
echo "  https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/invoke"
echo ""
echo "API Key:"
echo "  $API_KEY_VALUE"
echo ""
echo "Usage:"
echo "  curl -X POST \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'x-api-key: ${API_KEY_VALUE}' \\"
echo "    -d '{\"model\":\"apac.anthropic.claude-3-5-haiku-20241022-v1:0\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_tokens\":100}' \\"
echo "    https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/invoke"
echo ""
echo "Save these values - you'll need them for the app configuration!"
echo "=========================================="

# Save to file for reference
cat > /tmp/redactor-proxy-config.txt << EOF
API_ENDPOINT=https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/invoke
API_KEY=$API_KEY_VALUE
EOF
echo "Configuration saved to /tmp/redactor-proxy-config.txt"
