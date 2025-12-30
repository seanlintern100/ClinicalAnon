"""
Get API Key Lambda Function
Purpose: Return current API key from Secrets Manager to authenticated app
Organization: 3 Big Things
"""

import json
import boto3
from botocore.exceptions import ClientError

# Initialize clients
secrets_client = boto3.client('secretsmanager', region_name='ap-southeast-2')

# Configuration
SECRET_NAME = 'redactor/api-key'
ALLOWED_BUNDLE_IDS = [
    'com.3bigthings.Redactor',
    'com.3bigthings.ClinicalAnon',
]


def lambda_handler(event, context):
    """
    Return current API key from Secrets Manager.

    Security:
    - Validates X-Bundle-Id header against allowlist
    - Rate limited via API Gateway usage plan
    """
    try:
        # Get headers (case-insensitive)
        headers = event.get('headers', {}) or {}
        headers_lower = {k.lower(): v for k, v in headers.items()}

        # Validate bundle ID
        bundle_id = headers_lower.get('x-bundle-id', '')
        if bundle_id not in ALLOWED_BUNDLE_IDS:
            print(f'Invalid bundle ID: {bundle_id[:50]}')
            return error_response(403, 'Unauthorized application')

        # Fetch current API key from Secrets Manager
        try:
            response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
            secret_data = json.loads(response['SecretString'])
            api_key = secret_data.get('api_key')

            if not api_key:
                print('API key not found in secret')
                return error_response(500, 'Configuration error')

            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Cache-Control': 'no-store'  # Don't cache the key
                },
                'body': json.dumps({'apiKey': api_key})
            }

        except secrets_client.exceptions.ResourceNotFoundException:
            print('Secret not found')
            return error_response(500, 'Configuration error')
        except ClientError as e:
            print(f'Secrets Manager error: {e.response["Error"]["Code"]}')
            return error_response(500, 'Service error')

    except Exception as e:
        print(f'Error: {type(e).__name__}: {str(e)[:100]}')
        return error_response(500, 'Internal error')


def error_response(status_code, message):
    """Generate standardized error response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({'error': message})
    }
