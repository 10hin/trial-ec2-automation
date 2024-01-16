#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json
import logging
import os
import urllib

import boto3


APPLICATION_NAME = 'user-notification-publish'
LOGGING_FORMAT = '%(asctime)s %(levelname)8s %(process)d --- [%(threadName)16s] %(name)-42s: %(message)s'
LOGGING_DATETIME_FORMAT = '%Y-%m-%dT%H:%M:%S%Z'
logging.basicConfig(format=LOGGING_FORMAT, datefmt=LOGGING_DATETIME_FORMAT)

LOGGER = logging.getLogger(APPLICATION_NAME)
LOGGER.setLevel(logging.INFO)

TASK_TOKEN_PARAMETER_KEY = 'task_token'
USER_DECISION_PARAMETER_KEY = 'decision'
IMAGE_ID_PARAMETER_KEY ='image_id'

def main(event, context):
    LOGGER.info('Hello!')
    LOGGER.info('event = %s', json.dumps(event))
    LOGGER.info('type(context) = %s', type(context))

    executionContext = event['ExecutionContext']
    taskToken = executionContext['Task']['Token']
    taskTokenURLSafe = urllib.parse.quote(taskToken, safe='')

    image_info = event['Input']['getImageResult']['Image']
    ami = image_info['OutputResources']['Amis'][0]
    imageID = ami['Image']

    baseURL = os.getenv('CALLBACK_LAMBDA_URL')
    if baseURL.endswith('/'):
        baseURL = baseURL[:-1]

    commonURL = f'{baseURL}/?{IMAGE_ID_PARAMETER_KEY}={imageID}&{TASK_TOKEN_PARAMETER_KEY}={taskTokenURLSafe}'
    approveURL = f'{commonURL}&{USER_DECISION_PARAMETER_KEY}=approve'
    rejectURL = f'{commonURL}&{USER_DECISION_PARAMETER_KEY}=reject'

    message = f'''
    AMI build DONE!

    Following AMIs are currently available:
    - Name: {ami['Name']}
        AccountId: {ami['AccountId']}
        Region: {ami['Region']}
        Image: {ami['Image']}
    

    -----
    APPROVE:
    To approve this image and deploy with replacing EC2 instance, click following link:
    {approveURL}

    -----
    REJECT:
    To reject this image and keep EC2 instance, click following link:
    {rejectURL}

    -----
    '''

    sns_client = boto3.client('sns')
    snsTopicARN = os.getenv('SNS_TOPIC_TO_PUBLISH_ARN')
    sns_client.publish(
        TopicArn = snsTopicARN,
        Subject = 'Test message from Lambda function',
        Message = message,
    )

    return {}

if __name__ == '__main__':
    main()
