import json
import boto3
import logging

# Configure logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2_client = boto3.client('ec2')
    
    logger.info(f"Event received: {json.dumps(event, indent=2)}")
    
    try:
        if event.get('httpMethod') == 'GET':
            logger.info("Handling GET request to list instances")
            response = ec2_client.describe_instances()
            instances = []
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    name = next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed')
                    instances.append({
                        'InstanceId': instance['InstanceId'],
                        'Name': name,
                        'InstanceType': instance['InstanceType'],
                        'State': instance['State']['Name']
                    })
            logger.info(f"Returning {len(instances)} instances")
            return {
                'statusCode': 200,
                'body': json.dumps(instances),
                'headers': {'Content-Type': 'application/json'}
            }
        
        elif event.get('httpMethod') == 'POST':
            body = json.loads(event.get('body', '{}'))
            instance_id = body.get('instanceId')
            action = event['path'].split('/')[-1]
            
            logger.info(f"Handling POST request: Action={action}, InstanceID={instance_id}")
            
            if not instance_id or action not in ['start', 'stop']:
                logger.error(f"Validation failed: InstanceID={instance_id}, Action={action}")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Missing instanceId or invalid action'})
                }
            
            if action == 'start':
                logger.info(f"Starting instance: {instance_id}")
                ec2_client.start_instances(InstanceIds=[instance_id])
                logger.info(f"Successfully started instance: {instance_id}")
            elif action == 'stop':
                logger.info(f"Stopping instance: {instance_id}")
                ec2_client.stop_instances(InstanceIds=[instance_id])
                logger.info(f"Successfully stopped instance: {instance_id}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({'message': f'{action.capitalize()}ed instance {instance_id}'})
            }
    
    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
