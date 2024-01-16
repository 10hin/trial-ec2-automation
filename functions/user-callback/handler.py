#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json
import logging

import boto3


APPLICATION_NAME = 'user-callback'
LOGGING_FORMAT = '%(asctime)s %(levelname)8s %(process)d --- [%(threadName)16s] %(name)-42s: %(message)s'
LOGGING_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S%Z'
logging.basicConfig(format=LOGGING_FORMAT, datefmt=LOGGING_DATETIME_FORMAT)

LOGGER = logging.getLogger(APPLICATION_NAME)
LOGGER.setLevel(logging.INFO)

QUERY_STRING_PARAMETERS_KEY = 'queryStringParameters'
TASK_TOKEN_PARAMETER_KEY = 'task_token'
USER_DECISION_PARAMETER_KEY = 'decision'
IMAGE_ID_PARAMETER_KEY ='image_id'

def main(event, context):
    sfn = boto3.client('stepfunctions')
    if QUERY_STRING_PARAMETERS_KEY not in event:
        raise Exception('expected key not found in event')
    params = event[QUERY_STRING_PARAMETERS_KEY]

    if TASK_TOKEN_PARAMETER_KEY not in params:
        raise Exception(f'expected key not found in params: {TASK_TOKEN_PARAMETER_KEY}')
    task_token = params[TASK_TOKEN_PARAMETER_KEY]
    if USER_DECISION_PARAMETER_KEY not in params:
        raise Exception(f'expected key not found in params: {USER_DECISION_PARAMETER_KEY}')
    decision = params[USER_DECISION_PARAMETER_KEY]
    if IMAGE_ID_PARAMETER_KEY not in params:
        raise Exception(f'expected key not found in params: {IMAGE_ID_PARAMETER_KEY}')
    imageID = params[IMAGE_ID_PARAMETER_KEY]

    sfn.send_task_success(
        taskToken=task_token,
        output=json.dumps({
            'Payload': {
                'decision': decision,
                'imageID': [imageID],
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
