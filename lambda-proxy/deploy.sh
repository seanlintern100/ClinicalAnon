#!/bin/bash
# Bedrock Proxy Deployment Script with API Key Rotation
# Purpose: Deploy Lambda + API Gateway + Secrets Manager for secure Bedrock access
# Organization: 3 Big Things

set -e  # Exit on error

# Configuration
REGION="ap-southeast-2"
FUNCTION_NAME="redactor-bedrock-proxy"
GET_KEY_FUNCTION="redactor-get-api-key"
ROTATE_KEY_FUNCTION="redactor-rotate-api-key"
ROLE_NAME="redactor-bedrock-proxy-role"
API_NAME="redactor-bedrock-api"
STAGE_NAME="prod"
SECRET_NAME="redactor/api-key"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================="
echo "Deploying Bedrock Proxy with Key Rotation"
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

# Create inline policy for Secrets Manager and API Gateway
echo "Adding Secrets Manager and API Gateway permissions..."
cat > /tmp/rotation-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:PutSecretValue",
                "secretsmanager:CreateSecret",
                "secretsmanager:UpdateSecret"
            ],
            "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:redactor/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "apigateway:GET",
                "apigateway:POST",
                "apigateway:DELETE"
            ],
            "Resource": [
                "arn:aws:apigateway:${REGION}::/apikeys",
                "arn:aws:apigateway:${REGION}::/apikeys/*",
                "arn:aws:apigateway:${REGION}::/usageplans",
                "arn:aws:apigateway:${REGION}::/usageplans/*"
            ]
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name RedactorRotationPolicy \
    --policy-document file:///tmp/rotation-policy.json

# Wait for role to propagate
echo "Waiting for role to propagate..."
sleep 10

# Step 2: Create Secrets Manager Secret
echo ""
echo "Step 2: Setting up Secrets Manager..."

# Check if secret exists
if aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $REGION 2>/dev/null; then
    echo "Secret $SECRET_NAME already exists"
else
    # Create secret with placeholder (will be updated by rotation)
    aws secretsmanager create-secret \
        --name $SECRET_NAME \
        --description "Redactor API Gateway key" \
        --secret-string '{"api_key": "pending-rotation", "key_id": "pending"}' \
        --region $REGION
    echo "Created secret $SECRET_NAME"
fi

# Step 3: Package and Deploy Lambda Functions
echo ""
echo "Step 3: Deploying Lambda Functions..."

cd "$(dirname "$0")"

# Deploy main Bedrock proxy function
zip -j /tmp/lambda-function.zip lambda_function.py
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION 2>/dev/null; then
    echo "Updating $FUNCTION_NAME..."
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb:///tmp/lambda-function.zip \
        --region $REGION > /dev/null
else
    echo "Creating $FUNCTION_NAME..."
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.12 \
        --role arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda-function.zip \
        --timeout 120 \
        --memory-size 256 \
        --region $REGION \
        --description "Secure proxy for Bedrock API calls" > /dev/null
fi

# Deploy get-api-key function
zip -j /tmp/get-api-key.zip get_api_key.py
if aws lambda get-function --function-name $GET_KEY_FUNCTION --region $REGION 2>/dev/null; then
    echo "Updating $GET_KEY_FUNCTION..."
    aws lambda update-function-code \
        --function-name $GET_KEY_FUNCTION \
        --zip-file fileb:///tmp/get-api-key.zip \
        --region $REGION > /dev/null
else
    echo "Creating $GET_KEY_FUNCTION..."
    aws lambda create-function \
        --function-name $GET_KEY_FUNCTION \
        --runtime python3.12 \
        --role arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} \
        --handler get_api_key.lambda_handler \
        --zip-file fileb:///tmp/get-api-key.zip \
        --timeout 10 \
        --memory-size 128 \
        --region $REGION \
        --description "Return current API key from Secrets Manager" > /dev/null
fi

# Deploy rotate-api-key function
zip -j /tmp/rotate-api-key.zip rotate_api_key.py
if aws lambda get-function --function-name $ROTATE_KEY_FUNCTION --region $REGION 2>/dev/null; then
    echo "Updating $ROTATE_KEY_FUNCTION..."
    aws lambda update-function-code \
        --function-name $ROTATE_KEY_FUNCTION \
        --zip-file fileb:///tmp/rotate-api-key.zip \
        --region $REGION > /dev/null
else
    echo "Creating $ROTATE_KEY_FUNCTION..."
    aws lambda create-function \
        --function-name $ROTATE_KEY_FUNCTION \
        --runtime python3.12 \
        --role arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} \
        --handler rotate_api_key.lambda_handler \
        --zip-file fileb:///tmp/rotate-api-key.zip \
        --timeout 30 \
        --memory-size 128 \
        --region $REGION \
        --description "Rotate API Gateway key weekly" > /dev/null
fi

# Wait for functions to be active
echo "Waiting for functions to be active..."
aws lambda wait function-active --function-name $FUNCTION_NAME --region $REGION
aws lambda wait function-active --function-name $GET_KEY_FUNCTION --region $REGION
aws lambda wait function-active --function-name $ROTATE_KEY_FUNCTION --region $REGION

# Step 4: Create API Gateway
echo ""
echo "Step 4: Creating API Gateway..."

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

# Create /invoke resource (Bedrock proxy)
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

# Create /get-api-key resource
GET_KEY_RESOURCE=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query "items[?path=='/get-api-key'].id" --output text)
if [ -z "$GET_KEY_RESOURCE" ]; then
    GET_KEY_RESOURCE=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_ID \
        --path-part "get-api-key" \
        --region $REGION \
        --query 'id' --output text)
    echo "Created /get-api-key resource"
fi

# Configure /invoke POST method (requires API key)
echo "Configuring /invoke endpoint..."
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $INVOKE_RESOURCE \
    --http-method POST \
    --authorization-type NONE \
    --api-key-required \
    --region $REGION 2>/dev/null || true

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $INVOKE_RESOURCE \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region $REGION

# Configure /get-api-key POST method (no API key required, uses bundle ID)
echo "Configuring /get-api-key endpoint..."
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $GET_KEY_RESOURCE \
    --http-method POST \
    --authorization-type NONE \
    --api-key-required false \
    --region $REGION 2>/dev/null || true

GET_KEY_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${GET_KEY_FUNCTION}"
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $GET_KEY_RESOURCE \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${GET_KEY_LAMBDA_ARN}/invocations" \
    --region $REGION

# Add Lambda permissions for API Gateway
echo "Adding Lambda permissions..."
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id apigateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" \
    --region $REGION 2>/dev/null || true

aws lambda add-permission \
    --function-name $GET_KEY_FUNCTION \
    --statement-id apigateway-get-key \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" \
    --region $REGION 2>/dev/null || true

# Deploy API
echo "Deploying API to $STAGE_NAME stage..."
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $STAGE_NAME \
    --region $REGION > /dev/null

# Step 5: Create API Key and Usage Plan
echo ""
echo "Step 5: Creating API Key and Usage Plan..."

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

# Step 6: Create EventBridge Rule for Weekly Rotation
echo ""
echo "Step 6: Setting up weekly key rotation..."

RULE_NAME="redactor-key-rotation"

# Create rule (every Sunday at 2am AEST = 4pm Saturday UTC)
aws events put-rule \
    --name $RULE_NAME \
    --schedule-expression "cron(0 16 ? * SAT *)" \
    --description "Weekly API key rotation for Redactor" \
    --state ENABLED \
    --region $REGION > /dev/null

# Add permission for EventBridge to invoke Lambda
aws lambda add-permission \
    --function-name $ROTATE_KEY_FUNCTION \
    --statement-id eventbridge-rotation \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${REGION}:${ACCOUNT_ID}:rule/${RULE_NAME}" \
    --region $REGION 2>/dev/null || true

# Add Lambda as target
aws events put-targets \
    --rule $RULE_NAME \
    --targets "Id"="1","Arn"="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${ROTATE_KEY_FUNCTION}" \
    --region $REGION > /dev/null

echo "Weekly rotation scheduled: Sundays at 2am AEST"

# Step 7: Run Initial Key Rotation
echo ""
echo "Step 7: Running initial key rotation..."

aws lambda invoke \
    --function-name $ROTATE_KEY_FUNCTION \
    --region $REGION \
    /tmp/rotation-result.json > /dev/null

ROTATION_RESULT=$(cat /tmp/rotation-result.json)
echo "Rotation result: $ROTATION_RESULT"

# Step 8: Output results
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "Endpoints:"
echo "  Invoke:      https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/invoke"
echo "  Get API Key: https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/get-api-key"
echo ""
echo "Key Rotation:"
echo "  Schedule: Weekly (Sundays 2am AEST)"
echo "  Secret:   $SECRET_NAME"
echo ""
echo "Test get-api-key:"
echo "  curl -X POST \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'X-Bundle-Id: com.3bigthings.Redactor' \\"
echo "    https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/get-api-key"
echo ""
echo "=========================================="

# Save config
cat > /tmp/redactor-proxy-config.txt << EOF
API_ENDPOINT=https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/invoke
GET_KEY_ENDPOINT=https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/get-api-key
SECRET_NAME=$SECRET_NAME
EOF
echo "Configuration saved to /tmp/redactor-proxy-config.txt"
