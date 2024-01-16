#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json
import logging
import string

import boto3


APPLICATION_NAME = 'user-callback'
LOGGING_FORMAT = '%(asctime)s %(levelname)8s %(process)d --- [%(threadName)16s] %(name)-42s: %(message)s'
LOGGING_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S%Z'
logging.basicConfig(format=LOGGING_FORMAT, datefmt=LOGGING_DATETIME_FORMAT)

LOGGER = logging.getLogger(APPLICATION_NAME)
LOGGER.setLevel(logging.INFO)

QUERY_STRING_PARAMETERS_KEY = 'queryStringParameters'
BODY_KEY = 'body'
REQUEST_CONTEXT_KEY = 'requestContext'
HTTP_CONTEXT_KEY = 'http'
DOMAIN_NAME_KEY = 'domainName'
TASK_TOKEN_PARAMETER_KEY = 'task_token'
USER_DECISION_PARAMETER_KEY = 'decision'
IMAGE_ID_PARAMETER_KEY ='image_id'

with open('index.html') as f:
    html_template_str = f.read()
html_template = string.Template(html_template_str)


def main(event, context):
    # 関数URLによる呼び出しであることは前提とする。
    # event構造体のフィールドがなかったら失敗してよい(関数URLによる呼び出しではないから)
    reqCtx = event[REQUEST_CONTEXT_KEY]
    httpCtx = reqCtx[HTTP_CONTEXT_KEY]
    httpMethod = httpCtx['method']
    httpPath = httpCtx['path']
    
    if httpMethod == 'GET' and httpPath == '/':
        return get(event, context)
    if httpMethod == 'POST' and httpPath == '/':
        return post(event, context)
    if httpPath != '/':
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
            },
            'body': json.dumps({
                'message': f'not found',
            }),
            'isBase64Encoded': False,
        }
    return {
        'statusCode': 405,
        'headers': {
            'Content-Type': 'application/json',
        },
        'body': json.dumps({
            'message': f'method not allowed',
        }),
        'isBase64Encoded': False,
    }

def get(event, context):
    if QUERY_STRING_PARAMETERS_KEY not in event:
        raise Exception('expected key not found in event')
    params = event[QUERY_STRING_PARAMETERS_KEY]

    if TASK_TOKEN_PARAMETER_KEY not in params:
        raise Exception(f'expected key not found in params: {TASK_TOKEN_PARAMETER_KEY}')
    task_token = params[TASK_TOKEN_PARAMETER_KEY]
    if IMAGE_ID_PARAMETER_KEY not in params:
        raise Exception(f'expected key not found in params: {IMAGE_ID_PARAMETER_KEY}')
    image_id = params[IMAGE_ID_PARAMETER_KEY]

    reqCtx = event[REQUEST_CONTEXT_KEY]
    domainName = reqCtx[DOMAIN_NAME_KEY]

    html = html_template.safe_substitute({
        'task_token': task_token,
        'image_id': image_id,
        'lambda_url_domain_name': domainName,
    })

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/html; charset=utf-8',
        },
        'body': html,
        'isBase64Encoded': False,
    }

def post(event, context):
    sfn = boto3.client('stepfunctions')
    if BODY_KEY not in event:
        raise Exception('expected key not found in event')
    raw_body = event[BODY_KEY]
    body = json.loads(raw_body)

    if TASK_TOKEN_PARAMETER_KEY not in body:
        raise Exception(f'expected key not found in body: {TASK_TOKEN_PARAMETER_KEY}')
    task_token = body[TASK_TOKEN_PARAMETER_KEY]
    if USER_DECISION_PARAMETER_KEY not in body:
        raise Exception(f'expected key not found in body: {USER_DECISION_PARAMETER_KEY}')
    decision = body[USER_DECISION_PARAMETER_KEY]
    if IMAGE_ID_PARAMETER_KEY not in body:
        raise Exception(f'expected key not found in body: {IMAGE_ID_PARAMETER_KEY}')
    image_id = body[IMAGE_ID_PARAMETER_KEY]

    sfn.send_task_success(
        taskToken=task_token,
        output=json.dumps({
            'Payload': {
                'decision': decision,
                'imageID': [image_id],
            },
        }),
    )


    return {
        'statusCode': 201,
        'headers': {
            'Content-Type': 'application/json',
        },
        'body': json.dumps({
            'message': f'decision {decision} accepted successfully. You can cose this browser.',
        }),
        'isBase64Encoded': False,
    }


if __name__ == '__main__':
    main()
