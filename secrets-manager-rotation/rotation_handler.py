import json
import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def generate_new_secret(current_secret):
    # Naive rotation: if secret is JSON with 'password', append '-rot' for demo.
    try:
        data = json.loads(current_secret)
        if 'password' in data:
            data['password'] = data['password'] + '-rot'
        return json.dumps(data)
    except Exception:
        return current_secret + '-rot'


def lambda_handler(event, context):
    logger.info('Event: %s', json.dumps(event))
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    client = boto3.client('secretsmanager')

    try:
        metadata = client.describe_secret(SecretId=arn)
    except ClientError as e:
        logger.error('Error describing secret: %s', e)
        raise e

    if step == 'createSecret':
        # Get current secret value
        current = client.get_secret_value(SecretId=arn)['SecretString']
        new_secret = generate_new_secret(current)
        client.put_secret_value(SecretId=arn, ClientRequestToken=token, SecretString=new_secret, VersionStages=['AWSPENDING'])

    elif step == 'setSecret':
        # Nothing to do for demo
        pass

    elif step == 'testSecret':
        # Nothing to do for demo
        pass

    elif step == 'finishSecret':
        # Move AWSPENDING to AWSCURRENT
        client.update_secret_version_stage(SecretId=arn, VersionStage='AWSCURRENT', MoveToVersionId=token, RemoveFromVersionId=None)

    else:
        raise ValueError('Unknown step: ' + step)

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'ok'})
    }
