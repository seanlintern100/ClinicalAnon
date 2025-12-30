"""
Rotate API Key Lambda Function
Purpose: Automatically rotate API Gateway key and update Secrets Manager
Organization: 3 Big Things

Triggered by: EventBridge scheduled rule (weekly)
"""

import json
import boto3
import time
from datetime import datetime
from botocore.exceptions import ClientError

# Initialize clients
apigateway = boto3.client('apigateway', region_name='ap-southeast-2')
secrets_client = boto3.client('secretsmanager', region_name='ap-southeast-2')

# Configuration
SECRET_NAME = 'redactor/api-key'
USAGE_PLAN_NAME = 'redactor-usage-plan'
API_KEY_PREFIX = 'redactor-api-key'


def lambda_handler(event, context):
    """
    Rotate API key:
    1. Create new API Gateway key
    2. Associate with usage plan
    3. Update Secrets Manager with new key
    4. Delete old API Gateway key
    """
    print(f'Starting API key rotation at {datetime.utcnow().isoformat()}')

    try:
        # Step 1: Get current key ID from Secrets Manager
        old_key_id = get_current_key_id()
        print(f'Current key ID: {old_key_id}')

        # Step 2: Get usage plan ID
        usage_plan_id = get_usage_plan_id()
        if not usage_plan_id:
            raise Exception('Usage plan not found')
        print(f'Usage plan ID: {usage_plan_id}')

        # Step 3: Create new API key
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        new_key_name = f'{API_KEY_PREFIX}-{timestamp}'

        new_key_response = apigateway.create_api_key(
            name=new_key_name,
            description=f'Redactor API key created {timestamp}',
            enabled=True
        )
        new_key_id = new_key_response['id']
        new_key_value = new_key_response['value']
        print(f'Created new key: {new_key_id}')

        # Step 4: Associate new key with usage plan
        apigateway.create_usage_plan_key(
            usagePlanId=usage_plan_id,
            keyId=new_key_id,
            keyType='API_KEY'
        )
        print(f'Associated key with usage plan')

        # Step 5: Update Secrets Manager with new key
        update_secret(new_key_id, new_key_value)
        print('Updated Secrets Manager')

        # Step 6: Wait a moment for propagation
        time.sleep(5)

        # Step 7: Delete old key (if exists and different from new)
        if old_key_id and old_key_id != new_key_id:
            try:
                apigateway.delete_api_key(apiKey=old_key_id)
                print(f'Deleted old key: {old_key_id}')
            except apigateway.exceptions.NotFoundException:
                print(f'Old key already deleted: {old_key_id}')
            except Exception as e:
                # Log but don't fail - new key is already active
                print(f'Warning: Could not delete old key: {e}')

        print('API key rotation completed successfully')

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Key rotation successful',
                'newKeyId': new_key_id,
                'oldKeyId': old_key_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

    except Exception as e:
        print(f'Rotation failed: {type(e).__name__}: {str(e)}')
        # Don't expose details in response
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Key rotation failed'})
        }


def get_current_key_id():
    """Get current API key ID from Secrets Manager."""
    try:
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        secret_data = json.loads(response['SecretString'])
        return secret_data.get('key_id')
    except secrets_client.exceptions.ResourceNotFoundException:
        return None
    except Exception as e:
        print(f'Error getting current key: {e}')
        return None


def get_usage_plan_id():
    """Get the usage plan ID by name."""
    try:
        response = apigateway.get_usage_plans()
        for plan in response.get('items', []):
            if plan.get('name') == USAGE_PLAN_NAME:
                return plan['id']
        return None
    except Exception as e:
        print(f'Error getting usage plan: {e}')
        return None


def update_secret(key_id, key_value):
    """Update Secrets Manager with new key."""
    secret_data = {
        'api_key': key_value,
        'key_id': key_id,
        'rotated_at': datetime.utcnow().isoformat()
    }

    try:
        secrets_client.put_secret_value(
            SecretId=SECRET_NAME,
            SecretString=json.dumps(secret_data)
        )
    except secrets_client.exceptions.ResourceNotFoundException:
        # Secret doesn't exist, create it
        secrets_client.create_secret(
            Name=SECRET_NAME,
            Description='Redactor API Gateway key',
            SecretString=json.dumps(secret_data)
        )
