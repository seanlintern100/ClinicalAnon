"""
Shared utilities for Lambda functions.
Organization: 3 Big Things
"""

import json


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


def success_response(body):
    """Generate standardized success response."""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body) if isinstance(body, dict) else body
    }
