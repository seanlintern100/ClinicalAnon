"""
Bedrock Proxy Lambda Function
Purpose: Securely proxy requests to AWS Bedrock without exposing credentials to clients
Organization: 3 Big Things
"""

import json
import boto3
from botocore.config import Config

# Configure Bedrock client with retry settings
bedrock_config = Config(
    region_name='ap-southeast-2',
    retries={'max_attempts': 3, 'mode': 'adaptive'}
)

bedrock_runtime = boto3.client('bedrock-runtime', config=bedrock_config)

# Allowed model patterns (security: prevent model injection)
ALLOWED_MODEL_PATTERNS = [
    'anthropic.claude-',
    'apac.anthropic.claude-',
]

# Maximum tokens limit (cost protection)
MAX_TOKENS_LIMIT = 8192


def lambda_handler(event, context):
    """
    Main Lambda handler for Bedrock proxy requests.

    Expected request body:
    {
        "model": "anthropic.claude-3-5-haiku-20241022-v1:0",
        "messages": [{"role": "user", "content": "Hello"}],
        "system": "Optional system prompt",
        "max_tokens": 4096,
        "stream": false
    }
    """
    try:
        # Parse request body
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', event)

        # Validate required fields
        if 'messages' not in body:
            return error_response(400, 'Missing required field: messages')

        if 'model' not in body:
            return error_response(400, 'Missing required field: model')

        # Validate model (security: prevent model injection)
        model_id = body['model']
        if not any(model_id.startswith(pattern) for pattern in ALLOWED_MODEL_PATTERNS):
            return error_response(403, f'Model not allowed: {model_id}')

        # Validate and cap max_tokens (cost protection)
        max_tokens = min(body.get('max_tokens', 4096), MAX_TOKENS_LIMIT)

        # Build Bedrock request
        bedrock_body = {
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': max_tokens,
            'messages': body['messages']
        }

        # Add optional system prompt
        if 'system' in body and body['system']:
            bedrock_body['system'] = body['system']

        # Check if streaming requested
        if body.get('stream', False):
            return handle_streaming_request(model_id, bedrock_body)
        else:
            return handle_sync_request(model_id, bedrock_body)

    except json.JSONDecodeError:
        return error_response(400, 'Invalid JSON in request body')
    except Exception as e:
        # Log error type for debugging (but not details that could contain PII)
        print(f'Error processing request: {type(e).__name__}: {str(e)[:100]}')
        return error_response(500, 'Internal server error')


def handle_sync_request(model_id, bedrock_body):
    """Handle synchronous (non-streaming) Bedrock request."""
    try:
        response = bedrock_runtime.invoke_model(
            modelId=model_id,
            contentType='application/json',
            accept='application/json',
            body=json.dumps(bedrock_body)
        )

        response_body = json.loads(response['body'].read())

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }

    except bedrock_runtime.exceptions.ThrottlingException:
        return error_response(429, 'Rate limited. Please retry.')
    except bedrock_runtime.exceptions.AccessDeniedException as e:
        print(f'Access denied: {str(e)[:100]}')
        return error_response(403, 'Access denied to Bedrock model.')
    except bedrock_runtime.exceptions.ValidationException as e:
        print(f'Validation error: {str(e)[:200]}')
        return error_response(400, f'Invalid request: {str(e)[:100]}')
    except Exception as e:
        print(f'Bedrock error: {type(e).__name__}: {str(e)[:200]}')
        return error_response(502, 'Bedrock service error')


def handle_streaming_request(model_id, bedrock_body):
    """
    Handle streaming Bedrock request.
    Note: Lambda doesn't support true streaming responses.
    We collect all chunks and return as complete response.
    """
    try:
        response = bedrock_runtime.invoke_model_with_response_stream(
            modelId=model_id,
            contentType='application/json',
            accept='application/json',
            body=json.dumps(bedrock_body)
        )

        # Collect streamed chunks
        full_text = []
        for event in response['body']:
            if 'chunk' in event:
                chunk_data = json.loads(event['chunk']['bytes'])
                if chunk_data.get('type') == 'content_block_delta':
                    delta = chunk_data.get('delta', {})
                    if 'text' in delta:
                        full_text.append(delta['text'])

        # Return assembled response in Claude format
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'content': [{'type': 'text', 'text': ''.join(full_text)}],
                'stop_reason': 'end_turn'
            })
        }

    except Exception as e:
        print(f'Streaming error: {type(e).__name__}: {str(e)[:200]}')
        return error_response(502, 'Bedrock streaming error')


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
